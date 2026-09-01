import AppKit
import Foundation

@main
enum JisprMain {
    @MainActor static var delegate: AppDelegate?

    static func main() {
        let args = CommandLine.arguments
        if args.count >= 3, args[1] == "--transcribe" {
            // Developer mode: transcribe an audio file and print the text.
            let path = args[2]
            let engineName = args.count >= 4 ? args[3] : nil
            Task {
                let code = await FileTranscription.run(path: path, engineName: engineName)
                exit(code)
            }
            RunLoop.main.run()
            return
        }

        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            JisprMain.delegate = delegate
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            app.run()
        }
    }
}
