import Foundation
import MyTermCore
import Security

struct ApplicationIdentity {
    let fingerprint: String
    let detail: String
    let isStableForPrivacyGrants: Bool

    static func current() -> ApplicationIdentity {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return fallback
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return fallback
        }
        var rawInformation: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &rawInformation) == errSecSuccess,
            let information = rawInformation as? [String: Any]
        else {
            return fallback
        }

        let identifier =
            information[kSecCodeInfoIdentifier as String] as? String
            ?? MyTermIdentity.bundleIdentifier
        if let team = information[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty {
            return ApplicationIdentity(
                fingerprint: "team:\(team):\(identifier)",
                detail: "Developer ID team \(team)",
                isStableForPrivacyGrants: true
            )
        }

        if let unique = information[kSecCodeInfoUnique as String] as? Data {
            let hash = unique.map { String(format: "%02x", $0) }.joined()
            return ApplicationIdentity(
                fingerprint: "adhoc:\(hash)",
                detail: "Ad-hoc/local signature — privacy approval can reset after rebuilding",
                isStableForPrivacyGrants: false
            )
        }
        return fallback
    }

    private static var fallback: ApplicationIdentity {
        ApplicationIdentity(
            fingerprint: "unsigned:\(MyTermIdentity.bundleIdentifier)",
            detail: "Unsigned development build — not suitable for distribution",
            isStableForPrivacyGrants: false
        )
    }
}
