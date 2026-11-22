import Darwin
import Foundation

/// 捕获未捕获的 Objective-C 异常和致命信号，并记录最近的关键步骤。
/// 闪退后下次启动会把内容显示出来，方便没有 Mac 的情况下定位问题。
enum CrashLogger {
    private static let crashFileName = "last_crash.txt"
    private static let stepsFileName = "last_steps.log"
    private static let maxStepsBytes = 64_000
    private static let lock = NSLock()
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func install() {
        NSSetUncaughtExceptionHandler { exception in
            let text = """
            \(Date())
            name: \(exception.name.rawValue)
            reason: \(exception.reason ?? "")
            \(exception.callStackSymbols.joined(separator: "\n"))
            """
            write(text, to: crashFileName)
        }

        // 信号处理器只能使用最基础的 C 接口，路径提前转成 C 字符串。
        let path = documents.appendingPathComponent(crashFileName).path
        crashLogPath = strdup(path)
        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP] {
            signal(sig, crashSignalHandler)
        }
    }

    static func breadcrumb(_ message: String) {
        lock.lock()
        defer { lock.unlock() }

        let line = "\(formatter.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = documents.appendingPathComponent(stepsFileName)

        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: url, options: .atomic)
        }

        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? Int,
           size > maxStepsBytes {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// 正常退到后台时标记一次，避免下次启动把普通启动当成崩溃。
    static func markCleanExit() {
        breadcrumb("clean exit")
    }

    /// 读取并清空上次运行的诊断信息。没有异常时返回 nil。
    static func takeDiagnostics() -> String? {
        let crash = readAndRemove(crashFileName)
        let steps = readSteps()

        guard crash != nil || looksLikeUncleanExit(steps) else {
            remove(stepsFileName)
            return nil
        }

        remove(stepsFileName)
        var parts: [String] = []
        if let crash {
            parts.append("=== 崩溃信息 ===\n\(crash)")
        } else {
            parts.append("=== 上次运行没有正常结束（可能是被系统终止）===")
        }
        if !steps.isEmpty {
            parts.append("=== 最近步骤 ===\n\(steps)")
        }
        return parts.joined(separator: "\n\n")
    }

    // MARK: - 内部

    private static func looksLikeUncleanExit(_ steps: String) -> Bool {
        let lines = steps
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count > 1 else { return false }
        return lines.last?.hasSuffix("clean exit") != true
    }

    private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static func write(_ text: String, to name: String) {
        let url = documents.appendingPathComponent(name)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func readSteps() -> String {
        let url = documents.appendingPathComponent(stepsFileName)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private static func remove(_ name: String) {
        let url = documents.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
    }

    private static func readAndRemove(_ name: String) -> String? {
        let url = documents.appendingPathComponent(name)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return text
    }
}

/// 全局 C 函数，信号处理器里不能捕获上下文。
private var crashLogPath: UnsafeMutablePointer<CChar>?

private func crashSignalHandler(_ sig: Int32) {
    guard let path = crashLogPath else {
        signal(sig, SIG_DFL)
        raise(sig)
        return
    }

    let fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
    if fd >= 0 {
        let header: String
        switch sig {
        case SIGABRT: header = "\n=== 信号崩溃: SIGABRT ===\n"
        case SIGSEGV: header = "\n=== 信号崩溃: SIGSEGV（访问了无效内存）===\n"
        case SIGBUS: header = "\n=== 信号崩溃: SIGBUS ===\n"
        case SIGILL: header = "\n=== 信号崩溃: SIGILL ===\n"
        case SIGFPE: header = "\n=== 信号崩溃: SIGFPE ===\n"
        case SIGTRAP: header = "\n=== 信号崩溃: SIGTRAP ===\n"
        default: header = "\n=== 信号崩溃 ===\n"
        }
        header.withCString { pointer in
            _ = write(fd, pointer, strlen(pointer))
        }
        close(fd)
    }

    signal(sig, SIG_DFL)
    raise(sig)
}
