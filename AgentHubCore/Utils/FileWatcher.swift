import Foundation

/// FSEvents 기반 파일 변경 감시
public class FileWatcher {
    private let paths: [String]
    private let callback: () -> Void
    private var stream: FSEventStreamRef?

    public init(paths: [String], callback: @escaping () -> Void) {
        self.paths = paths
        self.callback = callback
    }

    deinit {
        stop()
    }

    public func start() {
        guard stream == nil else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { (
            stream,
            info,
            numEvents,
            eventPaths,
            eventFlags,
            eventIds
        ) in
            guard let info = info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.handleEvents()
        }

        let pathsToWatch = paths as CFArray

        stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,  // 1초 지연
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        )

        guard let stream = stream else { return }

        FSEventStreamScheduleWithRunLoop(
            stream,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )

        FSEventStreamStart(stream)
    }

    public func stop() {
        guard let stream = stream else { return }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func handleEvents() {
        DispatchQueue.main.async { [weak self] in
            self?.callback()
        }
    }
}
