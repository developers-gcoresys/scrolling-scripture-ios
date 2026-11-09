import Foundation
import FirebaseCore
import FirebaseAppCheck
import Security
import UIKit

enum FirebaseRuntime {
    static let isConfigured = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
    private static var didConfigure = false

    static func configure() {
        guard isConfigured, !didConfigure else { return }
        didConfigure = true
        FirebaseApp.configure()
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(AppAttestProviderFactory())
        #endif
    }
}

enum AppAccountTokenStore {
    private static let service = "com.gcoreapps.pro"
    private static let account = "appAccountToken"

    static func loadOrCreate() -> UUID {
        if let data = read(), let value = String(data: data, encoding: .utf8), let uuid = UUID(uuidString: value) {
            return uuid
        }
        let uuid = UUID()
        write(Data(uuid.uuidString.utf8))
        return uuid
    }

    private static func read() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func write(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }
}

extension UIApplication {
    var topViewController: UIViewController? {
        let scene = connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        guard var controller = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return nil }
        while let presented = controller.presentedViewController { controller = presented }
        return controller
    }
}
