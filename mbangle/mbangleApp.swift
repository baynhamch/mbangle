import SwiftUI

@main
struct mbangleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("MacBook Air", id: "showcase") {
            ShowcaseView(alignment: delegate.alignment)
                .frame(minWidth: 820, minHeight: 640)
                .preferredColorScheme(.light)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1260, height: 800)
        .windowResizability(.contentMinSize)

        Settings {
            FeedbackSettingsView(feedback: delegate.feedback)
        }
        .windowResizability(.contentSize)
    }
}
