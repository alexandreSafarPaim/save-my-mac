import Foundation

/// Modo de bisecção para isolar travamento de interface.
///
/// Ligar com:
///     defaults write br.com.pentagrama.savemymac safeMode -bool true
/// Desligar com:
///     defaults write br.com.pentagrama.savemymac safeMode -bool false
///
/// Com ele ligado o app desativa, de uma vez, tudo que é enfeite ou
/// infraestrutura recente:
///
///   - o fundo atmosférico (grade + gradientes radiais)
///   - o item na barra de menus
///   - o `FlowLayout`, que é um `Layout` customizado escrito à mão — a peça com
///     maior chance de entrar em negociação infinita de layout
///   - as animações de entrada
///
/// Se o app funcionar em modo seguro, o problema está numa dessas quatro. Se
/// travar mesmo assim, está no núcleo e o enfeite é inocente. Isso vale mais do
/// que qualquer palpite meu.
enum SafeMode {

    /// Lido uma vez. Trocar exige reabrir o app, o que é proposital: alternar em
    /// tempo real reconstruiria a árvore de views e confundiria o diagnóstico.
    static let isOn: Bool = {
        let on = UserDefaults.standard.bool(forKey: "safeMode")
        if on {
            NSLog("[SaveMyMac] MODO SEGURO ativo: fundo, barra de menus, FlowLayout e animações desligados.")
        }
        return on
    }()
}

/// A cena da barra de menus.
///
/// **Desativada por padrão.** Ela foi adicionada, o app passou a travar na
/// abertura e o item nunca apareceu ao lado do relógio — ou seja, o recurso não
/// funcionava E quebrava o resto. Enquanto a causa não estiver identificada, o
/// certo é o app abrir sem ela.
///
/// A decisão é lida **uma vez, no lançamento**, e a cena só é construída se
/// estiver ligada. Um `isInserted: false` não bastaria: a cena continuaria
/// existindo, o rótulo continuaria sendo avaliado a cada atualização de estado,
/// e o suspeito seguiria no processo.
///
/// Para testar:
///     defaults write br.com.pentagrama.savemymac enableMenuBar -bool true
/// Para voltar:
///     defaults write br.com.pentagrama.savemymac enableMenuBar -bool false
enum MenuBarFeature {

    static let isEnabled: Bool = {
        guard !SafeMode.isOn else { return false }
        // Padrão FALSE de propósito — ver acima.
        let on = UserDefaults.standard.bool(forKey: "enableMenuBar")
        NSLog("[SaveMyMac] Barra de menus: \(on ? "ligada" : "desligada")")
        return on
    }()
}
