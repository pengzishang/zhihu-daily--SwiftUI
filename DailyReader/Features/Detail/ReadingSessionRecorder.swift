import Foundation

/// 阅读会话停留记录器：复用 `ContinuousClock` + `scenePhase` 思路累计前台活跃停留。
///
/// 与 `ReadQualificationTimer`（用于「标为已读」资格判定，10s）解耦：本记录器
/// 累计用户在详情页的**全部**前台活跃停留时长，供兴趣信号采集落盘。
///
/// 不隔离到 MainActor：仅使用 `ContinuousClock` / `Duration`，无任何 UI 依赖，便于在
/// `@State` 默认值中直接构造（避免 main-actor-isolated 初始化器在 nonisolated 上下文报错）。
final class ReadingSessionRecorder {
    private let now: () -> ContinuousClock.Instant
    private var accumulated: Duration = .zero
    private var activeSince: ContinuousClock.Instant?

    init(now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.now = now
    }

    /// 进入前台：开始（或恢复）累计。
    func resume() {
        if activeSince == nil {
            activeSince = now()
        }
    }

    /// 离开前台 / 提交：暂停累计，把当前段并入累计值。
    func pause() {
        guard let activeSince else { return }
        accumulated += activeSince.duration(to: now())
        self.activeSince = nil
    }

    /// 提交后重置，避免重复累计。
    func reset() {
        accumulated = .zero
        activeSince = nil
    }

    /// 当前累计的前台活跃停留秒数（含正在进行的这一段）。
    var elapsedActiveTime: TimeInterval {
        let active = activeSince.map { $0.duration(to: now()) } ?? .zero
        return (accumulated + active).asTimeInterval
    }
}

private extension Duration {
    var asTimeInterval: TimeInterval {
        let components = self.components
        return Double(components.seconds) + (Double(components.attoseconds) / 1e18)
    }
}
