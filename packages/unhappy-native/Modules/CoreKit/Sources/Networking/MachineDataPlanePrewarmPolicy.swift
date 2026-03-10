import Foundation
import Network

public protocol MachineDataPlanePrewarmPolicy: Sendable {
    func allowsBackgroundPrewarm() async -> Bool
}

public actor DefaultMachineDataPlanePrewarmPolicy: MachineDataPlanePrewarmPolicy {
    public static let shared = DefaultMachineDataPlanePrewarmPolicy()

    private struct PathSnapshot: Sendable {
        let isSatisfied: Bool
        let isExpensive: Bool
        let isConstrained: Bool

        init(path: NWPath) {
            isSatisfied = path.status == .satisfied
            isExpensive = path.isExpensive
            isConstrained = path.isConstrained
        }

        var allowsBackgroundPrewarm: Bool {
            isSatisfied && !isExpensive && !isConstrained
        }
    }

    private let monitor: NWPathMonitor
    private let queue: DispatchQueue
    private var latestSnapshot: PathSnapshot?

    public init() {
        monitor = NWPathMonitor()
        queue = DispatchQueue(label: "im.unhappy.machine-data-plane-prewarm-path")
        monitor.pathUpdateHandler = { [weak self] path in
            let snapshot = PathSnapshot(path: path)
            Task {
                await self?.store(snapshot)
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    public func allowsBackgroundPrewarm() async -> Bool {
        latestSnapshot?.allowsBackgroundPrewarm ?? false
    }

    private func store(_ snapshot: PathSnapshot) {
        latestSnapshot = snapshot
    }
}
