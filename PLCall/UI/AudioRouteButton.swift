import AVKit
import SwiftUI

/// The system's own audio picker: Speaker, iPhone (the earpiece) or AirPods, like the Phone app's audio button.
struct AudioRouteButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        picker.tintColor = .white
        picker.activeTintColor = UIColor(red: 0.910, green: 0.392, blue: 0.118, alpha: 1)
        picker.accessibilityLabel = "Audio: speaker, iPhone or AirPods"
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
