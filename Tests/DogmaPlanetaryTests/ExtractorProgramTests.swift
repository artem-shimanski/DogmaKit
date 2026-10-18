//
//  ExtractorProgramTests.swift
//  DogmaKit
//
//  Extractor yield formula against CCP's reference values; results must match exactly, cycle by cycle.
//

import Foundation
import Testing
@testable import DogmaPlanetary

@Suite("Extractor program")
struct ExtractorProgramTests {

    static let install = Date(timeIntervalSince1970: 1_790_000_000)

    func program(quantity: Int, cycleTime: Int, cycles: Int, tail: Int = 0) -> ExtractorProgram {
        ExtractorProgram(installTime: Self.install,
                         expiryTime: Self.install.addingTimeInterval(TimeInterval(cycles * cycleTime + tail)),
                         cycleTime: cycleTime, quantityPerCycle: quantity,
                         decayFactor: 0.012, noiseFactor: 0.8)
    }

    // MARK: - Reference

    /// CCP's reference example: 1d 23h 30m, 30 minute cycle, quantity 6965.
    @Test("CCP example: 6965 per 30 minutes, 95 cycles")
    func ccpExample() {
        let p = program(quantity: 6965, cycleTime: 1800, cycles: 95)
        #expect(p.duration == 171_000)
        #expect(p.cycleCount == 95)
        #expect(p.yields == Self.reference6965)
        #expect(p.totalYield == 789_314)
        #expect(abs(p.rawYield(cycle: 0) - 24261.65942574787) < 1e-9)
    }

    @Test("Long cycle: 12345 per 4 hours, 84 cycles")
    func longCycle() {
        let p = program(quantity: 12345, cycleTime: 14400, cycles: 84)
        #expect(p.totalYield == 3_331_518)
        #expect(Array(p.yields.prefix(8)) == [180218, 212923, 143080, 141895, 105965, 122566, 87864, 103095])
        #expect(Array(p.yields.suffix(3)) == [11864, 17942, 12224])
    }

    @Test("Small quantity: 250 per 2 hours, 48 cycles")
    func smallQuantity() {
        let p = program(quantity: 250, cycleTime: 7200, cycles: 48)
        #expect(p.totalYield == 40_737)
        #expect(Array(p.yields.prefix(6)) == [1908, 2403, 1612, 1787, 2327, 1308])
    }

    @Test("Constants come from the catalog")
    func constantsFromCatalog() throws {
        let catalog = try PlanetaryCatalog.bundled()
        let p = ExtractorProgram(installTime: Self.install,
                                 expiryTime: Self.install.addingTimeInterval(171_000),
                                 cycleTime: 1800, quantityPerCycle: 6965,
                                 constants: catalog.extractor)
        #expect(p.yields == Self.reference6965)
    }

    // MARK: - Boundaries

    @Test("A partial program tail yields no cycle")
    func partialTail() {
        let p = program(quantity: 6965, cycleTime: 1800, cycles: 95, tail: 1799)
        #expect(p.cycleCount == 95)
        #expect(p.yield(cycle: 95) == 0)
    }

    @Test("Yield is zero outside the program and for degenerate input")
    func degenerate() {
        let p = program(quantity: 6965, cycleTime: 1800, cycles: 95)
        #expect(p.yield(cycle: -1) == 0)
        #expect(p.yield(cycle: 95) == 0)
        #expect(program(quantity: 6965, cycleTime: 0, cycles: 10).cycleCount == 0)
        #expect(program(quantity: 0, cycleTime: 1800, cycles: 10).totalYield == 0)
        let reversed = ExtractorProgram(installTime: Self.install, expiryTime: Self.install.addingTimeInterval(-3600),
                                        cycleTime: 1800, quantityPerCycle: 100, decayFactor: 0.012, noiseFactor: 0.8)
        #expect(reversed.cycleCount == 0)
    }

    // MARK: - Timing

    @Test("Cycle start, end and cycle at a given moment")
    func timing() {
        let p = program(quantity: 6965, cycleTime: 1800, cycles: 95)
        #expect(p.cycleStart(0) == Self.install)
        #expect(p.cycleEnd(0) == Self.install.addingTimeInterval(1800))
        #expect(p.cycle(at: Self.install) == 0)
        #expect(p.cycle(at: Self.install.addingTimeInterval(1799)) == 0)
        #expect(p.cycle(at: Self.install.addingTimeInterval(1800)) == 1)
        #expect(p.cycle(at: Self.install.addingTimeInterval(-1)) == nil)
        #expect(p.cycle(at: p.expiryTime) == nil)
        #expect(p.cycle(at: p.expiryTime.addingTimeInterval(-1)) == 94)
    }

    @Test("Window (from, to] counts the cycles completed in it")
    func window() {
        let p = program(quantity: 6965, cycleTime: 1800, cycles: 95)
        let at = { (seconds: Int) in Self.install.addingTimeInterval(TimeInterval(seconds)) }
        // Cycle 0 ends at exactly 1800: it is in (0, 1800], not in (1800, 3600].
        #expect(p.completedCycles(from: at(0), to: at(1800)) == 0..<1)
        #expect(p.completedCycles(from: at(1800), to: at(3600)) == 1..<2)
        #expect(p.completedCycles(from: at(1799), to: at(1800)) == 0..<1)
        #expect(p.completedCycles(from: at(1), to: at(1799)).isEmpty)
        // A window wider than the program covers all of it.
        #expect(p.completedCycles(from: at(-100_000), to: at(10_000_000)) == 0..<95)
        #expect(p.yield(from: at(-1), to: p.expiryTime) == p.totalYield)
        // Adjacent windows do not double count.
        let mid = at(50 * 1800 + 900)
        #expect(p.yield(from: at(0), to: mid) + p.yield(from: mid, to: p.expiryTime) == p.totalYield)
        #expect(p.completedCycles(from: at(3600), to: at(1800)).isEmpty)
    }

    static let reference6965: [Int] = [
        24261, 20481, 16053, 13903, 14488, 15656, 14854, 11805, 11569, 11343, 11126, 11374, 13299, 12531,
        10333, 10153, 9978, 10246, 11037, 9489, 9336, 9188, 9045, 8906, 8772, 8641, 8514, 8391, 8271, 8659,
        11474, 12727, 11691, 9462, 7932, 8102, 9271, 9811, 8750, 7150, 7063, 6978, 7904, 9790, 10134, 8913,
        7412, 6969, 7722, 8516, 8004, 6229, 6163, 6098, 6035, 5973, 5912, 5852, 5794, 5737, 5681, 5897,
        7307, 7216, 5872, 5416, 5365, 5316, 5888, 5814, 5174, 5128, 5083, 5039, 6817, 7845, 7576, 6616,
        6062, 6458, 7289, 7481, 6421, 4637, 4600, 4564, 4528, 4493, 4459, 4425, 4391, 4358, 4326, 5113, 5389,
    ]
}
