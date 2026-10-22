import Foundation
import Security

// MARK: - 会话
//
// 「记住密码」要存的东西分两类，安全性要求不同：
//   · token / 密码 → Keychain（系统加密、可设 only-this-device）
//   · 服务器地址 / 用户名 / 记住密码开关 → UserDefaults（不敏感，方便登录页预填）
//
// 分开存的原因是：用户关掉「记住密码」时，只需要清掉密码那一项，
// 服务器地址和用户名留着，下次不用重新输。

struct Session: Equatable {
    var server: URL
    var token: String
    var username: String
}

enum Credentials {

    private static let service = "com.oaife.airpanel.v2"

    private enum Key {
        static let token = "session.token"
        static let password = "session.password"
        static let server = "pref.server"
        static let username = "pref.username"
        static let remember = "pref.remember"
    }

    // MARK: 明文偏好

    static var server: String {
        get { UserDefaults.standard.string(forKey: Key.server) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Key.server) }
    }

    static var username: String {
        get { UserDefaults.standard.string(forKey: Key.username) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Key.username) }
    }

    static var rememberPassword: Bool {
        get { UserDefaults.standard.bool(forKey: Key.remember) }
        set { UserDefaults.standard.set(newValue, forKey: Key.remember) }
    }

    // MARK: 会话

    /// 启动时恢复会话：token 在、地址在，就直接进主界面
    static func restore() -> Session? {
        guard
            let token = read(Key.token), !token.isEmpty,
            let raw = read(Key.server) ?? (server.isEmpty ? nil : server),
            let url = APIClient.normalize(raw)
        else { return nil }
        return Session(server: url, token: token, username: read(Key.username) ?? username)
    }

    static func save(_ session: Session, password: String?) {
        write(Key.token, session.token)
        write(Key.server, session.server.absoluteString)
        write(Key.username, session.username)
        UserDefaults.standard.set(session.server.absoluteString, forKey: Key.server)
        UserDefaults.standard.set(session.username, forKey: Key.username)

        if let password, !password.isEmpty {
            write(Key.password, password)
        } else {
            delete(Key.password)
        }
    }

    /// 登录页预填的密码（仅在「记住密码」开着时存在）
    static var savedPassword: String? {
        guard rememberPassword else { return nil }
        return read(Key.password)
    }

    static func clearSession() {
        delete(Key.token)
    }

    // MARK: Keychain 原子操作

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func read(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private static func write(_ account: String, _ value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        var q = query(account)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(q as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update: [String: Any] = [kSecValueData as String: data]
            return SecItemUpdate(query(account) as CFDictionary, update as CFDictionary) == errSecSuccess
        }
        return status == errSecSuccess
    }

    private static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
