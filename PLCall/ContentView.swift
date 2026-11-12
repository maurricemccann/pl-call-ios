import SwiftUI

/// Build 0: proves the GitHub Mac build and the SideStore install. Nothing else.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "phone.fill")
                .font(.system(size: 44))
            Text("Call")
                .font(.largeTitle.weight(.semibold))
            Text("Hello. This build installed.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
}
