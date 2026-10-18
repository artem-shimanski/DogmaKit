//
//  Colony+Read.swift
//  DogmaPlanetary
//
//  Created by Artem Shimanski on 14.10.2026.
//

import Foundation

// MARK: - Pin name

extension Colony.Pin {
    /// The pin's in-client name, `XX-YYY` from `pinID`: the low five digits in base 34 over an alphabet without zero,
    /// with a hyphen after the second. The alphabet has 35 characters for base 34 (the last, `Z`, is unreachable).
    /// Match with the client **[unverified]**.
    public var name: String {
        Colony.pinName(pinID)
    }
}

extension Colony {
    static func pinName(_ pinID: Int64) -> String {
        let alphabet = Array("123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let base = Int64(alphabet.count - 1)
        var value = pinID.magnitude
        var name = ""
        for i in 0..<5 {
            if i == 2 { name.append("-") }
            name.append(alphabet[Int(value % UInt64(base))])
            value /= UInt64(base)
        }
        return name
    }
}

// MARK: - Pin state

extension Colony {

    /// Occupied storage volume, m3 (for a processor, the buffer volume).
    public func usedVolume(of pin: PinIndex) -> Double {
        self[pin].contents.volume(in: catalog)
    }

    /// Free storage volume, m3; 0 for processors and ECUs.
    public func freeVolume(of pin: PinIndex) -> Double {
        max(0, self[pin].capacity - usedVolume(of: pin))
    }

    /// Storage fill fraction, 0...1; `nil` for pins without capacity.
    public func fill(of pin: PinIndex) -> Double? {
        let capacity = self[pin].capacity
        return capacity > 0 ? usedVolume(of: pin) / capacity : nil
    }

    /// The nearest moment something happens to the pin: the end of a processor's running cycle or of the ECU's
    /// current cycle. `nil` if the pin is waiting (idle, program finished) or is a storage.
    public func nextEvent(of pin: PinIndex) -> Date? {
        switch self[pin].role {
        case .storage:
            nil
        case .processor(let processor):
            processor.runningCycleEnd
        case .extractor(let extractor):
            extractor.pendingCycle.flatMap { cycle in extractor.program?.cycleEnd(cycle) }
        }
    }

    /// Nominal pin throughput in units per hour, ignoring idle time: a processor by its schematic, an ECU as the
    /// average over the REMAINING part of the program (output declines toward the end, so a whole-program average
    /// would mislead). Empty for storages and unconfigured pins.
    public func hourlyRate(of pin: PinIndex) -> Rate {
        switch self[pin].role {
        case .storage:
            return Rate()
        case .processor:
            guard let schematic = schematic(of: pin), schematic.cycleTime > 0 else { return Rate() }
            let perHour = 3600 / Double(schematic.cycleTime)
            var rate = Rate()
            rate.outputs[schematic.output.typeID] = Double(schematic.output.quantity) * perHour
            for input in schematic.inputs {
                rate.inputs[input.typeID] = Double(input.quantity) * perHour
            }
            return rate
        case .extractor(let extractor):
            guard let program = extractor.program, let product = extractor.productTypeID,
                  let first = extractor.pendingCycle else { return Rate() }
            let cycles = first..<program.cycleCount
            let total = cycles.reduce(0) { $0 + program.yield(cycle: $1) }
            let hours = Double(cycles.count * program.cycleTime) / 3600
            var rate = Rate()
            rate.outputs[product] = hours > 0 ? Double(total) / hours : 0
            return rate
        }
    }

    /// Units per hour by commodity.
    public struct Rate: Hashable, Sendable {
        public var inputs: [TypeID: Double] = [:]
        public var outputs: [TypeID: Double] = [:]
        public init() {}
    }
}

// MARK: - Forecast: catch-up plus future

extension Colony {

    /// Result of `project(now:until:)`.
    public struct Projection: Sendable {
        /// What happened between the snapshot and `now` (the snapshot is stale: the server recomputes the colony only
        /// when it is viewed in the client). An empty window if `now` is not later than the snapshot.
        public let elapsed: Forecast
        /// What happens between `now` and the horizon.
        public let upcoming: Forecast
        /// The colony at `now`: what the player would see opening it now.
        public let current: Colony
        /// The colony at the horizon.
        public let final: Colony
    }

    /// Catches the colony up to `now` and forecasts to `horizon` in one call: two consecutive
    /// `ColonySimulation.run` calls, so the windows do not overlap.
    public func project(now: Date, until horizon: Date,
                        options: ColonySimulation.Options = .init()) -> Projection {
        var simulation = ColonySimulation(self)
        let elapsed = simulation.run(until: max(now, snapshotTime), options: options)
        let current = simulation.colony
        let upcoming = simulation.run(until: horizon, options: options)
        return Projection(elapsed: elapsed, upcoming: upcoming, current: current, final: simulation.colony)
    }
}

// MARK: - Queries on totals

extension Forecast {

    /// The first event of the window satisfying the predicate.
    public func firstEvent(where predicate: (Event) -> Bool) -> Event? {
        events.first(where: predicate)
    }

    /// When the storage first refused to accept cargo in this window.
    public func storageFull(_ pin: Colony.PinIndex) -> Date? {
        firstEvent { if case .storageFull(pin, _) = $0 { true } else { false } }?.date
    }

    /// Since when the processor has been idle at the end of the window (`nil` if it is running at the end or did not
    /// stop in the window). If it stopped and restarted, the last idle period is used.
    public func idleSince(_ pin: Colony.PinIndex) -> Date? {
        var since: Date?
        for event in events {
            switch event {
            case .processorIdle(pin, let date): since = date
            case .processorResumed(pin, _): since = nil
            default: break
            }
        }
        return since
    }

    /// When the ECU program ended within this window.
    public func extractorFinished(_ pin: Colony.PinIndex) -> Date? {
        firstEvent { if case .extractorFinished(pin, _) = $0 { true } else { false } }?.date
    }

    /// Pin contents at `date` according to the timeline (requires `Options.timeline`): the last entry not later than
    /// `date`; `nil` if there is none.
    public func contents(of pin: Colony.PinIndex, at date: Date) -> Inventory? {
        timeline.last { $0.pin == pin && $0.date <= date }?.contents
    }
}
