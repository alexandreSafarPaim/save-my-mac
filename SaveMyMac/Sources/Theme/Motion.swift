import SwiftUI

/// Equivalentes SwiftUI das oito animações nomeadas do design.
enum Motion {

    /// `smRise` — entrada de tela: sobe 10px e aparece.
    static let rise = Animation.easeOut(duration: 0.4)

    /// `smPop` — surgimento com leve overshoot (overlay de comemoração).
    static let pop = Animation.spring(response: 0.45, dampingFraction: 0.62)

    /// `smBar` — barra crescendo da esquerda.
    static let bar = Animation.easeOut(duration: 1.0)

    /// `smDash` — anel se preenchendo.
    static let ring = Animation.timingCurve(0.2, 0.9, 0.2, 1, duration: 1.2)

    // ATENÇÃO às duas abaixo. `repeatForever` obriga o SwiftUI a redesenhar a
    // 60 fps enquanto a view existir — não é "animação leve", é custo
    // permanente. Só valem quando a view é temporária.
    //
    // O `pulse` do ponto "ao vivo" e o `float` do anel de saúde foram removidos
    // justamente por isso: viviam no Painel, que é a tela padrão, e mantinham a
    // main thread ocupada o app inteiro aberto.

    /// `smScan` — faixa varrendo a barra. Só existe DURANTE a varredura.
    static let scan = Animation.linear(duration: 1.1).repeatForever(autoreverses: false)

    /// `smRing` — ondas da comemoração. Só existe enquanto o overlay está na tela.
    static let expandingRing = Animation.easeOut(duration: 1.6).repeatForever(autoreverses: false)

    /// Transição padrão entre telas.
    static let screen = AnyTransition.opacity.combined(with: .offset(y: 10))
}

/// Entrada `smRise` de uma tela.
///
/// A primeira versão começava em `opacity(0)` e só ficava visível no
/// `onAppear`. Isso transformou um enfeite em falha total: bastou o app
/// engasgar antes do `onAppear` para a tela inteira ficar em branco, sem
/// nenhuma pista do motivo.
///
/// Agora o conteúdo é **visível por padrão** e a animação é aditiva: usa
/// `transition`, que o SwiftUI aplica na inserção e ignora se não puder. Um
/// efeito decorativo nunca deve poder esconder a interface.
extension View {
    @ViewBuilder
    func riseIn() -> some View {
        if SafeMode.isOn {
            self
        } else {
            transition(.opacity.combined(with: .offset(y: 10)))
                .animation(Motion.rise, value: true)
        }
    }
}
