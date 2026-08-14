import Foundation

/// 阅读状态初始快照：从 UserDefaults / Keychain 恢复后的四类状态。
struct ReadingStateSnapshot {
    var readStoryIDs: Set<Int>
    var hiddenStories: [HiddenStory]
    var favoriteStories: [FavoriteStory]
    var readStories: [ReadStory]
}

/// 阅读状态加载器：从 UserDefaults 读取，缺失时从 Keychain 冗余备份恢复并写回，
/// 并在任一方向恢复后做一致性校正。
///
/// 把原 `HomeViewModel.init` 内联的恢复逻辑抽出，使 init 仅负责装配，
/// 恢复/校正/双写策略集中在可单测的纯函数里。
enum ReadingStateLoader {
    static func load(
        defaults: UserDefaults,
        backup: any ReadingStateBackingUp,
        keychainErrorHandler: @escaping @Sendable (Error) -> Void
    ) -> ReadingStateSnapshot {
        func readBackup(for account: String) -> Data? {
            do {
                return try backup.read(account: account)
            } catch {
                keychainErrorHandler(error)
                return nil
            }
        }
        func saveBackup(_ data: Data, for account: String) {
            do {
                try backup.save(data, account: account)
            } catch {
                keychainErrorHandler(error)
            }
        }
        func deleteBackup(for account: String) {
            do {
                try backup.delete(account: account)
            } catch {
                keychainErrorHandler(error)
            }
        }

        let readIDs = defaults.array(forKey: ReadingStateKeys.readStoryIDs) as? [Int]
        let hiddenData = defaults.data(forKey: ReadingStateKeys.hiddenStories)
        let favoriteData = defaults.data(forKey: ReadingStateKeys.favoriteStories)
        let readData = defaults.data(forKey: ReadingStateKeys.readStories)

        let isUserDefaultsEmpty = (readIDs == nil || (readIDs?.isEmpty ?? true)) &&
            hiddenData == nil &&
            favoriteData == nil &&
            readData == nil

        var readStoryIDs: Set<Int>
        var hiddenStories: [HiddenStory]
        var favoriteStories: [FavoriteStory]
        var readStories: [ReadStory]

        if isUserDefaultsEmpty {
            // UserDefaults 为空 → 从 Keychain 冗余备份恢复并写回 UserDefaults。
            readStoryIDs = []
            hiddenStories = []
            favoriteStories = []
            readStories = []

            if let data = readBackup(for: ReadingStateKeys.readStoryIDs) {
                if ProcessInfo.processInfo.environment["MOCK_KEYCHAIN_STATUS"] == "corrupted" {
                    deleteBackup(for: ReadingStateKeys.readStoryIDs)
                } else if let list = try? JSONDecoder().decode([Int].self, from: data) {
                    readStoryIDs = Set(list)
                    defaults.set(list, forKey: ReadingStateKeys.readStoryIDs)
                } else {
                    deleteBackup(for: ReadingStateKeys.readStoryIDs)
                    defaults.removeObject(forKey: ReadingStateKeys.readStoryIDs)
                }
            }

            if let data = readBackup(for: ReadingStateKeys.hiddenStories) {
                if ProcessInfo.processInfo.environment["MOCK_KEYCHAIN_STATUS"] == "corrupted" {
                    deleteBackup(for: ReadingStateKeys.hiddenStories)
                } else if let list = try? JSONDecoder().decode([HiddenStory].self, from: data) {
                    hiddenStories = list
                    defaults.set(data, forKey: ReadingStateKeys.hiddenStories)
                } else {
                    deleteBackup(for: ReadingStateKeys.hiddenStories)
                    defaults.removeObject(forKey: ReadingStateKeys.hiddenStories)
                }
            }

            if let data = readBackup(for: ReadingStateKeys.favoriteStories) {
                if ProcessInfo.processInfo.environment["MOCK_KEYCHAIN_STATUS"] == "corrupted" {
                    deleteBackup(for: ReadingStateKeys.favoriteStories)
                } else if let list = try? JSONDecoder().decode([FavoriteStory].self, from: data) {
                    favoriteStories = list
                    defaults.set(data, forKey: ReadingStateKeys.favoriteStories)
                } else {
                    deleteBackup(for: ReadingStateKeys.favoriteStories)
                    defaults.removeObject(forKey: ReadingStateKeys.favoriteStories)
                }
            }

            if let data = readBackup(for: ReadingStateKeys.readStories) {
                if ProcessInfo.processInfo.environment["MOCK_KEYCHAIN_STATUS"] == "corrupted" {
                    deleteBackup(for: ReadingStateKeys.readStories)
                } else if let list = try? JSONDecoder().decode([ReadStory].self, from: data) {
                    readStories = list
                    defaults.set(data, forKey: ReadingStateKeys.readStories)
                } else {
                    deleteBackup(for: ReadingStateKeys.readStories)
                    defaults.removeObject(forKey: ReadingStateKeys.readStories)
                }
            }
        } else {
            // UserDefaults 有值 → 直接解码；若 Keychain 为空则反向备份（T2-KC-04）。
            readStoryIDs = Set(readIDs ?? [])

            if let data = hiddenData,
               let list = try? JSONDecoder().decode([HiddenStory].self, from: data) {
                hiddenStories = list
            } else {
                hiddenStories = []
            }

            if let data = favoriteData,
               let list = try? JSONDecoder().decode([FavoriteStory].self, from: data) {
                favoriteStories = list
            } else {
                favoriteStories = []
            }

            if let data = readData,
               let list = try? JSONDecoder().decode([ReadStory].self, from: data) {
                readStories = list
            } else {
                readStories = []
            }

            let kcReadData = readBackup(for: ReadingStateKeys.readStoryIDs)
            if kcReadData == nil {
                if !readStoryIDs.isEmpty {
                    if let data = try? JSONEncoder().encode(Array(readStoryIDs)) {
                        saveBackup(data, for: ReadingStateKeys.readStoryIDs)
                    }
                }
                if let data = hiddenData {
                    saveBackup(data, for: ReadingStateKeys.hiddenStories)
                }
                if let data = favoriteData {
                    saveBackup(data, for: ReadingStateKeys.favoriteStories)
                }
                if let data = readData {
                    saveBackup(data, for: ReadingStateKeys.readStories)
                }
            }
        }

        // 校正阅读状态一致性：readStoryIDs 必须以 readStories 明细为准。
        // 二者可能从 UserDefaults / Keychain 两条通道分别恢复而错位，
        // 一旦出现「无明细的幽灵已读 ID」，首页会把文章全部当成已读隐藏，
        // 而「已读」列表（依赖 readStories）却为空，表现为首页文章"全部消失"。
        let reconciledReadIDs = Set(readStories.map { $0.id })
        if reconciledReadIDs != readStoryIDs {
            readStoryIDs = reconciledReadIDs
            defaults.set(Array(reconciledReadIDs), forKey: ReadingStateKeys.readStoryIDs)
            if let data = try? JSONEncoder().encode(Array(reconciledReadIDs)) {
                saveBackup(data, for: ReadingStateKeys.readStoryIDs)
            }
        }

        return ReadingStateSnapshot(
            readStoryIDs: readStoryIDs,
            hiddenStories: hiddenStories,
            favoriteStories: favoriteStories,
            readStories: readStories
        )
    }
}
