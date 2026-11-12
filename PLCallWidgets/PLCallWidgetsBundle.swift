import SwiftUI
import WidgetKit

/// Everything the one extension offers: the Live Activity, the Lock Screen widget and the controls.
@main
struct PLCallWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CallLiveActivity()
        StateWidget()
        CallControl()
        EndCallControl()
        ApproveControl()
    }
}
