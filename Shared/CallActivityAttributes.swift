import ActivityKit
import Foundation

/// What the Live Activity shows. Kept small: the system allows about 4 KB for all of it.
struct CallActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var state: String      // CallState.rawValue
        var line: String       // the last line said
        var askID: String?     // set while a permission or a question waits
        var askText: String?   // what is being asked, one or two lines
        var push: Bool?        // PUSH mode: the Lock Screen shows a Talk button
        var heard: String?     // set while "I heard: ..., right?" waits: the Lock Screen and Island show Yes / Again
    }

    var title: String
}

/// The kind strings the app needs when it asks the system to redraw a widget or a control.
enum PLCallKinds {
    static let stateWidget = "com.psychedluxuries.call.state"
    static let callControl = "com.psychedluxuries.call.control.call"
    static let endControl = "com.psychedluxuries.call.control.end"
    static let approveControl = "com.psychedluxuries.call.control.approve"
}
