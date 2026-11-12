import CoreText
import SwiftUI

/// Colours, words, symbols and type for everything the extension draws. One place, so the surfaces agree.
enum WidgetStyle {
    static let accent = Color(red: 0.910, green: 0.392, blue: 0.118)   // house orange #E8641E

    static func state(_ raw: String) -> CallState {
        CallState(rawValue: raw) ?? .idle
    }

    /// Apple system colours, so Increase Contrast and the Lock Screen's tinted modes still work.
    static func color(_ state: CallState) -> Color {
        switch state {
        case .idle, .connecting: return .gray
        case .listening, .hearing: return .blue
        case .working: return .orange
        case .speaking: return .green
        case .waitingApproval: return .yellow
        case .lost: return .red
        }
    }

    static func label(_ state: CallState) -> String {
        switch state {
        case .idle: return "Ready"
        case .connecting: return "Connecting"
        case .listening: return "Listening"
        case .hearing: return "Hearing you"
        case .working: return "Working"
        case .speaking: return "Speaking"
        case .waitingApproval: return "Needs your answer"
        case .lost: return "Line lost"
        }
    }

    static func symbol(_ state: CallState) -> String {
        switch state {
        case .idle, .connecting: return "phone.fill"
        case .listening: return "mic.fill"
        case .hearing: return "waveform"
        case .working: return "bolt.fill"
        case .speaking: return "speaker.wave.2.fill"
        case .waitingApproval: return "questionmark.circle"
        case .lost: return "xmark.circle.fill"
        }
    }

    /// The build copies the app's text fonts into this extension; register them once for this process.
    private static let hasTextFont: Bool = {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return !urls.isEmpty
    }()

    /// The house text face at an Apple text style's size, or the system font when the files are missing.
    static func text(_ size: CGFloat, _ style: Font.TextStyle, strong: Bool = false) -> Font {
        if hasTextFont {
            return .custom(strong ? "Jost-Semi" : "Jost-Book", size: size, relativeTo: style)
        }
        return .system(style, weight: strong ? Font.Weight.semibold : Font.Weight.regular)
    }
}

/// The state dot used on every surface.
struct StateDot: View {
    let state: CallState
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(WidgetStyle.color(state))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
