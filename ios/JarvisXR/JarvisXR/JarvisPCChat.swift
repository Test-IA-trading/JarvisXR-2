import UIKit

struct JarvisPCChatAddress {
    let url: URL

    init?(_ input: String) {
        var host = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host.hasPrefix("http://") { host.removeFirst("http://".count) }
        if host.hasSuffix("/") { host.removeLast() }
        if host.hasSuffix(":8765") { host.removeLast(":8765".count) }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let bytes = parts.compactMap { UInt8($0) }
        guard bytes.count == 4, bytes.map({ String($0) }).joined(separator: ".") == host else { return nil }
        let isPrivate = bytes[0] == 10 || (bytes[0] == 172 && (16...31).contains(bytes[1]))
            || (bytes[0] == 192 && bytes[1] == 168)
        guard isPrivate, let url = URL(string: "http://\(host):8765/") else { return nil }
        self.url = url
    }
}

extension JarvisRootViewController {
    func presentPCChat() {
        let savedAddress = "jarvis.pcChat.address"
        let alert = UIAlertController(title: "Chat avec mon PC",
            message: "Entre l’adresse affichée par Jarvis sur ton PC. Pour parler en français, saisis aussi le code du PC. Utilise ton Wi-Fi privé : le texte y circule en clair.",
            preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Adresse du PC"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.text = UserDefaults.standard.string(forKey: savedAddress)
        }
        alert.addTextField { field in
            field.placeholder = "Code du PC"
            field.isSecureTextEntry = true
            field.autocorrectionType = .no
        }
        guard let field = alert.textFields?.first else { return }
        let open = UIAlertAction(title: "Chat écrit dans Safari", style: .default) { [weak self, weak field] _ in
            guard let address = JarvisPCChatAddress(field?.text ?? "") else { return }
            UserDefaults.standard.set(address.url.host, forKey: savedAddress)
            UIApplication.shared.open(address.url, options: [:]) { opened in
                guard !opened else { return }
                DispatchQueue.main.async {
                    let notice = UIAlertController(title: "Navigateur indisponible",
                        message: "Ouvre l’adresse affichée sur le PC dans Safari.", preferredStyle: .alert)
                    notice.addAction(UIAlertAction(title: "Fermer", style: .default))
                    self?.present(notice, animated: true)
                }
            }
        }
        open.isEnabled = JarvisPCChatAddress(field.text ?? "") != nil
        field.addAction(UIAction { [weak field, weak open] _ in
            open?.isEnabled = JarvisPCChatAddress(field?.text ?? "") != nil
        }, for: .editingChanged)
        alert.addAction(UIAlertAction(title: "Annuler", style: .cancel))
        let voice = UIAlertAction(title: "Conversation vocale", style: .default) { [weak self, weak field, weak alert] _ in
            guard let address = JarvisPCChatAddress(field?.text ?? ""),
                  let code = alert?.textFields?.last?.text else { return }
            let key = code.uppercased().filter { !$0.isWhitespace && $0 != "-" }
            UserDefaults.standard.set(address.url.host, forKey: savedAddress)
            let vc = JarvisFrenchConversation(address: address, code: key)
            self?.present(UINavigationController(rootViewController: vc), animated: true)
        }
        let codeField = alert.textFields?.last
        let validateVoice = { [weak field, weak codeField, weak voice] in
            let key = (codeField?.text ?? "").uppercased().filter { !$0.isWhitespace && $0 != "-" }
            voice?.isEnabled = JarvisPCChatAddress(field?.text ?? "") != nil
                && key.range(of: "^[0-9A-F]{16}$", options: .regularExpression) != nil
        }
        validateVoice()
        field.addAction(UIAction { _ in validateVoice() }, for: .editingChanged)
        codeField?.addAction(UIAction { _ in validateVoice() }, for: .editingChanged)
        alert.addAction(voice)
        alert.addAction(open)
        present(alert, animated: true)
    }
}
