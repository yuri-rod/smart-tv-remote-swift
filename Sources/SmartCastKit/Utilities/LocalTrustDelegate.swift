import Foundation
import Security

/// URLSessionDelegate that allows local LAN connections to self-signed TLS endpoints (such as Samsung port 8002).
public final class LocalTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    public static let shared = LocalTrustDelegate()

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
