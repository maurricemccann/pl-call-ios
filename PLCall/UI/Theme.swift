import CoreText
import SwiftUI
import UIKit

/// Tokens. Apple's system colours, sizes and motion come first; the house layer is the orange tint,
/// the hand-drawn title, the pattern backdrop, Claude's coral and the house orange of his own messages.
enum T {
    // House layer
    static let orange = Color(red: 0.910, green: 0.392, blue: 0.118)
    static let coral = Color(red: 0.851, green: 0.467, blue: 0.341)
    // his messages in house orange (his ruling 11-12, S348: "make my bubbles orange not blue"); the bottom is deepened so
    // white text stays readable (3.7:1 at the top, 4.7:1 at the bottom)
    static let sentTop = Color(red: 0.860, green: 0.370, blue: 0.100)
    static let sentBottom = Color(red: 0.780, green: 0.300, blue: 0.070)
    static let sentContrast = Color(red: 0.690, green: 0.255, blue: 0.040)   // Increase Contrast: white text needs a darker orange

    // Apple system colours: they carry their own Increase Contrast variants
    static let call = Color(uiColor: .systemGreen)
    static let end = Color(uiColor: .systemRed)
    static let received = Color(uiColor: .systemGray5)
    static let plate = Color(uiColor: .systemFill)
    static let well = Color(uiColor: .tertiarySystemFill)

    // Metrics, in points
    static let touch: CGFloat = 44
    static let margin: CGFloat = 16
    static let gap: CGFloat = 8
    static let bubbleRadius: CGFloat = 20
    static let bubbleTail: CGFloat = 6
    static let bubblePadH: CGFloat = 14
    static let bubblePadV: CGFloat = 10
    static let cardRadius: CGFloat = 28
    static let wellRadius: CGFloat = 12

    static let handFont = "PL-Hand-V2-Regular"

    /// ENGINE sets this key when a config loads: "system" as the font family means Apple's system font, no Jost.
    static var usesSystemFont: Bool { UserDefaults.standard.bool(forKey: "plcall.usesSystemFont") }
}

/// Apple's text styles, each mapped to a Jost size and weight; every one scales with Dynamic Type through AX5.
enum PLText {
    case largeTitle, title, title2, title3, headline, body, callout, subhead, footnote, caption, caption2

    private var size: CGFloat {
        switch self {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline: return 18
        case .body: return 18
        case .callout: return 17
        case .subhead: return 16
        case .footnote: return 14
        case .caption: return 13
        case .caption2: return 12
        }
    }

    private var style: Font.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .body: return .body
        case .callout: return .callout
        case .subhead: return .subheadline
        case .footnote: return .footnote
        case .caption: return .caption
        case .caption2: return .caption2
        }
    }

    private var weight: Int {
        switch self {
        case .largeTitle, .title, .title2, .title3: return 500
        case .headline: return 600
        default: return 400
        }
    }

    /// Emphasis adds 200 to the weight, the Bold Text setting adds 100; the heaviest file bundled is 700.
    func font(bold: Bool, emphasized: Bool) -> Font {
        let w = min(700, weight + (emphasized ? 200 : 0) + (bold ? 100 : 0))
        if T.usesSystemFont {
            let systemWeight: Font.Weight = w >= 700 ? .bold : w >= 600 ? .semibold : w >= 500 ? .medium : .regular
            return .system(style, weight: systemWeight)
        }
        let name = w >= 700 ? "Jost-Bold" : w >= 600 ? "Jost-Semi" : w >= 500 ? "Jost-Medium" : "Jost-Book"
        return .custom(name, size: size, relativeTo: style)
    }
}

private struct PLFontModifier: ViewModifier {
    let text: PLText
    let emphasized: Bool
    @Environment(\.legibilityWeight) private var legibilityWeight

    init(text: PLText, emphasized: Bool) {
        self.text = text
        self.emphasized = emphasized
    }

    func body(content: Content) -> some View {
        content.font(text.font(bold: legibilityWeight == .bold, emphasized: emphasized))
    }
}

extension View {
    /// The text face for a text style: Jost, or the system font when the config asks for it.
    func plFont(_ text: PLText, emphasized: Bool = false) -> some View {
        modifier(PLFontModifier(text: text, emphasized: emphasized))
    }

    /// His hand font, for titles only.
    func plHand(_ size: CGFloat, relativeTo style: Font.TextStyle) -> some View {
        font(.custom(T.handFont, size: size, relativeTo: style))
    }

    /// Liquid Glass for a custom control: controls only, never the transcript. One tinted control per bar.
    func glassControl(tint: Color? = nil, in shape: some Shape = Capsule()) -> some View {
        buttonStyle(.plain).glassEffect(.regular.tint(tint).interactive(), in: shape)
    }
}

/// Registers the bundled font files at launch, so the text face does not depend on the Info.plist list.
enum PLFonts {
    static func register() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)   // false only means it was already registered
        }
    }
}

/// The haptics map. Each pattern keeps Apple's documented meaning.
@MainActor
enum PLHaptic {
    static let approve = SensoryFeedback.success
    static let deny = SensoryFeedback.warning
    static let connect = SensoryFeedback.impact(weight: .medium)
    static let end = SensoryFeedback.impact(weight: .heavy)
    static let error = SensoryFeedback.error
    static let select = SensoryFeedback.selection
}

/// Motion: SwiftUI's own spring presets, or a short fade when Reduce Motion is on.
enum PLMotion {
    static func standard(reduce: Bool) -> Animation { reduce ? .easeInOut(duration: 0.2) : .smooth }
}

extension CallState {
    /// The words beside the state dot, so the state never rests on colour alone.
    var plLabel: String {
        switch self {
        case .idle: return "Ready"
        case .connecting: return "Connecting"
        case .listening: return "Listening"
        case .hearing: return "Hearing you"
        case .working: return "Working"
        case .speaking: return "Speaking"
        case .waitingApproval: return "Needs you"
        case .lost: return "Line lost"
        }
    }

    var plDotColor: Color {
        switch self {
        case .idle, .connecting: return Color(uiColor: .systemGray)
        case .listening, .hearing: return Color(uiColor: .systemBlue)
        case .working: return Color(uiColor: .systemOrange)
        case .speaking: return Color(uiColor: .systemGreen)
        case .waitingApproval: return Color(uiColor: .systemYellow)
        case .lost: return Color(uiColor: .systemRed)
        }
    }
}
