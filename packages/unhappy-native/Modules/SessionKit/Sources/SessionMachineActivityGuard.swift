import Foundation
import CoreKit

public enum SessionMachineActivityGuard {
    private static let staleMachineGraceInterval: TimeInterval = 45

    public static func isEligibleForSessionSync(
        _ machine: APIMachine,
        now: Date = .now
    ) -> Bool {
        guard machine.active else { return false }
        guard machine.activeAt > 0 else { return false }
        return now.timeIntervalSince1970 - machine.activeAt <= staleMachineGraceInterval
    }

    public static func eligibleMachines(
        from machines: [APIMachine],
        now: Date = .now
    ) -> [APIMachine] {
        machines.filter { isEligibleForSessionSync($0, now: now) }
    }
}
