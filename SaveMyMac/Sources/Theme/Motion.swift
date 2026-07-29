import SwiftUI

/// SwiftUI equivalents of the design's eight named animations.
enum Motion {

    /// `smRise` — screen entrance: rises 10px and fades in.
    static let rise = Animation.easeOut(duration: 0.4)

    /// `smPop` — appearance with a slight overshoot (celebration overlay).
    static let pop = Animation.spring(response: 0.45, dampingFraction: 0.62)

    /// `smBar` — bar growing from the left.
    static let bar = Animation.easeOut(duration: 1.0)

    /// `smDash` — ring filling up.
    static let ring = Animation.timingCurve(0.2, 0.9, 0.2, 1, duration: 1.2)

    // CAREFUL with the two below. `repeatForever` forces SwiftUI to redraw at
    // 60 fps for as long as the view exists — that isn't a "light animation", it
    // is a permanent cost. They only make sense when the view is temporary.
    //
    // The `pulse` on the "live" dot and the `float` on the health ring were
    // removed for exactly that reason: they lived on the Dashboard, which is the
    // default screen, and kept the main thread busy the whole time the app was
    // open.

    /// `smScan` — band sweeping across the bar. Exists only DURING a scan.
    static let scan = Animation.linear(duration: 1.1).repeatForever(autoreverses: false)

    /// `smRing` — celebration ripples. Exists only while the overlay is on screen.
    static let expandingRing = Animation.easeOut(duration: 1.6).repeatForever(autoreverses: false)

    /// Default transition between screens.
    static let screen = AnyTransition.opacity.combined(with: .offset(y: 10))
}

/// A screen's `smRise` entrance.
///
/// The first version started at `opacity(0)` and only became visible in
/// `onAppear`. That turned a decoration into total failure: the app only had to
/// stall before `onAppear` for the entire screen to go blank, with no clue why.
///
/// Now the content is **visible by default** and the animation is additive: it
/// uses `transition`, which SwiftUI applies on insertion and ignores when it
/// can't. A decorative effect must never be able to hide the interface.
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
