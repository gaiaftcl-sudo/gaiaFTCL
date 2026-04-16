// WalletTests.swift — SwiftTestRobit
//
// Zero-PII wallet assertion tests.
//
// These tests verify the HARD requirement: the GaiaHealth wallet file
// contains ZERO personally identifiable information. If any of these
// tests fail, the OQ is blocked until resolved.
//
// The wallet file lives at ~/.gaiahealth/wallet.key and is generated
// by scripts/iq_install.sh. This suite reads it and asserts its structure.

import Foundation

enum WalletTests {
    /// Known-PHI patterns that must NEVER appear in the wallet file.
    static let phiPatterns: [String] = [
        // No names, emails, phone numbers, addresses, medical IDs
        "@",          // email address indicator
        "DOB",        // date of birth label
        "SSN",        // social security number label
        "MRN",        // medical record number label
        "patient",    // patient reference
        "name:",      // name field
        "address:",   // address field
        "phone",      // phone number
        "email",      // email field
    ]

    /// Required cryptographic fields in the wallet JSON.
    static let requiredCryptoFields: [String] = [
        "cell_id",
        "wallet_address",
        "generated_at",
        "curve",
        "derivation",
        "warning",
    ]

    /// Fields that are explicitly PROHIBITED from appearing in the wallet.
    static let prohibitedPersonalFields: [String] = [
        "name",
        "email",
        "dob",
        "ssn",
        "mrn",
        "patient_id",
        "first_name",
        "last_name",
        "phone",
        "address",
        "zip",
        "insurance",
    ]

    static func runAll() {
        // Locate wallet file
        let walletPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gaiahealth/wallet.key")

        run("TR-S3-001", "Wallet file exists at ~/.gaiahealth/wallet.key") {
            FileManager.default.fileExists(atPath: walletPath.path)
        }

        // Load wallet content for subsequent tests
        guard let walletData = try? Data(contentsOf: walletPath),
              let walletText = String(data: walletData, encoding: .utf8) else {
            // Wallet not yet generated — run structural tests against synthetic sample
            runStructuralTests(against: syntheticWalletJSON())
            return
        }

        runStructuralTests(against: walletText)

        run("TR-S3-010", "Wallet file permissions are 600 (owner-read only)") {
            let attrs = try FileManager.default.attributesOfItem(atPath: walletPath.path)
            let perms = attrs[.posixPermissions] as? Int ?? 0
            return perms == 0o600
        }
    }

    static func runStructuralTests(against walletText: String) {
        // PHI pattern scan
        for pattern in phiPatterns {
            let patternCopy = pattern
            run("TR-S3-002", "ZERO-PII: wallet does not contain '\(pattern)'") {
                !walletText.lowercased().contains(patternCopy.lowercased())
            }
        }

        // Required cryptographic fields present
        for field in requiredCryptoFields {
            let fieldCopy = field
            run("TR-S3-003", "Wallet contains required crypto field '\(field)'") {
                walletText.contains(fieldCopy)
            }
        }

        // Prohibited personal fields absent
        for field in prohibitedPersonalFields {
            let fieldCopy = field
            run("TR-S3-004", "ZERO-PII: wallet does NOT contain personal field '\(field)'") {
                !walletText.lowercased().contains("\"\(fieldCopy)\"")
            }
        }

        // wallet_address starts with gaiahealth1 prefix
        run("TR-S3-005", "wallet_address has gaiahealth1 prefix") {
            walletText.contains("\"gaiahealth1")
        }

        // curve must be secp256k1 (no personal info in curve name)
        run("TR-S3-006", "Wallet curve is secp256k1") {
            walletText.contains("secp256k1")
        }

        // warning field must be present (security advisory)
        run("TR-S3-007", "Wallet warning field present (KEEP SECRET advisory)") {
            walletText.contains("KEEP SECRET")
        }

        // Wallet JSON is valid
        run("TR-S3-008", "Wallet file is valid JSON") {
            guard let data = walletText.data(using: .utf8) else { return false }
            return (try? JSONSerialization.jsonObject(with: data)) != nil
        }

        // cell_id is a 64-char SHA-256 hex string (not a person's name)
        run("TR-S3-009", "ZERO-PII: cell_id is a 64-char hex SHA-256 (not a name)") {
            guard let range = walletText.range(of: "\"cell_id\":"),
                  let start = walletText[range.upperBound...].firstIndex(of: "\"") else {
                return false
            }
            let afterQuote = walletText.index(after: start)
            guard let end = walletText[afterQuote...].firstIndex(of: "\"") else { return false }
            let cellId = String(walletText[afterQuote..<end])
            return cellId.count == 64 && cellId.allSatisfy(\.isHexDigit)
        }
    }

    /// Synthetic wallet JSON for structural testing when wallet not yet generated.
    static func syntheticWalletJSON() -> String {
        """
        {
          "cell_id": "\(String(repeating: "a", count: 64))",
          "wallet_address": "gaiahealth1\(String(repeating: "b", count: 38))",
          "private_entropy": "\(String(repeating: "c", count: 64))",
          "generated_at": "20260416T120000Z",
          "curve": "secp256k1",
          "derivation": "SHA256(hw_uuid|entropy|timestamp)",
          "warning": "KEEP SECRET — never commit, never share."
        }
        """
    }
}
