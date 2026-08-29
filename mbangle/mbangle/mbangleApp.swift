//
//  mbangleApp.swift
//  mbangle
//
//  Created by nick on 8/28/26.
//

import SwiftUI

@main
struct mbangleApp: App {
    // All behavior lives in the delegate. There is intentionally no WindowGroup:
    // the app must never put anything on screen unless the hotkey is pressed.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // A Settings scene satisfies App's requirement without opening a window
        // at launch. With no menu bar there is no way to open it by accident.
        Settings { EmptyView() }
    }
}
