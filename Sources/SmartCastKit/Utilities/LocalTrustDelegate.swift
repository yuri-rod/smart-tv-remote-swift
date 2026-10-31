import Foundation
import Security

/// URLSessionDelegate that allows local LAN connections to self-signed TLS endpoints (such as Samsung port 8002).
public final class LocalTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    public static let shared = LocalTrustDelegate()

    public static func isPrivateOrLocalHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".local") {
            return true
        }
        let parts = host.split(separator: ".")
        if parts.count == 4, let first = Int(parts[0]), let second = Int(parts[1]) {
            if first == 10 || first == 127 { return true }
            if first == 192 && second == 168 { return true }
            if first == 172 && (16...31).contains(second) { return true }
            if first == 169 && second == 254 { return true }
        }
        let lower = host.lowercased()
        if lower == "::1" || lower.hasPrefix("fe80:") || lower.hasPrefix("fc") || lower.hasPrefix("fd") {
            return true
        }
        return false
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              Self.isPrivateOrLocalHost(challenge.protectionSpace.host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
