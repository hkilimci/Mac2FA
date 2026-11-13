import Foundation
import IOBluetooth
import Network
import Observation

@MainActor
@Observable
final class ProximityStatus {
    struct Device: Identifiable {
        let id: String
        let name: String
    }

    enum Signal: String, CaseIterable {
        case bluetooth = "Bluetooth"
        case network = "Network"
    }

    var signal = Signal(rawValue: UserDefaults.standard.string(forKey: "proximitySignal") ?? "") ?? .bluetooth {
        didSet { UserDefaults.standard.set(signal.rawValue, forKey: "proximitySignal") }
    }
    var deviceID = UserDefaults.standard.string(forKey: "proximityDeviceID") ?? "" {
        didSet { UserDefaults.standard.set(deviceID, forKey: "proximityDeviceID") }
    }
    var address = UserDefaults.standard.string(forKey: "proximityAddress") ?? "" {
        didSet { UserDefaults.standard.set(address, forKey: "proximityAddress") }
    }
    private(set) var message: String?
    private(set) var isChecking = false

    func pairedDevices() -> [Device] {
        devices().compactMap { device in
            guard let id = device.addressString else { return nil }
            return Device(id: id, name: device.name ?? id)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        let selectedSignal = signal
        switch selectedSignal {
        case .bluetooth:
            guard let device = devices().first(where: { $0.addressString == deviceID }) else {
                message = "Choose a paired Bluetooth device."
                return
            }
            message = device.isConnected() ? "Device connected." : "Device disconnected."
        case .network:
            let host = address.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let ip = IPv4Address(host), ip.debugDescription == host else {
                message = "Enter a numeric IPv4 address."
                return
            }
            let reachable = await Task.detached(priority: .utility) { Self.ping(host) }.value
            guard signal == selectedSignal, address.trimmingCharacters(in: .whitespacesAndNewlines) == host else {
                return
            }
            message = reachable ? "Address responded." : "Address did not respond."
        }
    }

    func resetMessage() {
        message = nil
    }

    private func devices() -> [IOBluetoothDevice] {
        IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
    }

    private nonisolated static func ping(_ host: String) -> Bool {
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/sbin/ping")
        probe.arguments = ["-n", "-c", "1", "-W", "1000", "-t", "2", host]
        probe.standardOutput = FileHandle.nullDevice
        probe.standardError = FileHandle.nullDevice
        do {
            try probe.run()
            probe.waitUntilExit()
            return probe.terminationStatus == 0
        } catch {
            return false
        }
    }
}
