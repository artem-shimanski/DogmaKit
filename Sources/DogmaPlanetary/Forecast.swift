//
//  Forecast.swift
//  DogmaPlanetary
//
//  Created by Artem Shimanski on 14.10.2026.
//

import Foundation

/// Result of one `ColonySimulation.run(until:)`: the window `(from, to]`.
///
/// Two consecutive runs give two independent windows that join without double counting (an event exactly at `to`
/// belongs to the first window). The first window includes the snapshot moment itself, when processors pick up inputs and start.
public struct Forecast: Sendable {

    /// Counters of one pin over the window.
    public struct PinStats: Hashable, Sendable {
        /// Completed cycles (ECUs and processors).
        public var cycles = 0
        /// Gross output of completed cycles, including what then had nowhere to go.
        public var produced = Inventory()
        /// Output no route accepted is lost (as in the game).
        public var wasted = Inventory()
        /// Inputs consumed when cycles started (processors).
        public var consumed = Inventory()
        /// Received through routes.
        public var received = Inventory()
        /// Sent out through routes.
        public var sent = Inventory()
        /// Seconds of the window the processor was working. Its share of the window length is the utilization
        /// (`utilization(of:)`).
        public var busyTime: TimeInterval = 0

        public init() {}
    }

    public enum Event: Hashable, Sendable {
        /// The processor stalled: the cycle ended (or none was running at snapshot time) and inputs are insufficient for a new one.
        case processorIdle(Colony.PinIndex, at: Date)
        /// An idle processor started again.
        case processorResumed(Colony.PinIndex, at: Date)
        /// The ECU program finished its last cycle.
        case extractorFinished(Colony.PinIndex, at: Date)
        /// Storage refused to accept a load entirely for the first time (after having accepted; not reported again
        /// until it accepts everything once more).
        case storageFull(Colony.PinIndex, at: Date)
        /// A source lost output for the first time: routes did not accept it entirely.
        case outputWasted(Colony.PinIndex, typeID: TypeID, at: Date)

        public var date: Date {
            switch self {
            case .processorIdle(_, let at), .processorResumed(_, let at), .extractorFinished(_, let at),
                 .storageFull(_, let at), .outputWasted(_, _, let at):
                at
            }
        }
    }

    /// Pin contents after a change (only with `Options.timeline`).
    public struct TimelineEntry: Hashable, Sendable {
        public var date: Date
        public var pin: Colony.PinIndex
        public var contents: Inventory
    }

    public let from: Date
    public let to: Date
    /// Indexed by pin (`Colony.PinIndex.rawValue`).
    public internal(set) var pins: [PinStats]
    public internal(set) var events: [Event] = []
    /// Empty if the timeline is not enabled.
    public internal(set) var timeline: [TimelineEntry] = []
    /// The run hit `Options.maxEvents` and stopped before `to`.
    public internal(set) var isTruncated = false

    init(from: Date, to: Date, pinCount: Int) {
        self.from = from
        self.to = to
        self.pins = Array(repeating: PinStats(), count: pinCount)
    }

    public subscript(_ pin: Colony.PinIndex) -> PinStats {
        pins[Int(pin.rawValue)]
    }

    public var duration: TimeInterval {
        max(0, to.timeIntervalSince(from))
    }

    /// Fraction of the window the processor was working (0...1).
    public func utilization(of pin: Colony.PinIndex) -> Double {
        duration > 0 ? self[pin].busyTime / duration : 0
    }

    // MARK: - Colony summary

    /// Gross output of all ECUs and processors.
    public var produced: Inventory { sum(\.produced) }
    public var wasted: Inventory { sum(\.wasted) }
    public var consumed: Inventory { sum(\.consumed) }

    /// ECU and processor output minus what was lost and consumed inside the colony: how much the colony has
    /// accumulated (in storage or processor buffers). Negative values (stock depleting faster than it is
    /// replenished) are not stored in `Inventory`; use `balance(of:)` for them.
    public var net: Inventory {
        var result = Inventory()
        for typeID in Set(produced.map(\.typeID)).union(consumed.map(\.typeID)) {
            result[typeID] = balance(of: typeID)
        }
        return result
    }

    /// Produced - lost - consumed.
    public func balance(of typeID: TypeID) -> Int {
        produced[typeID] - wasted[typeID] - consumed[typeID]
    }

    private func sum(_ keyPath: KeyPath<PinStats, Inventory>) -> Inventory {
        var result = Inventory()
        for stats in pins {
            for item in stats[keyPath: keyPath] {
                result[item.typeID] += item.quantity
            }
        }
        return result
    }
}
