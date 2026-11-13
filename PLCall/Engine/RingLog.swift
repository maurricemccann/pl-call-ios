import Foundation
import UIKit

/// The last 40 things that happened around rings, with the time and whether the phone was locked.
/// Shown in Settings > Ring log, so a ring that never came can be traced on the phone itself.
@MainActor enum RingLog {
    private static let key = "plcall.ringLog"

    static var lines: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }

    static func note(_ what: String) {
        let time = Date().formatted(date: .omitted, time: .standard)
        let where_ = UIApplication.shared.applicationState == .active ? "open" : (UIApplication.shared.isProtectedDataAvailable ? "background" : "locked")
        var all = lines
        all.insert("\(time) [\(where_)] \(what)", at: 0)
        UserDefaults.standard.set(Array(all.prefix(40)), forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
