import SwiftUI
import MyAppCore

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "swift")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text(Greeter.greeting(for: ""))
                .font(.title2)
                .accessibilityIdentifier("greeting")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
