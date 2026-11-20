import AppKit
import SwiftUI

@main
struct VocalCoachApp: App {
    var body: some Scene {
        Window("Vocal Coach", id: "practice") {
            CoachView()
        }
        .defaultSize(width: 750, height: 430)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .help) {
                Button("Audio and Software Credits") {
                    if let credits = Bundle.main.url(forResource: "Credits", withExtension: "txt", subdirectory: "Resources") {
                        NSWorkspace.shared.open(credits)
                    }
                }
            }
        }
    }
}
