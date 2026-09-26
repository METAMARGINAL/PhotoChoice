import SwiftUI

struct ContentView: View {
    @Bindable var session: PhotoSession

    var body: some View {
        Group {
            if session.isViewing {
                ViewerView(session: session)
            } else {
                ScrollView {
                    SetupView(session: session)
                        .frame(maxWidth: .infinity)
                }
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}

#Preview {
    ContentView(session: PhotoSession())
}
