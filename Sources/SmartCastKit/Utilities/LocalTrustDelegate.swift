import Foundation
import Security
import CryptoKit

/// URLSessionDelegate that allows local LAN connections to self-signed TLS endpoints
/// with optional SHA-256 certificate pinning for explicit device trust.
public final class LocalTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    public static let shared = LocalTrustDelegate()

    public let pinnedFingerprints: Set<String>
    public let allowUnpinnedOnLocalNetwork: Bool

    public init(pinnedFingerprints: Set<String> = [], allowUnpinnedOnLocalNetwork: Bool = true) {
        self.pinnedFingerprints = Set(pinnedFingerprints.map { Self.normalizeFingerprint($0) })
        self.allowUnpinnedOnLocalNetwork = allowUnpinnedOnLocalNetwork
        super.init()
    }

    public static func normalizeFingerprint(_ fp: String) -> String {
        fp.replacingOccurrences(of: ":", with: "")
          .replacingOccurrences(of: " ", with: "")
          .lowercased()
    }

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

    public static func sha256Fingerprint(for certificate: SecCertificate) -> String {
        let certData = SecCertificateCopyData(certificate) as Data
        let digest = SHA256.hash(data: certData)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func leafCertificateFingerprint(from trust: SecTrust) -> String? {
        if let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first {
            return sha256Fingerprint(for: leaf)
        }
        return nil
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

        if !pinnedFingerprints.isEmpty {
            guard let fingerprint = Self.leafCertificateFingerprint(from: trust),
                  pinnedFingerprints.contains(fingerprint) else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        if allowUnpinnedOnLocalNetwork {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
