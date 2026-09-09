import Foundation
import CoreServices

/// Watches a library folder for changes made outside the app (another editor, a git pull, Finder, a
/// sync client) and reports them, a little after they stop, as paths relative to the root. The app's
/// own writes are not reported (the file system knows which process wrote), those are handled where
/// they happen. Ignores git's own folder, build output and Finder metadata.
public final class FolderWatcher {
    public let root: URL
    public var ignored: [String] = [".git", ".build", "node_modules", ".DS_Store", ".fseventsd"]
    private let latency: TimeInterval
    private let quiet: TimeInterval
    private let onChange: ([String]) -> Void
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "studio.folder-watcher")
    private var pending: Set<String> = []
    private var flush: DispatchWorkItem?
    private let rootPath: String
    /// The root as FSEvents may spell it: as given, and with symlinks resolved (/var is /private/var).
    private let rootPrefixes: [String]

    /// `onChange` runs on the main queue with the relative paths that changed, once nothing has changed
    /// for `quiet` seconds.
    public init(root: URL, latency: TimeInterval = 0.3, quiet: TimeInterval = 0.6, onChange: @escaping ([String]) -> Void) {
        self.root = root
        self.latency = latency
        self.quiet = quiet
        self.onChange = onChange
        rootPath = root.standardizedFileURL.path
        var real = [UInt8](repeating: 0, count: Int(PATH_MAX))
        let resolved = realpath(rootPath, &real).map { String(cString: $0) } ?? root.resolvingSymlinksInPath().path
        rootPrefixes = Array(Set([rootPath, resolved])).map { $0.hasSuffix("/") ? $0 : $0 + "/" }
    }

    deinit { stop() }

    public func start() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagIgnoreSelf | kFSEventStreamCreateFlagNoDefer)
        guard let s = FSEventStreamCreate(nil, { _, info, count, paths, _, _ in
            guard let info else { return }
            let me = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            guard let list = unsafeBitCast(paths, to: CFArray.self) as? [String] else { return }
            me.record(Array(list.prefix(count)))
        }, &context, [rootPath] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else { return }
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        stream = s
    }

    public func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    private func record(_ absolute: [String]) {
        for p in absolute {
            let prefix = rootPrefixes.first { p.hasPrefix($0) }
            let rel = prefix.map { String(p.dropFirst($0.count)) } ?? (rootPrefixes.contains(p + "/") ? "" : p)
            let parts = rel.split(separator: "/").map(String.init)
            if parts.contains(where: { ignored.contains($0) }) { continue }
            pending.insert(rel)
        }
        flush?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let paths = Array(self.pending).sorted()
            self.pending = []
            guard !paths.isEmpty else { return }
            DispatchQueue.main.async { self.onChange(paths) }
        }
        flush = work
        queue.asyncAfter(deadline: .now() + quiet, execute: work)
    }
}
