import Foundation

/// 阅读状态持久化键名集中定义。
///
/// UserDefaults 与 Keychain 冗余备份共用同一组 account 名。统一在此声明，
/// 避免 `HomeViewModel` / `AppRootView` 等多处的裸字符串漂移导致状态不同步。
enum ReadingStateKeys {
    /// 已读故事 ID 列表（`[Int]`，存于 UserDefaults）。
    static let readStoryIDs = "DailyReader.readStoryIDs"
    /// 冷宫（不感兴趣）列表（`[HiddenStory]` 的 JSON `Data`）。
    static let hiddenStories = "DailyReader.hiddenStories"
    /// 收藏列表（`[FavoriteStory]` 的 JSON `Data`）。
    static let favoriteStories = "DailyReader.favoriteStories"
    /// 已读明细列表（`[ReadStory]` 的 JSON `Data`）。
    static let readStories = "DailyReader.readStories"
}
