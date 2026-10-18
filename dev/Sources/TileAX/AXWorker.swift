// Where Accessibility calls run (architecture TA-13): one serial queue per app, so a hung
// or slow app blocks only its own queue, and one thread with a run loop for observers.
import ApplicationServices
import Foundation
import TileLog

public final class AXWorker: @unchecked Sendable {
    // @unchecked: the queue table is guarded by the lock; queues and the thread are thread-safe.

    /// How long TILE32 waits for any app to answer before treating it as unavailable.
    public static let messagingTimeout: Float = 0.5

    public static let shared = AXWorker()

    private let lock = NSLock()
    private var queues: [pid_t: DispatchQueue] = [:]
    public let observerThread = AXObserverThread()

    private init() {
        // A timeout on the system-wide element applies to every element without its own.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), Self.messagingTimeout)
        observerThread.start()
    }

    /// Runs blocking Accessibility work on the app's own serial queue.
    public func run<T: Sendable>(for pid: pid_t, _ work: @escaping @Sendable () -> T) async -> T {
        let queue = queue(for: pid)
        return await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    /// Drops the queue of an app that quit.
    public func forget(_ pid: pid_t) {
        lock.withLock { _ = queues.removeValue(forKey: pid) }
    }

    private func queue(for pid: pid_t) -> DispatchQueue {
        lock.withLock {
            if let queue = queues[pid] { return queue }
            let queue = DispatchQueue(label: "com.66ideas.tile32.ax.\(pid)", qos: .userInitiated)
            queues[pid] = queue
            return queue
        }
    }
}

/// A dedicated thread with its own run loop for all `AXObserver` sources (TA-9, TA-13).
/// Observers are registered in task T-1.2; the callbacks only forward small events.
public final class AXObserverThread: Thread, @unchecked Sendable {
    // @unchecked: the run loop reference is written once on the thread before the
    // semaphore is signalled, and only read afterwards.
    private var runLoop: CFRunLoop?
    private let ready = DispatchSemaphore(value: 0)

    public override init() {
        super.init()
        name = "com.66ideas.tile32.ax-observers"
        qualityOfService = .userInitiated
    }

    public override func main() {
        runLoop = CFRunLoopGetCurrent()
        // A port keeps the run loop alive while no observer is registered yet.
        RunLoop.current.add(NSMachPort(), forMode: .default)
        ready.signal()
        while !isCancelled {
            RunLoop.current.run(mode: .default, before: .distantFuture)
        }
    }

    /// Runs a block on the observer thread, for example to add or remove an observer source.
    public func perform(_ block: @escaping @Sendable () -> Void) {
        if runLoop == nil { ready.wait(); ready.signal() }
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }
}
