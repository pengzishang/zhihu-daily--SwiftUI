import Foundation

/// 双轨灰度开关：默认 false = 走 WebView（零回归）；true = 走原生渲染。
/// 同一 `UserDefaults` 键被设置页的 `@AppStorage` 与读取处共享。
enum FeatureFlag {
    static var useNativeBody: Bool {
        get { UserDefaults.standard.bool(forKey: "DailyReader.useNativeBody") }
        set { UserDefaults.standard.set(newValue, forKey: "DailyReader.useNativeBody") }
    }
}
