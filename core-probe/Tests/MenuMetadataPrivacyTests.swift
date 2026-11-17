import Foundation

@main struct MenuMetadataPrivacyTests {
    static func main() throws {
        let packet: [String: Any] = [
            "sid": "PRIVATE_SESSION_VALUE", "code": 1,
            "text": "PRIVATE_TRANSCRIPT_VALUE", "token": "PRIVATE_TOKEN_VALUE",
            "settings": ["mode": 3, "source_language": "ko", "target_language": "en",
                         "user_note": "PRIVATE_NOTE_VALUE"]
        ]
        let data = try JSONSerialization.data(withJSONObject: packet)
        let summary = LauncherStructure.inspect(data)
        precondition(!summary.contains("PRIVATE_"))
        precondition(summary.contains("settings.mode=3"))
        precondition(summary.contains("settings.source_language=ko"))
        precondition(summary.contains("settings.target_language=en"))
        precondition(summary.contains("code=1"))
        let classic = try JSONSerialization.data(withJSONObject: ["settings": ["mode": "classic"]])
        precondition(LauncherStructure.inspect(classic).contains("settings.mode=classic"))
        print("Menu metadata check passed: control values retained; session, transcript, token and note values excluded.")
    }
}
