import Foundation

/// Resolves the branch shown by a tab hover card without letting rapid pointer
/// movement accumulate detached git processes.
enum HorizontalTabGitBranchLookup {
    nonisolated(unsafe) private static let cache = NSCache<NSString, BranchCacheEntry>()
    private static let cacheLifetime: TimeInterval = 5

    nonisolated static func branch(at workingDirectory: String) async -> String? {
        let key = workingDirectory as NSString
        if let cached = cache.object(forKey: key),
           Date().timeIntervalSince(cached.createdAt) < cacheLifetime
        {
            return cached.branch
        }

        let runner = GitBranchProcess()
        let branch = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(returning: runner.run(at: workingDirectory))
                }
            }
        } onCancel: {
            runner.cancel()
        }
        guard !Task.isCancelled else { return nil }
        cache.setObject(BranchCacheEntry(branch: branch), forKey: key)
        return branch
    }
}

private final class BranchCacheEntry {
    let branch: String?
    let createdAt = Date()

    init(branch: String?) {
        self.branch = branch
    }
}

private final class GitBranchProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var isCancelled = false

    func run(at workingDirectory: String) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", workingDirectory, "branch", "--show-current"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return nil
        }
        self.process = process
        lock.unlock()

        defer {
            lock.lock()
            self.process = nil
            lock.unlock()
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard !cancelled, process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let branch = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return branch.isEmpty ? nil : branch
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let runningProcess = process?.isRunning == true ? process : nil
        lock.unlock()
        runningProcess?.terminate()
    }

    private var cancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }
}
