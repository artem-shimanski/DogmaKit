//
//  HeatSimulator.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 01.08.2026.
//

#if os(WASI)
import FoundationEssentials
// Math functions come from libc; elsewhere Foundation re-exports it.
import WASILibc
#else
import Foundation
#endif

/// Overheat simulator: how long modules survive while overloaded.
///
/// **Heating.** A rack (hi / med / low) heats as `dH/dt = g·(C − H)`, where
/// `C = heatCapacity/100` and `g = heatGenerationMultiplier · Σ heatAbsorbtionRateModifier`
/// of the rack's overloaded modules. `H` is advanced incrementally,
/// `H ← C + (H − C)·exp(−g·Δt)`, which survives changes of `g` (a module burns out).
/// A rack with no overloaded modules cools down: `H ← H·exp(−heatDissipationRate·Δt)`.
///
/// **Damage.** At the end of each cycle an overloaded module deals `heatDamage` to every
/// module in its rack, itself included, with probability `P = H · Fs · heatAttenuation^|Δsocket|`.
/// `Fs` is the ship-wide slot fill ratio: `(online hi+med+low modules) / (hi+med+low+rig slots)`.
/// Offline modules are not counted in `Fs` but still take damage.
///
/// **Randomness.** Instead of rolling, the expected damage `mean += P·damage` and its variance
/// `var += P·(1−P)·damage²` are accumulated, giving the typical burnout time and the spread
/// around it (`Result.Module.burnoutTime(probability:)`).
public struct HeatSimulator: Sendable, Equatable {

    /// An overloaded module: a source of heat and damage.
    public struct Node: Sendable, Equatable {
        /// Position of the source in the rack.
        public var socket: Int
        /// Time between activations within a clip, seconds.
        public var cycleTime: Double
        /// Activations before a reload. `0` means no reload.
        public var clipSize: Int
        /// Discrete reload gap after a clip, seconds.
        public var reloadTime: Double
        /// `heatAbsorbtionRateModifier`: the module's contribution to rack heating.
        public var absorbtionRate: Double
        /// `heatDamage`: damage per hit.
        public var damage: Double

        @inlinable
        public init(socket: Int,
                    cycleTime: Double,
                    clipSize: Int = 0,
                    reloadTime: Double = 0,
                    absorbtionRate: Double,
                    damage: Double) {
            self.socket = socket
            self.cycleTime = cycleTime
            self.clipSize = clipSize
            self.reloadTime = reloadTime
            self.absorbtionRate = absorbtionRate
            self.damage = damage
        }

        /// Average cycle duration including clip reloads, seconds.
        @inlinable
        public var period: Double {
            clipSize > 0 ? cycleTime + reloadTime / Double(clipSize) : cycleTime
        }
    }

    /// A rack slot, occupied or empty.
    public struct Socket: Sendable, Equatable {
        /// Module ID, so results can be mapped back to the fit.
        public var id: ModuleID?
        /// Module HP. `0` means the slot is empty.
        public var hitPoints: Double
        /// Whether the module counts toward `Fs` (online or higher).
        public var isOnline: Bool

        @inlinable
        public init(id: ModuleID? = nil, hitPoints: Double, isOnline: Bool) {
            self.id = id
            self.hitPoints = hitPoints
            self.isOnline = isOnline
        }

        /// An empty slot.
        public static let empty = Socket(hitPoints: 0, isOnline: false)

        @inlinable
        public var isOccupied: Bool { hitPoints > 0 }
    }

    /// A hi, med or low rack. Racks heat independently but share `Fs`.
    public struct Rack: Sendable, Equatable {
        public var slot: Entity.Module.Slot
        /// `heatCapacity{Hi|Med|Low} / 100`.
        public var capacity: Double
        /// `heatAttenuation{Hi|Med|Low}`.
        public var attenuation: Double
        /// `heatDissipationRate{Hi|Med|Low}`; applies only while the rack has no overloaded modules.
        public var dissipationRate: Double
        /// Rack slots in order; the length is the total slot count.
        public var sockets: [Socket]
        /// Overloaded modules of the rack.
        public var nodes: [Node]

        @inlinable
        public init(slot: Entity.Module.Slot,
                    capacity: Double,
                    attenuation: Double,
                    dissipationRate: Double,
                    sockets: [Socket],
                    nodes: [Node]) {
            self.slot = slot
            self.capacity = capacity
            self.attenuation = attenuation
            self.dissipationRate = dissipationRate
            self.sockets = sockets
            self.nodes = nodes
        }
    }

    /// The hull's `heatGenerationMultiplier`.
    public var heatGenerationMultiplier: Double
    /// The hi / med / low racks. Racks without slots can be omitted.
    public var racks: [Rack]
    /// Number of rig slots. Rigs do not heat or take damage but count in the `Fs` denominator.
    public var rigSlots: Int

    @inlinable
    public init(heatGenerationMultiplier: Double, racks: [Rack], rigSlots: Int = 0) {
        self.heatGenerationMultiplier = heatGenerationMultiplier
        self.racks = racks
        self.rigSlots = rigSlots
    }

    /// Default simulation horizon, seconds. Guards against data where modules never burn out.
    public static let maxSimulationTime: Double = 3600
    /// Safety limit on the number of events.
    public static let maxIterations = 1_000_000
}
