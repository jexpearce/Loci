import CryptoKit
import Foundation

/// 1) Create a random code verifier (43–128 characters)
func generateCodeVerifier() -> String {
    let length = 64
    let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
    return String((0..<length).map { _ in chars.randomElement()! })
}

/// 2) SHA256-hash & Base64-URL-encode to make the code challenge
func generateCodeChallenge(from verifier: String) -> String {
    let data = Data(verifier.utf8)
    let hash = SHA256.hash(data: data)
    let base64 = Data(hash).base64EncodedString()
    // Convert to “Base64-URL” by replacing characters and removing padding
    return base64
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .trimmingCharacters(in: CharacterSet(charactersIn: "="))
}
