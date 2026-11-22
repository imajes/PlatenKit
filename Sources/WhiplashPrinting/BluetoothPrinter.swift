import CoreBluetooth
import Foundation

public struct NearbyPrinter: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let rssi: Int
    public let advertisedServices: [String]
}

/// Each delegate operation has one waiter and an inactivity deadline on Core Bluetooth's main queue.
@MainActor final class OperationResult<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Error>?
    private var timer: DispatchSourceTimer?
    private var interval = 0.0
    private var token: UUID?
    var pending: Bool { continuation != nil }

    func wait(seconds: Double, deadline: @escaping () -> Result<Value, Error>, start: () -> Void) async throws -> Value {
        try Task.checkCancellation()
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                token = id
                interval = seconds
                let timer = DispatchSource.makeTimerSource(queue: .main)
                self.timer = timer
                timer.setEventHandler { [weak self] in
                    guard let self, self.token == id else { return }
                    self.finish(deadline())
                }
                refresh()
                timer.resume()
                start()
            }
        } onCancel: {
            Task { @MainActor in
                if self.token == id { self.finish(.failure(CancellationError())) }
            }
        }
    }

    func refresh() { timer?.schedule(deadline: .now() + interval) }

    func finish(_ result: Result<Value, Error>) {
        timer?.cancel()
        timer = nil
        token = nil
        let waiter = continuation
        continuation = nil
        waiter?.resume(with: result)
    }
}

@MainActor public final class BluetoothPrinter: NSObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    public var onEvent: ((String) -> Void)?
    public var connectedID: UUID? { active?.state == .connected ? active?.identifier : nil }
    private lazy var central = CBCentralManager(delegate: self, queue: .main)
    private var seen: [UUID: (CBPeripheral, NearbyPrinter)] = [:]
    private var active: CBPeripheral?
    private var busy = false
    private let ready = OperationResult<Void>()
    private let scanning = OperationResult<Void>()
    private let connecting = OperationResult<Void>()
    private let inspecting = OperationResult<Void>()
    private let writing = OperationResult<Void>()
    private let subscribing = OperationResult<Void>()
    private let observing = OperationResult<Void>()
    private var remainingServices = Set<ObjectIdentifier>()
    private var inventory: [(PrinterEndpoint, CBCharacteristic)] = []
    private var writeTarget: CBCharacteristic?
    private var notificationTarget: CBCharacteristic?
    private var notificationEndpoint = ""
    private var tracingRongta = false
    private var replyBytes: Data?
    private var labelifeLink: LabelifeLink?
    private var deviceMessages = LabelifeMessages()
    private var pump: WritePump?

    private func begin() throws {
        guard !busy else { throw BenchError("Another printer operation is running.") }
        busy = true
    }

    public func scan(seconds: Double = 5) async throws -> [NearbyPrinter] {
        try begin()
        defer { busy = false }
        guard active == nil else { throw BenchError("Disconnect before scanning again.") }
        guard seconds.isFinite, (0.2...60).contains(seconds) else { throw BenchError("Scan duration must be 0.2–60 seconds.") }
        seen.removeAll()
        switch central.state {
        case .poweredOn: break
        case .unknown, .resetting:
            try await ready.wait(seconds: 8, deadline: { .failure(BenchError("Bluetooth readiness timed out. Check Bluetooth permission and the local controller.")) }, start: {})
        default: throw stateError(central.state)
        }
        onEvent?("Scanning for \(seconds) seconds")
        defer { if central.isScanning { central.stopScan() } }
        try await scanning.wait(seconds: seconds, deadline: { .success(()) }) {
            central.scanForPeripherals(withServices: nil)
        }
        return seen.values.map(\.1).sorted { $0.name == $1.name ? $0.id.uuidString < $1.id.uuidString : $0.name < $1.name }
    }

    public func connect(_ id: UUID) async throws {
        try begin()
        defer { busy = false }
        guard central.state == .poweredOn else { throw stateError(central.state) }
        guard active == nil, let (peripheral, device) = seen[id], peripheral.state == .disconnected else {
            throw BenchError("Select a disconnected peripheral from the current scan.")
        }
        active = peripheral
        peripheral.delegate = self
        onEvent?("Connecting to \(device.name) \(id.uuidString)")
        do {
            try await connecting.wait(seconds: 12, deadline: { .failure(BenchError("Connection timed out.")) }) {
                central.connect(peripheral)
            }
        } catch {
            disconnect()
            throw error
        }
    }

    public func inspect() async throws -> [PrinterEndpoint] {
        try begin()
        defer { busy = false }
        guard let peripheral = active, peripheral.state == .connected else { throw BenchError("Connect before inspecting services.") }
        inventory.removeAll()
        remainingServices.removeAll()
        do {
            try await inspecting.wait(seconds: 12, deadline: { .failure(BenchError("Service inspection timed out.")) }) {
                peripheral.discoverServices(nil)
            }
        } catch {
            disconnect()
            throw error
        }
        return inventory.map(\.0).sorted { $0.id < $1.id }
    }

    public func submit(_ job: LabelJob, to endpoint: PrinterEndpoint, mode preferred: WriteMode? = nil) async throws -> Submission {
        try begin()
        defer { busy = false }
        if job.model == .labelife && endpoint.id == "FF00/FF02" && inventory.contains(where: { $0.0.id == "FF00/FF03" && $0.1.properties.contains(.notify) }) {
            try await subscribe(to: "FF00/FF03", labelifeCredits: true)
        }
        onEvent?("Submit \(job.id) · \(job.model.name) · \(job.model.language) · \(job.stock.description)")
        let (mode, chunks) = try await transmit(job.bytes, to: endpoint, mode: preferred)
        let result = Submission(runID: job.id, mode: mode, bytes: job.bytes.count, chunks: chunks)
        onEvent?(result.description)
        return result
    }

    private func subscribe(to id: String, labelifeCredits: Bool) async throws {
        let matches = inventory.filter { $0.0.id == id && ($0.1.properties.contains(.notify) || $0.1.properties.contains(.indicate)) }
        guard let peripheral = active, peripheral.state == .connected, matches.count == 1 else {
            throw BenchError("This printer must expose a unique \(id) notification endpoint.")
        }
        let target = matches[0].1
        if target === notificationTarget && target.isNotifying { return }
        if let previous = notificationTarget, previous !== target, previous.isNotifying {
            throw BenchError("Reconnect before switching notification endpoints.")
        }
        notificationTarget = target
        notificationEndpoint = id
        labelifeLink = labelifeCredits ? LabelifeLink() : nil
        onEvent?("Host requesting notifications on \(id)")
        try await subscribing.wait(seconds: 12, deadline: { .failure(BenchError("Notification subscription timed out.")) }) {
            peripheral.setNotifyValue(true, for: target)
        }
    }

    /// Subscribe before the request so that even a reply arriving ahead of the write callback is captured.
    /// A quiet window has an empty result. It makes no assertion about printer health.
    public func rongtaStatus(to endpoint: PrinterEndpoint, mode: WriteMode? = nil) async throws -> Data {
        try begin()
        defer { busy = false; replyBytes = nil }
        let name = active.flatMap { seen[$0.identifier]?.1.name.uppercased() } ?? ""
        guard name.hasPrefix("RP421") || name.hasPrefix("RP-421") else { throw BenchError("Select the Rongta RP421 from the live scan.") }
        let reply = try RongtaDiagnostics.replyEndpoint(for: endpoint, in: inventory.map(\.0))
        tracingRongta = true
        try await subscribe(to: reply.id, labelifeCredits: false)
        onEvent?("Host Rongta status query · TX \(endpoint.id), RX \(reply.id)")
        replyBytes = Data()
        _ = try await transmit(RongtaDiagnostics.statusQuery, to: endpoint, mode: mode, printJob: false)
        try await observing.wait(seconds: 3, deadline: { .success(()) }, start: {})
        let bytes = replyBytes ?? Data()
        onEvent?("Status observation ended 3 s after submission · \(bytes.count) reply bytes captured")
        return bytes
    }

    private func transmit(_ bytes: Data, to endpoint: PrinterEndpoint, mode preferred: WriteMode?, printJob: Bool = true) async throws -> (WriteMode, Int) {
        let matches = inventory.filter { $0.0 == endpoint }
        guard let peripheral = active, peripheral.state == .connected, matches.count == 1 else {
            throw BenchError("Connect and select a unique endpoint from this printer's inspection.")
        }
        let mode = try endpoint.mode(preferred: preferred)
        let type: CBCharacteristicWriteType = mode == .acknowledged ? .withResponse : .withoutResponse
        let limit = peripheral.maximumWriteValueLength(for: type)
        let link = endpoint.id == "FF00/FF02" ? labelifeLink : nil
        pump = try WritePump(bytes, limit: limit, mode: mode, link: link)
        writeTarget = matches[0].1
        defer { pump = nil; writeTarget = nil }
        onEvent?("Writing \(bytes.count) bytes · \(endpoint.id) · \(mode.rawValue), limit \(limit)")
        do {
            try await writing.wait(seconds: 15, deadline: { .failure(BenchError("No Bluetooth write progress for 15 seconds.")) }) {
                sendAvailable()
            }
        } catch {
            let reason = error.localizedDescription
            let outcome = printJob ? (pump?.failure(reason) ?? BenchError(reason)) : BenchError("Status query failed. \(reason)")
            disconnect()
            throw outcome
        }
        return (mode, pump?.chunks ?? 0)
    }

    public func disconnect() {
        if central.isScanning { central.stopScan() }
        let peripheral = active
        if let peripheral { onEvent?("Host requested disconnect from \(peripheral.identifier)") }
        invalidate(BenchError("Disconnected by the caller."))
        if let peripheral, central.state == .poweredOn, peripheral.state != .disconnected {
            central.cancelPeripheralConnection(peripheral)
        }
    }

    private func invalidate(_ error: Error) {
        active?.delegate = nil
        active = nil
        notificationTarget = nil
        notificationEndpoint = ""
        tracingRongta = false
        labelifeLink = nil
        deviceMessages = LabelifeMessages()
        inventory.removeAll()
        remainingServices.removeAll()
        for operation in [ready, scanning, connecting, inspecting, writing, subscribing, observing] {
            operation.finish(.failure(error))
        }
    }

    private func sendAvailable() {
        guard writing.pending, let peripheral = active, let target = writeTarget, let mode = pump?.mode else { return }
        while let chunk = pump?.next(canQueue: peripheral.canSendWriteWithoutResponse) {
            if tracingRongta {
                onEvent?("HOST TX \(target.uuid.uuidString) packet \(pump?.chunks ?? 0) · \(RongtaDiagnostics.dump(chunk))")
            }
            peripheral.writeValue(chunk, for: target, type: mode == .acknowledged ? .withResponse : .withoutResponse)
            writing.refresh()
            if mode == .acknowledged { return }
        }
        if pump?.complete == true { writing.finish(.success(())) }
    }

    private func stateError(_ state: CBManagerState) -> BenchError {
        switch state {
        case .poweredOff: return BenchError("Bluetooth is turned off on this host.")
        case .unauthorized: return BenchError("Bluetooth access denied. Check Privacy & Security → Bluetooth for this app or terminal.")
        case .unsupported: return BenchError("This process cannot access a supported Bluetooth controller.")
        default: return BenchError("Bluetooth is unavailable (controller state \(state.rawValue)).")
        }
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            ready.finish(.success(()))
        } else if central.state != .unknown && central.state != .resetting {
            let error = stateError(central.state)
            onEvent?(error.localizedDescription)
            invalidate(error)
        } else if active != nil || scanning.pending {
            invalidate(stateError(central.state))
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard scanning.pending else { return }
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "(unnamed)"
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        seen[peripheral.identifier] = (peripheral, NearbyPrinter(id: peripheral.identifier, name: name, rssi: RSSI.intValue, advertisedServices: services.map(\.uuidString)))
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral === active, connecting.pending else { return }
        onEvent?("Connected to \(peripheral.identifier)")
        connecting.finish(.success(()))
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral === active else { return }
        connecting.finish(.failure(error ?? BenchError("Connection failed.")))
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral === active else { return }
        let reason = error ?? BenchError("Peripheral disconnected.")
        onEvent?(reason.localizedDescription)
        invalidate(reason)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === active, inspecting.pending else { return }
        if let error { inspecting.finish(.failure(error)); return }
        let services = peripheral.services ?? []
        guard !services.isEmpty else { inspecting.finish(.failure(BenchError("No GATT services were discovered."))); return }
        remainingServices = Set(services.map(ObjectIdentifier.init))
        for service in services { peripheral.discoverCharacteristics(nil, for: service) }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral === active, inspecting.pending, remainingServices.remove(ObjectIdentifier(service)) != nil else { return }
        if let error {
            onEvent?("Service \(service.uuid) could not be inspected: \(error.localizedDescription)")
        } else {
            for c in service.characteristics ?? [] {
                let flags: [(CBCharacteristicProperties, String)] = [(.read, "read"), (.write, "write"),
                    (.writeWithoutResponse, "writeWithoutResponse"), (.notify, "notify"), (.indicate, "indicate")]
                let properties = flags.compactMap { c.properties.contains($0.0) ? $0.1 : nil }
                let endpoint = PrinterEndpoint(service: service.uuid.uuidString, characteristic: c.uuid.uuidString, properties: properties)
                inventory.append((endpoint, c))
                onEvent?("Endpoint \(endpoint.description)")
            }
        }
        inspecting.refresh()
        if remainingServices.isEmpty {
            inspecting.finish(inventory.isEmpty ? .failure(BenchError("No characteristics could be inspected.")) : .success(()))
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === active, characteristic === writeTarget, writing.pending, pump?.mode == .acknowledged else { return }
        if let error {
            let detail = error as NSError
            onEvent?("Core Bluetooth write error · \(detail.domain) \(detail.code) · \(error.localizedDescription)")
            writing.finish(.failure(error))
            return
        }
        pump?.didAcknowledge()
        if tracingRongta { onEvent?("GATT ACK \(characteristic.uuid.uuidString) packet \(pump?.chunks ?? 0) · \(pump?.acknowledged ?? 0) bytes total") }
        sendAvailable()
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === active, characteristic === notificationTarget, subscribing.pending else { return }
        if let error { subscribing.finish(.failure(error)); return }
        guard characteristic.isNotifying else { subscribing.finish(.failure(BenchError("Notifications were not enabled."))); return }
        onEvent?("Listening on \(notificationEndpoint)")
        subscribing.finish(.success(()))
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === active, characteristic === notificationTarget else { return }
        if let error { onEvent?("Notification error: \(error.localizedDescription)"); return }
        guard let bytes = characteristic.value, !bytes.isEmpty else { return }
        if tracingRongta {
            onEvent?("PRINTER RX \(notificationEndpoint) · \(RongtaDiagnostics.dump(bytes))")
            if let count = replyBytes?.count, count < 65_536 {
                replyBytes?.append(contentsOf: bytes.prefix(65_536 - count))
            }
            return
        }
        let hadGrant = labelifeLink?.receivedGrant == true
        if labelifeLink?.receive(bytes) == true {
            if bytes.first == 2 { onEvent?("FF03 packet limit · \(labelifeLink?.packetLimit ?? 0) bytes") }
            else if !hadGrant { onEvent?("FF03 initial write credits · \(labelifeLink?.credits ?? 0)") }
            sendAvailable()
            return
        }
        for message in deviceMessages.append(bytes) {
            onEvent?("Printer · \(message)")
        }
    }

    public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        if peripheral === active && pump?.mode == .queued { sendAvailable() }
    }

    public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard peripheral === active, !invalidatedServices.isEmpty else { return }
        onEvent?("Printer services changed. Reconnect and inspect the new service list.")
        disconnect()
    }
}
