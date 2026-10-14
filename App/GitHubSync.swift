import Foundation
import Security

/// 把 measurements.csv 和蓝牙事件日志推到私有仓库，Mac 上的会话直接用 `gh api` 读取，不用插手机。
/// token 是只授权这一个仓库 Contents 读写的 fine-grained PAT，保存在钥匙串里。
enum GitHubSync {
    static let repo = "wayichao/afu-data"

    /// Mac 端通过文件共享放进来的 token；导入钥匙串后立即删除文件。
    static let tokenDropURL = URL.documentsDirectory.appending(path: "github_token.txt")

    enum SyncError: LocalizedError {
        case noToken
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .noToken: return "未配置 token"
            case let .http(code, body): return "HTTP \(code) \(body.prefix(120))"
            }
        }
    }

    @discardableResult
    static func importDroppedToken() -> Bool {
        guard let raw = try? String(contentsOf: tokenDropURL, encoding: .utf8) else { return false }
        try? FileManager.default.removeItem(at: tokenDropURL)
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return false }
        Keychain.save(token)
        return true
    }

    static var hasToken: Bool { Keychain.load() != nil }

    /// 内容与远端一致时不提交，避免每天产生空提交。
    static func upload(path: String, data: Data) async throws {
        guard let token = Keychain.load() else { throw SyncError.noToken }
        let url = URL(string: "https://api.github.com/repos/\(repo)/contents/\(path)")!

        func request(_ method: String) -> URLRequest {
            var r = URLRequest(url: url)
            r.httpMethod = method
            r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            r.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            return r
        }

        var body: [String: Any] = [
            "message": "sync \(path) from AFUScale",
            "content": data.base64EncodedString(),
            "committer": ["name": "AFUScale", "email": "39851118+wayichao@users.noreply.github.com"]
        ]
        // 文件已存在时 PUT 必须带当前 sha；404 说明是新文件。
        let (existing, getResponse) = try await URLSession.shared.data(for: request("GET"))
        let getCode = (getResponse as? HTTPURLResponse)?.statusCode ?? 0
        if getCode == 200, let json = try JSONSerialization.jsonObject(with: existing) as? [String: Any] {
            if let remote = json["content"] as? String,
               Data(base64Encoded: remote, options: .ignoreUnknownCharacters) == data {
                return
            }
            body["sha"] = json["sha"]
        } else if getCode != 404 {
            throw SyncError.http(getCode, String(decoding: existing, as: UTF8.self))
        }

        var put = request("PUT")
        put.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (result, putResponse) = try await URLSession.shared.data(for: put)
        let putCode = (putResponse as? HTTPURLResponse)?.statusCode ?? 0
        guard putCode == 200 || putCode == 201 else {
            throw SyncError.http(putCode, String(decoding: result, as: UTF8.self))
        }
    }

    private enum Keychain {
        private static let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "AFUScale.GitHubSync",
            kSecAttrAccount as String: "afu-data"
        ]

        static func save(_ token: String) {
            SecItemDelete(query as CFDictionary)
            var item = query
            item[kSecValueData as String] = Data(token.utf8)
            // 秤在后台唤醒 App 时设备可能是锁着的。
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(item as CFDictionary, nil)
        }

        static func load() -> String? {
            var q = query
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var out: AnyObject?
            guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }
}
