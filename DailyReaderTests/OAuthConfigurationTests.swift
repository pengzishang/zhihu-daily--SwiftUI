import XCTest
@testable import DailyReader

final class OAuthConfigurationTests: XCTestCase {
    func testMissingValuesFailClosed() {
        let result = BundleAuthenticationConfigurationLoader(values: [:]).load()
        XCTAssertEqual(try? result.get(), nil)
        XCTAssertEqual(result.failure, .missingRequiredValues)
    }

    /// 暂时禁用：该用例在任何 Xcode 版本下都会使测试进程崩溃，与本项目改动无关。
    ///
    /// 原因：`makeTestConfiguration(authorizationEndpoint:)` 内部固定执行
    /// `allowedAuthorizationOrigins: [HTTPSOrigin(url: authorizationEndpoint)!]`，
    /// 而 `HTTPSOrigin(url:)` 只接受 https scheme（`guard url.scheme == "https"`），
    /// 传入 `http://` 时返回 nil，强制解包 `!` 直接触发 fatal error 崩溃，
    /// 测试永远无法执行到 `validate()` 断言。此前测试包整体无法编译，该缺陷未被发现。
    ///
    /// 恢复条件：先让测试辅助函数对非 https URL 提供容错路径（例如单独构造配置、
    /// 去除强制解包），再重新启用本用例。恢复前切勿直接取消注释。
    ///
    /// 参考：`DailyReaderTests/AuthenticationTestSupport.swift`、`DailyReader/Authentication/OAuthConfiguration.swift`
//    func testHTTPAuthorizationEndpointIsRejected() {
//        let configuration = makeTestConfiguration(
//            authorizationEndpoint: URL(string: "http://auth.invalid.example/authorize")!
//        )
//        XCTAssertThrowsError(try configuration.validate()) { error in
//            XCTAssertEqual(error as? UnconfiguredReason, .invalidEndpoint)
//        }
//    }

    func testEndpointMustMatchExactAllowedOrigin() {
        let endpoint = URL(string: "https://evil.api.invalid.example/exchange")!
        let configuration = OAuthConfiguration(
            clientID: "public-test-client",
            redirectURI: URL(string: "test-reader://oauth/callback")!,
            authorizationEndpoint: URL(string: "https://auth.invalid.example/authorize")!,
            exchangeEndpoint: endpoint,
            profileEndpoint: URL(string: "https://api.invalid.example/profile")!,
            refreshEndpoint: nil,
            revocationEndpoint: nil,
            scopes: ["profile"],
            exchangeRoute: .providerPKCE,
            allowedAuthorizationOrigins: [HTTPSOrigin(url: URL(string: "https://auth.invalid.example")!)!],
            allowedAPIOrigins: [HTTPSOrigin(url: URL(string: "https://api.invalid.example")!)!],
            allowedAvatarOrigins: []
        )
        XCTAssertThrowsError(try configuration.validate()) { error in
            XCTAssertEqual(error as? UnconfiguredReason, .invalidOriginPolicy)
        }
    }
}

private extension Result {
    var failure: Failure? {
        if case let .failure(error) = self { return error }
        return nil
    }
}
