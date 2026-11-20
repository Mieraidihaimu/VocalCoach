import AppKit
import SwiftUI

@main
struct ArticulateApp: App {
    var body: some Scene {
        Window("Articulate", id: "practice") {
            PracticeView()
                .frame(minWidth: 970, minHeight: 670)
                .preferredColorScheme(.light)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1136, height: 750)
        .commands {
            CommandGroup(after: .help) {
                Button("Audio Credits") {
                    if let credits = Bundle.main.url(forResource: "Credits", withExtension: "txt",
                                                     subdirectory: "AudioExamples") {
                        NSWorkspace.shared.open(credits)
                    }
                }
            }
        }
    }
}
