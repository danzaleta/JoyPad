import SwiftUI
import JoyPadClientCore

@main
struct JoyPadClientApp: App {
    @StateObject private var session = PadSessionClient()

    var body: some Scene {
        WindowGroup {
            UniversalPadMainView(session: session)
                .onAppear {
                    session.startDiscovery()
                }
        }
    }
}
