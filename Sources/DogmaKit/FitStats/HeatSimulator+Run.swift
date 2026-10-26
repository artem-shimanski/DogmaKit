//
//  HeatSimulator+Run.swift
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

extension HeatSimulator {

    private struct RackState {
        var capacity: Double
        var attenuation: Double
        var dissipationRate: Double
        /// Current heat generation `g`; drops as sources burn out.
        var generation: Double
        var heat: Double
        /// Index of the rack's first slot in the flat socket array.
        var first: Int
        var count: Int
        /// Precomputed `attenuation^d`.
        var powers: [Double]
        var segments: [Result.HeatSegment]
    }

    private struct SocketState {
        var id: ModuleID?
        var rack: Int
        var socket: Int
        var hitPoints: Double
        var isOnline: Bool
        var isAlive: Bool
        var mean: Double = 0
        var variance: Double = 0
        var burnoutTime: Double? = nil
        var burnoutDeviation: Double = 0
    }

    private struct NodeState {
        var rack: Int
        var socket: Int
        /// Index of the source's own slot in the flat array; used to stop it when it burns out.
        var owner: Int
        var cycleTime: Double
        var clipSize: Int
        var reloadTime: Double
        var absorbtionRate: Double
        var damage: Double
        var period: Double
        var tNext: Double
        var shot: Int = 0
        var isAlive: Bool = true
    }

    public func run(horizon: Double = HeatSimulator.maxSimulationTime) -> Result {

        // MARK: Setup

        var rackStates: [RackState] = []
        var sockets: [SocketState] = []
        var nodes: [NodeState] = []
        var totalSlots = rigSlots
        var onlineCount = 0

        rackStates.reserveCapacity(racks.count)
        for (rackIndex, rack) in racks.enumerated() {
            let first = sockets.count
            let count = rack.sockets.count
            totalSlots += count

            for (index, socket) in rack.sockets.enumerated() {
                let occupied = socket.isOccupied
                if occupied && socket.isOnline { onlineCount += 1 }
                sockets.append(SocketState(id: socket.id,
                                           rack: rackIndex,
                                           socket: index,
                                           hitPoints: socket.hitPoints,
                                           isOnline: occupied && socket.isOnline,
                                           isAlive: occupied))
            }

            var powers = [Double](repeating: 1, count: Swift.max(count, 1))
            for i in 1..<powers.count { powers[i] = powers[i - 1] * rack.attenuation }

            var generation = 0.0
            for node in rack.nodes {
                // Skip zero cycles (would never advance), sockets outside the rack
                // (overfitted) and empty slots.
                guard node.cycleTime > 0,
                      node.socket >= 0, node.socket < count,
                      sockets[first + node.socket].isAlive
                else { continue }
                generation += node.absorbtionRate
                let owner = first + node.socket
                nodes.append(NodeState(rack: rackIndex,
                                       socket: node.socket,
                                       owner: owner,
                                       cycleTime: node.cycleTime,
                                       clipSize: node.clipSize,
                                       reloadTime: node.reloadTime,
                                       absorbtionRate: node.absorbtionRate,
                                       damage: node.damage,
                                       period: node.period,
                                       // Damage applies at the end of a cycle.
                                       tNext: node.cycleTime))
            }
            generation *= heatGenerationMultiplier

            rackStates.append(RackState(capacity: rack.capacity,
                                        attenuation: rack.attenuation,
                                        dissipationRate: rack.dissipationRate,
                                        generation: generation,
                                        heat: 0,
                                        first: first,
                                        count: count,
                                        powers: powers,
                                        segments: [Result.HeatSegment(start: 0,
                                                                      initialHeat: 0,
                                                                      generation: generation,
                                                                      capacity: rack.capacity,
                                                                      dissipationRate: rack.dissipationRate)]))
        }

        let slotFactor = totalSlots > 0 ? Double(onlineCount) / Double(totalSlots) : 0

        guard totalSlots > 0, !nodes.isEmpty else {
            return result(sockets: sockets, rackStates: rackStates,
                          slotFactor: slotFactor, duration: 0, isTruncated: false)
        }

        // MARK: Event loop

        var t = 0.0
        var iterations = 0
        var isTruncated = false
            // Modules that die in one event are collected first so that damage rates are
            // computed over the live set, independent of slot order.
        var dying: [(index: Int, rate: Double)] = []
        dying.reserveCapacity(8)

        while true {
            iterations += 1
            if iterations > Self.maxIterations {
                isTruncated = true
                break
            }

            // Next event; ties go to the lower index for determinism.
            var next = Double.infinity
            var idx = -1
            for i in nodes.indices where nodes[i].isAlive && nodes[i].tNext < next {
                next = nodes[i].tNext
                idx = i
            }
            if idx < 0 { break }                      // no sources left
            if next > horizon {
                isTruncated = true
                break
            }

            // Advance heat of all racks to the event time.
            let dt = next - t
            if dt > 0 {
                for r in rackStates.indices {
                    if rackStates[r].generation > 0 {
                        let c = rackStates[r].capacity
                        rackStates[r].heat = c + (rackStates[r].heat - c) * exp(-rackStates[r].generation * dt)
                    }
                    else if rackStates[r].dissipationRate > 0 {
                        rackStates[r].heat *= exp(-rackStates[r].dissipationRate * dt)
                    }
                }
            }
            t = next

            let r = nodes[idx].rack
            let source = nodes[idx].socket
            let damage = nodes[idx].damage
            let heat = rackStates[r].heat
            let fs = Double(onlineCount) / Double(totalSlots)

            // Damage every live module in the rack, the source included (distance 0).
            if heat > 0, damage > 0, fs > 0 {
                let first = rackStates[r].first
                for s in 0..<rackStates[r].count where sockets[first + s].isAlive {
                    let probability = Swift.min(1, Swift.max(0, heat * fs * rackStates[r].powers[abs(s - source)]))
                    guard probability > 0 else { continue }
                    sockets[first + s].mean += probability * damage
                    sockets[first + s].variance += probability * (1 - probability) * damage * damage
                }
            }

            // Modules that did not survive the event.
            dying.removeAll(keepingCapacity: true)
            let first = rackStates[r].first
            for s in 0..<rackStates[r].count {
                let i = first + s
                guard sockets[i].isAlive, sockets[i].mean >= sockets[i].hitPoints else { continue }
                // Instantaneous damage rate, to convert damage deviation into time deviation.
                // The average rate would underestimate it, since heat keeps rising.
                var rate = 0.0
                for n in nodes.indices where nodes[n].isAlive && nodes[n].rack == r && nodes[n].period > 0 {
                    let probability = Swift.min(1, Swift.max(0, heat * fs * rackStates[r].powers[abs(s - nodes[n].socket)]))
                    rate += probability * nodes[n].damage / nodes[n].period
                }
                dying.append((index: i, rate: rate))
            }

            var generationChanged = false
            for (i, rate) in dying {
                sockets[i].isAlive = false
                sockets[i].burnoutTime = t
                sockets[i].burnoutDeviation = rate > 0 ? sockets[i].variance.squareRoot() / rate : 0
                if sockets[i].isOnline { onlineCount -= 1 }

                // A burnt module goes offline: it stops heating, dealing damage and counting in Fs.
                for n in nodes.indices where nodes[n].isAlive && nodes[n].owner == i {
                    nodes[n].isAlive = false
                    rackStates[r].generation -= heatGenerationMultiplier * nodes[n].absorbtionRate
                    generationChanged = true
                }
            }
            if generationChanged {
                rackStates[r].generation = Swift.max(0, rackStates[r].generation)
                rackStates[r].segments.append(Result.HeatSegment(start: t,
                                                                 initialHeat: rackStates[r].heat,
                                                                 generation: rackStates[r].generation,
                                                                 capacity: rackStates[r].capacity,
                                                                 dissipationRate: rackStates[r].dissipationRate))
            }

            // Schedule the source's next activation.
            guard nodes[idx].isAlive else { continue }
            nodes[idx].tNext += nodes[idx].cycleTime
            nodes[idx].shot += 1
            if nodes[idx].clipSize > 0 && nodes[idx].shot % nodes[idx].clipSize == 0 {
                nodes[idx].shot = 0
                nodes[idx].tNext += nodes[idx].reloadTime
            }
        }

        return result(sockets: sockets, rackStates: rackStates,
                      slotFactor: slotFactor, duration: t, isTruncated: isTruncated)
    }

    private func result(sockets: [SocketState],
                        rackStates: [RackState],
                        slotFactor: Double,
                        duration: Double,
                        isTruncated: Bool) -> Result {
        var modules: [Result.Module] = []
        modules.reserveCapacity(sockets.count)
        for state in sockets where state.hitPoints > 0 {
            modules.append(Result.Module(id: state.id,
                                         slot: racks[state.rack].slot,
                                         socket: state.socket,
                                         hitPoints: state.hitPoints,
                                         damageTaken: state.mean,
                                         damageDeviation: state.variance.squareRoot(),
                                         burnoutTime: state.burnoutTime,
                                         burnoutDeviation: state.burnoutDeviation))
        }

        var resultRacks: [Result.Rack] = []
        resultRacks.reserveCapacity(rackStates.count)
        for (index, state) in rackStates.enumerated() {
            resultRacks.append(Result.Rack(slot: racks[index].slot,
                                           capacity: state.capacity,
                                           segments: state.segments))
        }

        return Result(modules: modules,
                      racks: resultRacks,
                      slotFactor: slotFactor,
                      duration: duration,
                      isTruncated: isTruncated)
    }
}
