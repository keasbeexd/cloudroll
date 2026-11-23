import Darwin
import Foundation

/// What to call the device in messages: "iPad" on iPads, "iPhone" on everything else,
/// iPhone Duo included. Read from the hardware model rather than UIDevice, so it can be
/// used off the main actor (the local server's threads build some of these messages).
enum ThisDevice {
    static let name: String = model.hasPrefix("iPad") ? "iPad" : "iPhone"

    /// "iPad14,5", or the simulated device's identifier in the simulator.
    private static var model: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var size = 0
        guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &bytes, &size, nil, 0) == 0 else { return "" }
        return String(cString: bytes)
    }
}
