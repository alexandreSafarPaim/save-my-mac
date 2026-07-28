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

/// A cena da barra de menus — **ligada por padrão**.
///
/// Ela ficou desativada por um tempo, e vale registrar por quê, porque a
/// conclusão foi errada: quando este recurso entrou, o app passou a travar na
/// abertura e o item nunca apareceu ao lado do relógio. Parecia culpa dele.
///
/// Não era. A causa estava no `Preferences`, que usava `@Published`. O
/// `MenuBarExtra(isInserted:)` escreve no binding a cada passagem de
/// atualização, e `@Published` publica em toda atribuição — inclusive quando o
/// valor não muda. Isso fechava um ciclo que consumia 100 % de um núcleo e
/// impedia o grafo de convergir. **O item nunca apareceu porque o app nunca
/// terminava a primeira atualização.** O recurso era vítima, não culpado.
///
/// Corrigido o setter, ele funciona. A chave continua existindo como interruptor
/// de emergência — é barato manter e evita ter que recompilar para isolar algo:
///
///     defaults write br.com.pentagrama.savemymac enableMenuBar -bool false
///
/// A decisão é lida **uma vez, no lançamento**: alternar em tempo real
/// reconstruiria a árvore de cenas, que é justamente o que não se quer testar
/// enquanto se investiga instabilidade.
enum MenuBarFeature {

    static let isEnabled: Bool = {
        guard !SafeMode.isOn else { return false }
        let defaults = UserDefaults.standard
        // Registrado aqui e não no `Preferences`: isto é lido no lançamento,
        // possivelmente antes de `Preferences.init` existir.
        defaults.register(defaults: ["enableMenuBar": true])
        let on = defaults.bool(forKey: "enableMenuBar")
        NSLog("[SaveMyMac] Barra de menus: \(on ? "ligada" : "desligada")")
        return on
    }()
}
