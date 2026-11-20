import FanKit
import Foundation
import Security

/// The code-signing requirement a client must meet to talk to the helper.
///
/// When the helper is signed with a Developer ID, clients must be signed by Apple-issued
/// certificates from the same team, so no other app can drive the fans. A helper built
/// from source with an ad-hoc signature has no team to compare against, so it falls back
/// to checking the client's signing identifier.
enum ClientRequirement {
    static var current: String {
        let identifier = "identifier \"\(HelperConstants.appIdentifier)\""
        guard let team = ownTeamIdentifier() else { return identifier }
        return "anchor apple generic and \(identifier) and certificate leaf[subject.OU] = \"\(team)\""
    }

    /// Team ID from this process's own signature, or nil if it is ad-hoc signed.
    static func ownTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info = info as? [String: Any] else { return nil }
        return info[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
