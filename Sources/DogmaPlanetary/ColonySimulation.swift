//
//  ColonySimulation.swift
//  DogmaPlanetary
//
//  Created by Artem Shimanski on 14.10.2026.
//

import Foundation

/// Event-driven colony simulation from the snapshot moment forward, with a mandatory horizon.
///
/// Rules:
///
/// 1. **End of an ECU / processor cycle**: the output is pushed through the source's outgoing routes in `route_id`
///    order; each receiver takes what it can. What does not fit is LOST (`wasted`), as in the game.
/// 2. **Receipt into storage** (command center, storage, launchpad): the storage immediately pushes the cargo into
///    processors whose input routes start at it (in `route_id` order). Storage-to-storage routes do not run
///    **[unverified]**, as in the game.
/// 3. A **processor** pulls inputs from the source storages of its input routes up to the schematic's need (the
///    buffer is exactly one cycle), starts as soon as the buffer is full, and immediately pulls the buffer for the
///    next cycle. Surplus commodities in the buffer do not block a start.
/// 4. A pin without an outgoing route works; its output is lost.
/// 5. Within one moment events are processed in the order: ECUs, then processors by output tier (P1 < ... < P4),
///    then by `PinIndex`, so the order is fully deterministic.
///
/// A route's `quantity` is not treated as a limit. Customs, taxes and manual export are outside the simulation.
///
/// State carries over between calls: `run(until: a)` then `run(until: b)` gives the same as one `run(until: b)`,
/// but with totals for two windows.
public struct ColonySimulation: Sendable {

    public struct Options: Sendable {
        /// Record pin contents after every change (`Forecast.timeline`).
        public var timeline: Bool
        /// Loop guard: the run stops after this many events (14 days of an ECU program with a 15-minute cycle is 1344 events).
        public var maxEvents: Int

        public init(timeline: Bool = false, maxEvents: Int = 1_000_000) {
            self.timeline = timeline
            self.maxEvents = maxEvents
        }
    }

    /// The colony at the current simulation moment: pin contents and cycle state are written back after each `run`.
    public private(set) var colony: Colony
    /// Current simulation moment; the snapshot moment before the first `run`.
    public private(set) var time: Date

    private typealias PinIndex = Colony.PinIndex
    private typealias Schematic = DogmaPlanetaryData.Schematic

    private var started = false
    private let order: [Int]
    private let schematics: [Schematic?]
    private let programs: [ExtractorProgram?]
    private let products: [TypeID?]
    private var processorStart: [Date?]
    private var processorEnd: [Date?]
    private var pendingCycle: [Int?]
    private var isIdle: [Bool]
    private var isFull: [Bool]
    private var isWasting: [Bool]
    private var lastRecorded: [Inventory]
    private var forecast: Forecast
    private var recordsTimeline = false

    public init(_ colony: Colony) {
        self.colony = colony
        self.time = colony.snapshotTime
        let count = colony.pins.count

        var schematics = [Schematic?](repeating: nil, count: count)
        var programs = [ExtractorProgram?](repeating: nil, count: count)
        var products = [TypeID?](repeating: nil, count: count)
        var processorStart = [Date?](repeating: nil, count: count)
        var processorEnd = [Date?](repeating: nil, count: count)
        var pendingCycle = [Int?](repeating: nil, count: count)
        var priority = [Int](repeating: Int.max, count: count)
        for (i, pin) in colony.pins.enumerated() {
            switch pin.role {
            case .storage:
                break
            case .processor(let processor):
                let schematic = processor.schematicID.flatMap { colony.catalog.schematic($0) }
                schematics[i] = schematic
                if let schematic, let end = processor.runningCycleEnd {
                    processorEnd[i] = end
                    processorStart[i] = end.addingTimeInterval(-TimeInterval(schematic.cycleTime))
                }
                let tier = schematic.flatMap { colony.catalog.commodity($0.output.typeID)?.tier }
                priority[i] = 1 + Int(tier?.rawValue ?? 0)
            case .extractor(let extractor):
                programs[i] = extractor.program
                products[i] = extractor.productTypeID
                pendingCycle[i] = extractor.program == nil ? nil : extractor.pendingCycle
                priority[i] = 0
            }
        }
        self.order = (0..<count).sorted { (priority[$0], $0) < (priority[$1], $1) }
        self.schematics = schematics
        self.programs = programs
        self.products = products
        self.processorStart = processorStart
        self.processorEnd = processorEnd
        self.pendingCycle = pendingCycle
        self.isIdle = Array(repeating: false, count: count)
        self.isFull = Array(repeating: false, count: count)
        self.isWasting = Array(repeating: false, count: count)
        self.lastRecorded = colony.pins.map(\.contents)
        self.forecast = Forecast(from: colony.snapshotTime, to: colony.snapshotTime, pinCount: count)
    }

    /// Advances the simulation to `date` inclusive and returns the totals of the window `(time, date]` (the first
    /// window includes the snapshot moment). If `date` is not later than the current moment, nothing happens and the window is empty.
    public mutating func run(until date: Date, options: Options = Options()) -> Forecast {
        forecast = Forecast(from: time, to: max(date, time), pinCount: colony.pins.count)
        recordsTimeline = options.timeline

        if !started {
            started = true
            if recordsTimeline {
                for (i, pin) in colony.pins.enumerated() {
                    forecast.timeline.append(.init(date: time, pin: PinIndex(rawValue: UInt16(i)), contents: pin.contents))
                }
            }
            for i in order where schematics[i] != nil {
                tryStart(i, at: time)
            }
            recordChanges(at: time)
        }

        var processed = 0
        while let next = nextEventTime(), next <= date {
            guard processed < options.maxEvents else {
                forecast.isTruncated = true
                break
            }
            accumulateBusyTime(until: next)
            time = next
            for i in order where nextEvent(of: i) == next {
                handleEvent(of: i, at: next)
                processed += 1
            }
            recordChanges(at: next)
        }
        if !forecast.isTruncated, date > time {
            accumulateBusyTime(until: date)
            time = date
        }

        writeBack()
        return forecast
    }

    // MARK: - Events

    private func nextEvent(of i: Int) -> Date? {
        if let end = processorEnd[i] { return end }
        if let cycle = pendingCycle[i], let program = programs[i] { return program.cycleEnd(cycle) }
        return nil
    }

    private func nextEventTime() -> Date? {
        var result: Date?
        for i in order {
            if let date = nextEvent(of: i), result.map({ date < $0 }) ?? true {
                result = date
            }
        }
        return result
    }

    private mutating func handleEvent(of i: Int, at date: Date) {
        if let schematic = schematics[i], processorEnd[i] == date {
            processorEnd[i] = nil
            let output = schematic.output
            forecast.pins[i].cycles += 1
            emit(from: i, typeID: output.typeID, quantity: Int(output.quantity), at: date)
            tryStart(i, at: date)
        } else if let cycle = pendingCycle[i], let program = programs[i], let product = products[i] {
            forecast.pins[i].cycles += 1
            emit(from: i, typeID: product, quantity: program.yield(cycle: cycle), at: date)
            if cycle + 1 < program.cycleCount {
                pendingCycle[i] = cycle + 1
            } else {
                pendingCycle[i] = nil
                forecast.events.append(.extractorFinished(pin(i), at: date))
            }
        }
    }

    /// Cycle output: counted as produced, pushed through routes, the remainder is lost.
    private mutating func emit(from source: Int, typeID: TypeID, quantity: Int, at date: Date) {
        guard quantity > 0 else { return }
        forecast.pins[source].produced[typeID] += quantity
        let delivered = deliver(from: source, typeID: typeID, quantity: quantity, at: date)
        let wasted = quantity - delivered
        if wasted > 0 {
            forecast.pins[source].wasted[typeID] += wasted
            if !isWasting[source] {
                isWasting[source] = true
                forecast.events.append(.outputWasted(pin(source), typeID: typeID, at: date))
            }
        } else {
            isWasting[source] = false
        }
    }

    // MARK: - Transfers

    /// Distributes cargo over a source's outgoing routes; returns how much was accepted.
    private mutating func deliver(from source: Int, typeID: TypeID, quantity: Int, at date: Date) -> Int {
        var remaining = quantity
        for route in colony.routes(from: pin(source)) where route.typeID == typeID {
            guard remaining > 0 else { break }
            let destination = Int(route.destination.rawValue)
            let accepted = min(remaining, accept(destination, typeID))
            if isStorage(destination) {
                if accepted < remaining {
                    if !isFull[destination] {
                        isFull[destination] = true
                        forecast.events.append(.storageFull(route.destination, at: date))
                    }
                } else {
                    isFull[destination] = false
                }
            }
            guard accepted > 0 else { continue }
            move(typeID, quantity: accepted, from: source, to: destination)
            remaining -= accepted
            if isStorage(destination) {
                push(from: destination, at: date)
            } else if schematics[destination] != nil {
                tryStart(destination, at: date)
            }
        }
        return quantity - remaining
    }

    /// A storage pushes its contents into the processors of its outgoing routes.
    private mutating func push(from storage: Int, at date: Date) {
        for route in colony.routes(from: pin(storage)) {
            let destination = Int(route.destination.rawValue)
            guard schematics[destination] != nil else { continue }
            let quantity = min(colony.pins[storage].contents[route.typeID], accept(destination, route.typeID))
            guard quantity > 0 else { continue }
            move(route.typeID, quantity: quantity, from: storage, to: destination)
            tryStart(destination, at: date)
        }
    }

    /// A processor pulls inputs from the source storages of its input routes.
    private mutating func pull(into processor: Int) {
        for route in colony.routes(to: pin(processor)) {
            let source = Int(route.source.rawValue)
            guard isStorage(source) else { continue }
            let quantity = min(colony.pins[source].contents[route.typeID], accept(processor, route.typeID))
            guard quantity > 0 else { continue }
            move(route.typeID, quantity: quantity, from: source, to: processor)
        }
    }

    private mutating func tryStart(_ processor: Int, at date: Date) {
        guard let schematic = schematics[processor] else { return }
        pull(into: processor)
        guard processorEnd[processor] == nil else { return }
        let contents = colony.pins[processor].contents
        guard schematic.inputs.allSatisfy({ contents[$0.typeID] >= Int($0.quantity) }) else {
            if !isIdle[processor] {
                isIdle[processor] = true
                forecast.events.append(.processorIdle(pin(processor), at: date))
            }
            return
        }
        for input in schematic.inputs {
            colony.pins[processor].contents[input.typeID] -= Int(input.quantity)
            forecast.pins[processor].consumed[input.typeID] += Int(input.quantity)
        }
        processorStart[processor] = date
        processorEnd[processor] = date.addingTimeInterval(TimeInterval(schematic.cycleTime))
        if isIdle[processor] {
            isIdle[processor] = false
            forecast.events.append(.processorResumed(pin(processor), at: date))
        }
        pull(into: processor)
    }

    /// How many units of `typeID` the pin will accept right now.
    private func accept(_ i: Int, _ typeID: TypeID) -> Int {
        let pin = colony.pins[i]
        if let schematic = schematics[i] {
            guard let input = schematic.inputs.first(where: { $0.typeID == typeID }) else { return 0 }
            return max(0, Int(input.quantity) - pin.contents[typeID])
        }
        guard isStorage(i), let volume = colony.catalog.commodity(typeID)?.volume, volume > 0 else { return 0 }
        let free = pin.capacity - pin.contents.volume(in: colony.catalog)
        // The epsilon absorbs `Double` error: 12000 / 0.19 at the boundary must not lose a unit.
        return max(0, Int((free / volume + 1e-9).rounded(.down)))
    }

    private mutating func move(_ typeID: TypeID, quantity: Int, from source: Int, to destination: Int) {
        if isStorage(source) {
            colony.pins[source].contents[typeID] -= quantity
        }
        colony.pins[destination].contents[typeID] += quantity
        forecast.pins[source].sent[typeID] += quantity
        forecast.pins[destination].received[typeID] += quantity
    }

    private func isStorage(_ i: Int) -> Bool {
        colony.pins[i].role == .storage
    }

    private func pin(_ i: Int) -> PinIndex {
        PinIndex(rawValue: UInt16(i))
    }

    // MARK: - Accounting

    private mutating func accumulateBusyTime(until date: Date) {
        let delta = date.timeIntervalSince(time)
        guard delta > 0 else { return }
        for i in order where processorEnd[i] != nil {
            forecast.pins[i].busyTime += delta
        }
    }

    private mutating func recordChanges(at date: Date) {
        guard recordsTimeline else { return }
        for (i, pin) in colony.pins.enumerated() where pin.contents != lastRecorded[i] {
            lastRecorded[i] = pin.contents
            forecast.timeline.append(.init(date: date, pin: self.pin(i), contents: pin.contents))
        }
    }

    /// Writes the cycle state back into `colony` so that it describes moment `time`.
    private mutating func writeBack() {
        for i in colony.pins.indices {
            switch colony.pins[i].role {
            case .storage:
                break
            case .processor(var processor):
                processor.runningCycleEnd = processorEnd[i]
                processor.lastCycleStart = processorStart[i] ?? processor.lastCycleStart
                colony.pins[i].role = .processor(processor)
            case .extractor(var extractor):
                extractor.pendingCycle = pendingCycle[i]
                if let cycle = pendingCycle[i], let program = programs[i] {
                    extractor.lastCycleStart = program.cycleStart(cycle)
                }
                colony.pins[i].role = .extractor(extractor)
            }
        }
        if !recordsTimeline {
            lastRecorded = colony.pins.map(\.contents)
        }
    }
}
