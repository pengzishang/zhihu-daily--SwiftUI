import Foundation
import SwiftUI

struct AIChatPresentation: Identifiable, Equatable {
    let id: UUID
    var sessionID: UUID
    var currentArticleContext: AIArticleContext?
}

@MainActor
final class AIChatCoordinator: ObservableObject {
    @Published private(set) var sessions: [AIChatSession] = []
    @Published var presentation: AIChatPresentation?
    @Published private(set) var isLoaded = false
    @Published private(set) var loadingError: String?

    let configurationStore: AIConfigurationStore
    private let sessionStore: AISessionStore
    private let chatService: AIChatServicing
    private let racingChatService: AIRacingChatServicing
    private var persistenceTask: Task<Void, Never>?
    private var persistenceRevision: UInt64 = 0

    init(
        configurationStore: AIConfigurationStore? = nil,
        sessionStore: AISessionStore = AISessionStore(),
        chatService: AIChatServicing = OpenAICompatibleChatService(),
        racingChatService: AIRacingChatServicing? = nil
    ) {
        self.configurationStore = configurationStore ?? AIConfigurationStore()
        self.sessionStore = sessionStore
        self.chatService = chatService
        self.racingChatService = racingChatService ?? AIRacingChatService(transport: chatService)
    }

    func loadIfNeeded() async {
        guard !isLoaded else { return }
        do {
            let persistedSessions = try await sessionStore.load()
            var mergedByID = Dictionary(uniqueKeysWithValues: persistedSessions.map { ($0.id, $0) })
            for session in sessions {
                if let persisted = mergedByID[session.id] {
                    mergedByID[session.id] = session.updatedAt >= persisted.updatedAt ? session : persisted
                } else {
                    mergedByID[session.id] = session
                }
            }
            sessions = mergedByID.values.sorted { $0.updatedAt > $1.updatedAt }
            loadingError = nil
        } catch {
            loadingError = "对话记录读取失败，请重试"
        }
        isLoaded = true
        if !sessions.isEmpty {
            persist()
        }
    }

    func openIndependentChat() {
        let session: AIChatSession
        if let existing = sessions.first(where: { $0.articleContext == nil }) {
            session = existing
        } else {
            session = createSession(articleContext: nil, draft: "")
        }
        presentation = AIChatPresentation(id: UUID(), sessionID: session.id, currentArticleContext: nil)
    }

    func openArticleChat(context: AIArticleContext, selectedText: String? = nil) {
        var context = context
        context.focusedSelection = selectedText
        let session: AIChatSession
        if selectedText?.isEmpty == false {
            session = createSession(articleContext: context, draft: selectedText ?? "")
        } else if let existing = sessions.first(where: { $0.articleContext?.id == context.id }) {
            session = existing
        } else {
            session = createSession(articleContext: context, draft: "")
        }
        presentation = AIChatPresentation(id: UUID(), sessionID: session.id, currentArticleContext: context)
    }

    func dismiss() {
        presentation = nil
    }

    func session(id: UUID) -> AIChatSession? {
        sessions.first(where: { $0.id == id })
    }

    func selectSession(id: UUID) {
        guard let current = presentation, sessions.contains(where: { $0.id == id }) else { return }
        presentation = AIChatPresentation(
            id: UUID(),
            sessionID: id,
            currentArticleContext: current.currentArticleContext
        )
    }

    @discardableResult
    func newSession(articleContext: AIArticleContext? = nil, draft: String = "") -> AIChatSession {
        let session = createSession(articleContext: articleContext, draft: draft)
        if let current = presentation {
            presentation = AIChatPresentation(
                id: UUID(),
                sessionID: session.id,
                currentArticleContext: current.currentArticleContext
            )
        }
        return session
    }

    func update(_ session: AIChatSession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index] = session
        sortAndPersist()
    }

    func deleteSession(id: UUID) {
        sessions.removeAll { $0.id == id }
        if let current = presentation, current.sessionID == id {
            if let next = sessions.first {
                presentation = AIChatPresentation(
                    id: UUID(),
                    sessionID: next.id,
                    currentArticleContext: current.currentArticleContext
                )
            } else {
                let replacement = createSession(articleContext: current.currentArticleContext, draft: "")
                presentation = AIChatPresentation(
                    id: UUID(),
                    sessionID: replacement.id,
                    currentArticleContext: current.currentArticleContext
                )
            }
        }
        persist()
    }

    func renameSession(id: UUID, title: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        sessions[index].title = normalized
        sessions[index].updatedAt = Date()
        sortAndPersist()
    }

    func replaceContext(sessionID: UUID, with context: AIArticleContext) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].articleContext = context
        sessions[index].updatedAt = Date()
        sortAndPersist()
    }

    func makeChatViewModel(sessionID: UUID) -> AIChatViewModel {
        AIChatViewModel(
            sessionID: sessionID,
            coordinator: self,
            configurationStore: configurationStore,
            chatService: chatService,
            racingChatService: racingChatService
        )
    }

    private func createSession(articleContext: AIArticleContext?, draft: String) -> AIChatSession {
        let session = AIChatSession(
            title: articleContext.map { Self.sessionTitle(for: $0.title) } ?? "新对话",
            articleContext: articleContext,
            draft: draft
        )
        sessions.insert(session, at: 0)
        persist()
        return session
    }

    private static func sessionTitle(for articleTitle: String) -> String {
        let trimmed = articleTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 24 ? String(trimmed.prefix(24)) + "…" : trimmed
    }

    private func sortAndPersist() {
        sessions.sort { $0.updatedAt > $1.updatedAt }
        persist()
    }

    private func persist() {
        guard isLoaded else { return }
        persistenceRevision = persistenceRevision == UInt64.max ? UInt64.max : persistenceRevision + 1
        let revision = persistenceRevision
        let snapshot = sessions
        persistenceTask?.cancel()
        persistenceTask = Task { [sessionStore] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            try? await sessionStore.save(snapshot, revision: revision)
        }
    }
}

@MainActor
final class AIChatViewModel: ObservableObject {
    @Published private(set) var session: AIChatSession
    @Published var draft: String
    @Published private(set) var isGenerating = false
    @Published private(set) var errorMessage: String?

    private let sessionID: UUID
    private weak var coordinator: AIChatCoordinator?
    private let configurationStore: AIConfigurationStore
    private let chatService: AIChatServicing
    private let racingChatService: AIRacingChatServicing
    private var generationTask: Task<Void, Never>?

    @Published private(set) var isThinking = false

    init(
        sessionID: UUID,
        coordinator: AIChatCoordinator,
        configurationStore: AIConfigurationStore,
        chatService: AIChatServicing,
        racingChatService: AIRacingChatServicing? = nil
    ) {
        self.sessionID = sessionID
        self.coordinator = coordinator
        self.configurationStore = configurationStore
        self.chatService = chatService
        self.racingChatService = racingChatService ?? AIRacingChatService(transport: chatService)
        let fallback = AIChatSession(id: sessionID, title: "新对话")
        let initialSession = coordinator.session(id: sessionID) ?? fallback
        self.session = initialSession
        self.draft = initialSession.draft
    }

    var canSend: Bool {
        !isGenerating && configurationStore.isReady && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasAvailableProviders: Bool {
        configurationStore.isReady
    }

    var providerSummary: String {
        configurationStore.enabledProviderSummary
    }

    func refreshFromCoordinator() {
        guard let latest = coordinator?.session(id: sessionID) else { return }
        session = latest
        draft = latest.draft
    }

    func updateDraft(_ value: String) {
        draft = value
        session.draft = value
        coordinator?.update(session)
    }

    func send(prompt: String) {
        let content = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isGenerating else { return }
        updateDraft(content)
        send()
    }

    func send() {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isGenerating else { return }
        guard configurationStore.isReady else {
            errorMessage = AIChatError.noAvailableProviders.errorDescription
            return
        }
        session.messages.append(AIChatMessage(role: .user, content: content))
        session.draft = ""
        session.updatedAt = Date()
        if session.title == "新对话" {
            session.title = Self.generatedTitle(from: content)
        }
        draft = ""
        coordinator?.update(session)
        startGeneration()
    }

    func stop() {
        guard isGenerating else { return }
        generationTask?.cancel()
    }

    func retryLast() {
        guard !isGenerating,
              session.messages.last(where: { $0.role == .user }) != nil else { return }
        while let last = session.messages.last, last.role == .assistant {
            session.messages.removeLast()
        }
        session.draft = ""
        session.updatedAt = Date()
        draft = ""
        coordinator?.update(session)
        startGeneration()
    }

    func replaceArticleContext(_ context: AIArticleContext) {
        session.articleContext = context
        session.updatedAt = Date()
        coordinator?.update(session)
    }

    private func startGeneration() {
        guard !isGenerating else { return }
        errorMessage = nil
        isThinking = false
        let assistantID = UUID()
        session.messages.append(
            AIChatMessage(id: assistantID, role: .assistant, content: "", state: .streaming)
        )
        session.updatedAt = Date()
        coordinator?.update(session)
        isGenerating = true

        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let providers = configurationStore.runtimeProviders()
                guard !providers.isEmpty else { throw AIChatError.noAvailableProviders }
                let history = session.messages.filter { $0.id != assistantID }
                for try await event in racingChatService.streamReply(
                    providers: providers,
                    messages: history,
                    articleContext: session.articleContext
                ) {
                    try Task.checkCancellation()
                    apply(event, to: assistantID)
                }
                finishMessage(id: assistantID, state: .complete)
            } catch is CancellationError {
                finishMessage(id: assistantID, state: .interrupted)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                finishMessage(id: assistantID, state: .failed)
            }
            isThinking = false
            isGenerating = false
            generationTask = nil
        }
    }

    private func apply(_ event: AIStreamEvent, to messageID: UUID) {
        guard let index = session.messages.firstIndex(where: { $0.id == messageID }) else { return }
        switch event {
        case .thinking:
            isThinking = true
        case .providerSelected(_, let name):
            session.messages[index].providerName = name
        case .text(let delta):
            isThinking = false
            session.messages[index].content += delta
        case .searchStatus(let summary):
            session.messages[index].searchSummary = summary
        case .citations(let citations):
            session.messages[index].citations = citations
        case .finished:
            break
        }
        session.updatedAt = Date()
        coordinator?.update(session)
    }

    private func finishMessage(id: UUID, state: AIMessageState) {
        guard let index = session.messages.firstIndex(where: { $0.id == id }) else { return }
        session.messages[index].state = state
        session.updatedAt = Date()
        coordinator?.update(session)
    }

    private static func generatedTitle(from content: String) -> String {
        let singleLine = content.replacingOccurrences(of: "\n", with: " ")
        return singleLine.count > 24 ? String(singleLine.prefix(24)) + "…" : singleLine
    }
}
