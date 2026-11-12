import AppIntents
import SwiftUI
import WidgetKit

// Control Center, Lock Screen and Action button controls. The Lock Screen shows only the symbol,
// so each symbol must say what the button does on its own.

struct CallControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: PLCallKinds.callControl) {
            ControlWidgetButton(action: StartCallIntent()) {
                Label("Call", systemImage: "phone.fill")
            }
        }
        .displayName("Call")
        .description("Starts a call.")
    }
}

struct EndCallControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: PLCallKinds.endControl) {
            ControlWidgetButton(action: EndCallIntent()) {
                Label("End", systemImage: "phone.down.fill")
            }
        }
        .displayName("End")
        .description("Ends the call.")
    }
}

struct ApproveControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: PLCallKinds.approveControl) {
            ControlWidgetButton(action: ApproveIntent()) {
                Label("Approve", systemImage: "checkmark.circle.fill")
            }
        }
        .displayName("Approve")
        .description("Approves the request that is waiting. Asks for Face ID when the iPhone is locked.")
    }
}
