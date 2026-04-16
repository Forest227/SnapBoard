import AppKit
import Foundation

// MARK: - Public API

/// Installs signal and exception handlers that persist a crash log to disk.
/// Call once, as early as possible in `applicationDidFinishLaunching`.
@MainActor
func installCrashHandlers() {
    CrashReporter.shared.install()
}

/// Checks whether a crash log was left by a previous run.
/// If found, shows a dialog and optionally copies the log to Downloads.
/// Call after the app is ready to present UI.
@MainActor
func checkForPreviousCrashLog() {
    CrashReporter.shared.checkAndPrompt()
}

// MARK: - File paths

private let crashLogDirectory: URL = {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return appSupport.appendingPathComponent("SnapBoard", isDirectory: true)
}()

private let crashLogPath: URL = crashLogDirectory.appendingPathComponent("last_crash.log")

/// Raw C-string path used inside async-signal-safe handlers.
/// Initialized once before signals are armed; read-only thereafter.
/// nonisolated(unsafe) silences the concurrency checker — the value is
/// effectively immutable after `install()` and signal handlers only read it.
nonisolated(unsafe) private var crashLogCPath: UnsafeMutablePointer<CChar>?

// MARK: - Signal handler (async-signal-safe)

private func signalHandler(sig: Int32) {
    guard let cPath = crashLogCPath else { _exit(sig) }

    let fd = open(cPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    guard fd >= 0 else { _exit(sig) }

    func writeStr(_ s: StaticString) {
        s.withUTF8Buffer { buf in
            _ = write(fd, buf.baseAddress, buf.count)
        }
    }

    func writeInt(_ value: Int32) {
        var n = value
        if n < 0 { _ = write(fd, "-", 1); n = -n }
        var digits: [UInt8] = []
        if n == 0 { digits.append(0x30) }
        while n > 0 { digits.append(UInt8(0x30 + n % 10)); n /= 10 }
        for d in digits.reversed() {
            var byte = d
            _ = write(fd, &byte, 1)
        }
    }

    writeStr("=== SnapBoard Crash Report ===\n")
    writeStr("Signal: ")
    writeInt(sig)
    writeStr(" (")
    switch sig {
    case SIGABRT: writeStr("SIGABRT")
    case SIGSEGV: writeStr("SIGSEGV")
    case SIGBUS:  writeStr("SIGBUS")
    case SIGFPE:  writeStr("SIGFPE")
    case SIGILL:  writeStr("SIGILL")
    case SIGTRAP: writeStr("SIGTRAP")
    default:      writeStr("UNKNOWN")
    }
    writeStr(")\n\n")

    writeStr("Backtrace:\n")
    var callStack = [UnsafeMutableRawPointer?](repeating: nil, count: 128)
    let frameCount = backtrace(&callStack, Int32(callStack.count))
    if frameCount > 0 {
        if let symbols = backtrace_symbols(&callStack, frameCount) {
            for i in 0 ..< Int(frameCount) {
                if let sym = symbols[i] {
                    let len = strlen(sym)
                    _ = write(fd, sym, len)
                    _ = write(fd, "\n", 1)
                }
            }
            free(symbols)
        }
    }

    writeStr("\n=== End of Report ===\n")
    close(fd)
    _exit(sig)
}

// MARK: - CrashReporter

@MainActor
private final class CrashReporter {
    static let shared = CrashReporter()

    private var installed = false

    func install() {
        guard !installed else { return }
        installed = true

        try? FileManager.default.createDirectory(at: crashLogDirectory, withIntermediateDirectories: true)

        crashLogCPath = strdup(crashLogPath.path)

        NSSetUncaughtExceptionHandler { exception in
            let report = CrashReporter.buildExceptionReport(exception)
            try? report.write(to: crashLogPath, atomically: true, encoding: .utf8)
        }

        let signals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGFPE, SIGILL, SIGTRAP]
        for sig in signals {
            signal(sig, signalHandler)
        }
    }

    func checkAndPrompt() {
        guard FileManager.default.fileExists(atPath: crashLogPath.path) else { return }

        guard let content = try? String(contentsOf: crashLogPath, encoding: .utf8),
              !content.isEmpty else {
            cleanup()
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "SnapBoard \u{4E0A}\u{6B21}\u{5F02}\u{5E38}\u{9000}\u{51FA}"
        alert.informativeText = "检测到上次运行时发生了崩溃，是否将崩溃日志保存到\u{300C}下载\u{300D}文件夹？"
        alert.addButton(withTitle: "保存日志")
        alert.addButton(withTitle: "忽略")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            saveCrashLogToDownloads(content)
        }

        cleanup()
    }

    private func saveCrashLogToDownloads(_ content: String) {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            showError("无法定位下载文件夹。")
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let fileName = "SnapBoard_Crash_\(timestamp).log"
        let destination = downloads.appendingPathComponent(fileName)

        do {
            try content.write(to: destination, atomically: true, encoding: .utf8)

            let successAlert = NSAlert()
            successAlert.alertStyle = .informational
            successAlert.messageText = "日志已保存"
            successAlert.informativeText = "崩溃日志已保存到：\n\(destination.path)"
            successAlert.addButton(withTitle: "在 Finder 中显示")
            successAlert.addButton(withTitle: "好的")
            let result = successAlert.runModal()

            if result == .alertFirstButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            }
        } catch {
            showError("保存失败：\(error.localizedDescription)")
        }
    }

    private func cleanup() {
        try? FileManager.default.removeItem(at: crashLogPath)
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "保存崩溃日志失败"
        alert.informativeText = message
        alert.addButton(withTitle: "好的")
        alert.runModal()
    }

    private static nonisolated func buildExceptionReport(_ exception: NSException) -> String {
        var lines: [String] = []
        lines.append("=== SnapBoard Crash Report ===")
        lines.append("Date: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("Exception: \(exception.name.rawValue)")
        lines.append("Reason: \(exception.reason ?? "unknown")")
        lines.append("")
        lines.append("User Info:")
        if let userInfo = exception.userInfo {
            for (key, value) in userInfo {
                lines.append("  \(key): \(value)")
            }
        } else {
            lines.append("  (none)")
        }
        lines.append("")
        lines.append("Call Stack:")
        for symbol in exception.callStackSymbols {
            lines.append("  \(symbol)")
        }
        lines.append("")
        lines.append("=== End of Report ===")
        return lines.joined(separator: "\n")
    }
}
