import UIKit
import Security

enum CloudVoiceKeys {
    static var asrHost: String { CloudASRHostSettings.current() }
    static var asrService: String { CloudASRHostSettings.service(for: asrHost) }
    static let llmService = "RayNeo.CloudLLM.https.api.deepseek.com.chat.completions"
    static let enabledKey = "cloudVoiceConsent.v1"
    static func get(_ service: String) -> String? {
        var item: CFTypeRef?
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,
            kSecAttrService as String:service, kSecAttrAccount as String:"user-api-key",
            kSecReturnData as String:true, kSecMatchLimit as String:kSecMatchLimitOne]
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data:data,encoding:.utf8)
    }
    static var ready: Bool { CloudASRHostSettings.normalize(asrHost) != nil && Self.get(asrService) != nil && Self.get(llmService) != nil }
    static func save(_ value: String, service: String) -> Bool {
        let key = value.trimmingCharacters(in:.whitespacesAndNewlines)
        guard key.hasPrefix("sk-"), key.utf8.count <= 512,
              !key.contains(where: { $0.isWhitespace }) else { return false }
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,
            kSecAttrService as String:service, kSecAttrAccount as String:"user-api-key"]
        let attributes: [String:Any] = [kSecValueData as String:Data(key.utf8),
            kSecAttrAccessible as String:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound {
            return SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary,nil) == errSecSuccess
        }
        return result == errSecSuccess
    }
}

final class CloudVoiceSettingsController: UIViewController {
    var changed: ((Bool) -> Void)?
    private let asr = UITextField(), llm = UITextField(), host = UITextField(), note = UILabel()
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        let title = UILabel(); title.text = "클라우드 음성 연결 진단"; title.font = .preferredFont(forTextStyle:.title1)
        stack.addArrangedSubview(title)
        note.numberOfLines = 0
        note.text = "Alibaba Cloud ASR → DeepSeek V4 Flash\n음성 호출 후 오디오는 ASR로, 인식 텍스트는 DeepSeek로 전송됩니다. 각 서비스 요금이 발생할 수 있습니다. TTS는 없으며 키는 이 기기의 키체인에 저장합니다. Codex 음성 도구는 별도 허용 시에만 사용합니다."
        stack.addArrangedSubview(note)
        host.placeholder = "Alibaba Cloud ASR 호스트 (프로토콜/경로 제외)"
        host.text = CloudASRHostSettings.current(); host.borderStyle = .roundedRect
        host.autocapitalizationType = .none; host.autocorrectionType = .no
        stack.addArrangedSubview(host)
        for (field, identifier, placeholder) in [(asr,"cloud-asr-key","Alibaba Cloud ASR API 키"),(llm,"cloud-llm-key","DeepSeek API Key")] {
            field.isSecureTextEntry = true; field.accessibilityIdentifier = identifier
            field.placeholder = placeholder; field.borderStyle = .roundedRect
            field.autocapitalizationType = .none; field.autocorrectionType = .no
            field.textContentType = .password
            stack.addArrangedSubview(field)
        }
        for (title, action) in [("저장 및 클라우드 대화 켜기",#selector(save)),("클라우드 끄기 · 로컬 무작위 응답 테스트",#selector(disable)),("뒤로",#selector(back))] {
            let button = UIButton(type:.system); button.setTitle(title,for:.normal)
            button.heightAnchor.constraint(equalToConstant:44).isActive = true
            button.addTarget(self,action:action,for:.touchUpInside); stack.addArrangedSubview(button)
        }
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor,constant:24),
            stack.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:20),stack.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-20)])
    }
    @objc private func save() {
        let a = asr.text ?? "", b = llm.text ?? ""
        guard let target = CloudASRHostSettings.normalize(host.text ?? "") else { note.text = "유효한 Alibaba Cloud ASR 호스트명을 입력하세요. 클라우드 전송은 켜지지 않았습니다."; return }
        let service = CloudASRHostSettings.service(for: target)
        let okA = a.isEmpty ? CloudVoiceKeys.get(service) != nil : CloudVoiceKeys.save(a,service:service)
        let okB = b.isEmpty ? CloudVoiceKeys.get(CloudVoiceKeys.llmService) != nil : CloudVoiceKeys.save(b,service:CloudVoiceKeys.llmService)
        asr.text = ""; llm.text = ""
        guard okA && okB else { note.text = "API 키를 모두 저장하지 못했습니다. 입력을 확인하세요. 클라우드 전송은 켜지지 않았습니다."; return }
        CloudASRHostSettings.save(target)
        UserDefaults.standard.set(true,forKey:CloudVoiceKeys.enabledKey)
        changed?(true); dismiss(animated:true)
    }
    @objc private func disable() {
        UserDefaults.standard.set(false,forKey:CloudVoiceKeys.enabledKey)
        changed?(false); dismiss(animated:true)
    }
    @objc private func back() { dismiss(animated:true) }
}
