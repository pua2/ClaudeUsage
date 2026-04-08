import Foundation
import Security
import CommonCrypto
import SQLite3
import WebKit

// MARK: - Usage Data

struct UsageData {
    let sessionPct: Double      // 0–100; nil resetsAt means no active session window
    let sessionResetsAt: Date?
    let weeklyPct: Double       // 0–100
    let weeklyResetsAt: Date?
}

// MARK: - ClaudeAuth

enum ClaudeAuth {

    static func fetchUsage() async -> UsageData? {
        let creds: (sessionKey: String, orgId: String, cookieHeader: String)? = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: readCredentials())
            }
        }
        guard let creds else { return nil }
        return await callUsageAPI(sessionKey: creds.sessionKey, orgId: creds.orgId, cookieHeader: creds.cookieHeader)
    }

    // MARK: - Credentials

    private static func readCredentials() -> (sessionKey: String, orgId: String, cookieHeader: String)? {
        guard let password = readKeychain(service: "Claude Safe Storage"),
              let aesKey   = deriveAESKey(from: password) else { return nil }

        let dbPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/Cookies").path

        let all = readAllCookies(from: dbPath, key: aesKey)
        guard let sessionKey = all["sessionKey"], !sessionKey.isEmpty,
              let orgId      = all["lastActiveOrg"], !orgId.isEmpty else { return nil }

        let cookieHeader = all.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
        return (sessionKey, orgId, cookieHeader)
    }

    private static func readAllCookies(from dbPath: String, key: Data) -> [String: String] {
        var result = [String: String]()
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return result }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db,
            "SELECT name, encrypted_value FROM cookies WHERE host_key LIKE '%.claude%'",
            -1, &stmt, nil) == SQLITE_OK else { return result }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let nameCStr = sqlite3_column_text(stmt, 0) else { continue }
            let name = String(cString: nameCStr)
            let len  = Int(sqlite3_column_bytes(stmt, 1))
            guard len > 0, let blob = sqlite3_column_blob(stmt, 1) else { continue }
            let encrypted = Data(bytes: blob, count: len)
            if let val = decryptChromeValue(encrypted, key: key), !val.isEmpty {
                result[name] = val
            }
        }
        return result
    }

    // MARK: - Keychain

    private static func readKeychain(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var item: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Key Derivation (Chromium PBKDF2-SHA1)

    private static func deriveAESKey(from password: String) -> Data? {
        guard let passData = password.data(using: .utf8) else { return nil }
        let salt = Array("saltysalt".utf8)
        var key  = [UInt8](repeating: 0, count: 16)
        let rc = passData.withUnsafeBytes { passPtr in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passPtr.bindMemory(to: Int8.self).baseAddress, passData.count,
                salt, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                1003,
                &key, 16
            )
        }
        return rc == kCCSuccess ? Data(key) : nil
    }

    // MARK: - SQLite

    private static func readAndDecryptCookie(_ name: String, from dbPath: String, key: Data) -> String? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db,
            "SELECT encrypted_value FROM cookies WHERE name=? LIMIT 1", -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        name.withCString { cStr in sqlite3_bind_text(stmt, 1, cStr, -1, nil) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        let blobLen = Int(sqlite3_column_bytes(stmt, 0))
        guard let blob = sqlite3_column_blob(stmt, 0), blobLen > 0 else { return nil }

        let encrypted = Data(bytes: blob, count: blobLen)
        return decryptChromeValue(encrypted, key: key)
    }

    // MARK: - AES-128-CBC ("v10" prefix, 16-space IV)

    private static func decryptChromeValue(_ encrypted: Data, key: Data) -> String? {
        guard encrypted.count > 3 else { return nil }
        let ciphertext = encrypted.dropFirst(3)
        let iv = [UInt8](repeating: 0x20, count: kCCBlockSizeAES128)
        var out = [UInt8](repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
        var outLen = 0

        let rc = ciphertext.withUnsafeBytes { ct in
            key.withUnsafeBytes { k in
                CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES128),
                        CCOptions(kCCOptionPKCS7Padding),
                        k.baseAddress, 16, iv,
                        ct.baseAddress, ciphertext.count,
                        &out, out.count, &outLen)
            }
        }
        guard rc == kCCSuccess else { return nil }

        let decrypted = Data(out.prefix(outLen))
        var best = Data(), cur = Data()
        for byte in decrypted {
            if byte >= 0x20 && byte < 0x7F { cur.append(byte) }
            else { if cur.count > best.count { best = cur }; cur = Data() }
        }
        if cur.count > best.count { best = cur }

        guard var val = String(data: best, encoding: .ascii), !val.isEmpty else { return nil }
        if val.hasPrefix("`") { val = String(val.dropFirst()) }
        return val
    }

    // MARK: - API Call (WKWebView)

    private static func callUsageAPI(sessionKey: String, orgId: String, cookieHeader: String) async -> UsageData? {
        // URLSession and curl are blocked by Cloudflare's TLS fingerprinting.
        // WKWebView uses Safari's engine — it can solve Cloudflare JS challenges automatically.
        // We exclude Chrome's cf_clearance (fingerprint-tied) so WKWebView gets its own.
        let cfCookies: Set<String> = ["cf_clearance", "__cf_bm", "__cflb"]
        let cookies: [HTTPCookie] = cookieHeader.components(separatedBy: "; ").compactMap { pair in
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2, !cfCookies.contains(kv[0]) else { return nil }
            return HTTPCookie(properties: [
                .name: kv[0], .value: kv[1], .domain: ".claude.ai", .path: "/"
            ])
        }

        return await MainActor.run { UsageFetcher(orgId: orgId) }.fetch(cookies: cookies)
    }

    fileprivate static func parseUsageResponse(_ data: Data) -> UsageData? {
        struct Period: Decodable {
            let utilization: Double
            let resetsAt: String?
            enum CodingKeys: String, CodingKey {
                case utilization; case resetsAt = "resets_at"
            }
            var date: Date? {
                guard let resetsAt else { return nil }
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return f.date(from: resetsAt)
            }
        }
        struct Response: Decodable {
            let fiveHour: Period?
            let sevenDay: Period?
            enum CodingKeys: String, CodingKey {
                case fiveHour = "five_hour"; case sevenDay = "seven_day"
            }
        }
        guard let r = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        return UsageData(
            sessionPct:      r.fiveHour?.utilization ?? 0,
            sessionResetsAt: r.fiveHour?.date ?? nil,
            weeklyPct:       r.sevenDay?.utilization ?? 0,
            weeklyResetsAt:  r.sevenDay?.date ?? nil
        )
    }
}

// MARK: - WKWebView Usage Fetcher

@MainActor
private final class UsageFetcher: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let orgId: String
    private var cont: CheckedContinuation<UsageData?, Never>?
    private var navCount = 0
    private var timeoutItem: DispatchWorkItem?

    init(orgId: String) {
        self.orgId = orgId
        self.webView = WKWebView(frame: .zero)
        super.init()
        self.webView.navigationDelegate = self
    }

    func fetch(cookies: [HTTPCookie]) async -> UsageData? {
        await withCheckedContinuation { [self] cont in
            self.cont = cont
            let store = webView.configuration.websiteDataStore.httpCookieStore
            var remaining = cookies.count == 0 ? 1 : cookies.count
            let proceed = {
                remaining -= 1
                guard remaining == 0 else { return }
                let url = URL(string: "https://claude.ai/api/organizations/\(self.orgId)/usage")!
                self.webView.load(URLRequest(url: url))
                // Abort if no response after 20 seconds
                let item = DispatchWorkItem { [weak self] in self?.finish(nil) }
                self.timeoutItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: item)
            }
            if cookies.isEmpty { proceed() }
            for cookie in cookies {
                store.setCookie(cookie) { proceed() }
            }
        }
    }

    // Allow WebKit to display JSON responses (don't trigger download)
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navCount += 1
        webView.evaluateJavaScript("document.body.innerText") { [weak self] result, _ in
            guard let self, let text = result as? String,
                  text.hasPrefix("{") || text.hasPrefix("["),
                  let data = text.data(using: .utf8) else { return }
            self.finish(ClaudeAuth.parseUsageResponse(data))
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(nil) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(nil) }

    private func finish(_ result: UsageData?) {
        timeoutItem?.cancel()
        timeoutItem = nil
        cont?.resume(returning: result)
        cont = nil
    }
}
