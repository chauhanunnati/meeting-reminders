import AppKit
import EventKit

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let config: Config
    private let watcher: CalendarWatcher
    private var overlay: OverlayController?
    private let testMode: Bool

    init(testMode: Bool) {
        self.testMode = testMode
        self.config = Config.load()
        self.watcher = CalendarWatcher(config: config)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = OverlayController(config: config)

        if testMode {
            // Show the animation once with dummy data, then quit.
            let fakeStart = Date().addingTimeInterval(5 * 60)
            overlay?.show(
                title: "Test Meeting — Standup with Engineering",
                startDate: fakeStart,
                minutesUntil: 5
            ) {
                NSApp.terminate(nil)
            }
            return
        }

        watcher.onMeetingSoon = { [weak self] event in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let title = self.watcher.displayTitle(for: event)
                let minutesUntil = max(1, Int(round(event.startDate.timeIntervalSinceNow / 60)))
                self.overlay?.show(
                    title: title,
                    startDate: event.startDate,
                    minutesUntil: minutesUntil,
                    completion: nil
                )
            }
        }
        watcher.start()
    }
}

// MARK: - Entry point

let args = CommandLine.arguments
let testMode = args.contains("--test")

let app = NSApplication.shared
let delegate = AppDelegate(testMode: testMode)
app.delegate = delegate
// .accessory = no Dock icon, no main menu — pure background process.
app.setActivationPolicy(.accessory)
app.run()
