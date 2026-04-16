import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installCrashHandlers()

        appState.configureApplication()
        statusBarController = StatusBarController(appState: appState)

        // Defer the crash-log prompt so the status bar is ready first
        DispatchQueue.main.async {
            checkForPreviousCrashLog()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.tearDown()
        statusBarController?.tearDown()
        statusBarController = nil
    }
}
