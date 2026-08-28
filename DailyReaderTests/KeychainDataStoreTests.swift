import Security
import XCTest
@testable import DailyReader

final class KeychainDataStoreTests: XCTestCase {
    func testSaveAddsExactNamespaceAccessibilityAndSynchronizablePolicy() throws {
        let client = KeychainClientDouble()
        let store = KeychainDataStore(service: "test.service", client: client)

        try store.save(Data("secret".utf8), account: "account")

        XCTAssertEqual(client.added?[kSecAttrService as String] as? String, "test.service")
        XCTAssertEqual(client.added?[kSecAttrAccount as String] as? String, "account")
        XCTAssertEqual(client.added?[kSecAttrAccessible as String] as! CFString, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
        XCTAssertEqual(client.added?[kSecAttrSynchronizable as String] as? Bool, false)
    }

    func testUnexpectedReadStatusIsThrownInsteadOfReturningNil() {
        let client = KeychainClientDouble()
        client.copyStatus = errSecInteractionNotAllowed
        let store = KeychainDataStore(service: "test.service", client: client)

        XCTAssertThrowsError(try store.read(account: "account", migrateLegacy: false)) { error in
            XCTAssertEqual(error as? KeychainStoreError, .status(errSecInteractionNotAllowed))
        }
    }

    func testLegacyMigrationVerifiesNewValueBeforeDeletingPersistentReference() throws {
        let client = KeychainClientDouble()
        client.legacyData = Data("legacy".utf8)
        client.persistentReference = Data("persistent-ref".utf8)
        let store = KeychainDataStore(service: "test.service", client: client)

        XCTAssertEqual(try store.read(account: "account"), Data("legacy".utf8))
        XCTAssertEqual(client.deleted?[kSecValuePersistentRef as String] as? Data, client.persistentReference)
        XCTAssertNil(client.deleted?[kSecAttrAccount as String])
    }

    func testMigrationWriteFailureKeepsLegacyItem() {
        let client = KeychainClientDouble()
        client.legacyData = Data("legacy".utf8)
        client.addStatus = errSecInteractionNotAllowed
        let store = KeychainDataStore(service: "test.service", client: client)

        XCTAssertThrowsError(try store.read(account: "account"))
        XCTAssertNil(client.deleted)
    }

    func testMultipleLegacyCandidatesAreRejectedWithoutDeletion() {
        let client = KeychainClientDouble()
        client.legacyData = Data("legacy".utf8)
        client.legacyCandidateCount = 2
        let store = KeychainDataStore(service: "test.service", client: client)

        XCTAssertThrowsError(try store.read(account: "account")) { error in
            XCTAssertEqual(error as? KeychainStoreError, .ambiguousLegacyItems)
        }
        XCTAssertNil(client.deleted)
    }

    func testItemsWithAnotherServiceAreNotMigratedAsLegacy() throws {
        let client = KeychainClientDouble()
        client.legacyData = Data("other-service".utf8)
        client.legacyService = "another.namespaced.service"
        let store = KeychainDataStore(service: "test.service", client: client)

        XCTAssertNil(try store.read(account: "account"))
        XCTAssertNil(client.added)
        XCTAssertNil(client.deleted)
    }
}

private final class KeychainClientDouble: KeychainSecItemClient, @unchecked Sendable {
    var copyStatus: OSStatus?
    var addStatus: OSStatus = errSecSuccess
    var updateStatus: OSStatus = errSecItemNotFound
    var deleteStatus: OSStatus = errSecSuccess
    var legacyData: Data?
    var legacyService: String?
    var persistentReference = Data("persistent-ref".utf8)
    var legacyCandidateCount = 1
    var namespacedData: Data?
    var added: [String: Any]?
    var deleted: [String: Any]?

    func copyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        let values = query as NSDictionary
        if values[kSecAttrService as String] != nil {
            if let status = copyStatus { return status }
            guard let namespacedData else { return errSecItemNotFound }
            result?.pointee = namespacedData as CFData
            return errSecSuccess
        }
        guard let legacyData else { return errSecItemNotFound }
        var item: [String: Any] = [
            kSecValueData as String: legacyData,
            kSecValuePersistentRef as String: persistentReference
        ]
        if let legacyService {
            item[kSecAttrService as String] = legacyService
        }
        result?.pointee = Array(repeating: item, count: legacyCandidateCount) as CFArray
        return errSecSuccess
    }

    func add(_ attributes: CFDictionary) -> OSStatus {
        added = attributes as? [String: Any]
        if addStatus == errSecSuccess {
            namespacedData = added?[kSecValueData as String] as? Data
        }
        return addStatus
    }

    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        if updateStatus == errSecSuccess {
            namespacedData = (attributes as NSDictionary)[kSecValueData as String] as? Data
        }
        return updateStatus
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        deleted = query as? [String: Any]
        return deleteStatus
    }
}
