//
//  Targeting.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 27.07.2026.
//

#if os(WASI)
import FoundationEssentials
// Math functions come from libc; elsewhere Foundation re-exports it.
import WASILibc
#else
import Foundation
#endif

/// Targeting characteristics.
@frozen
public struct Targeting: Sendable, Equatable {
    /// Maximum targeting range, m.
    public var maxTargetRange: Double
    /// Scan resolution, mm. Higher locks faster.
    public var scanResolution: Double
    /// Maximum number of locked targets.
    public var maxLockedTargets: Int
    /// Sensor strength by type (also the ECM resistance).
    public var sensorStrength: SensorStrength
    /// Legacy lock time attribute (`scanSpeed`, ms); the fallback for types without
    /// `scanResolution` (mostly NPCs).
    public var scanSpeed: Double

    @inlinable
    public init(maxTargetRange: Double,
                scanResolution: Double,
                maxLockedTargets: Int,
                sensorStrength: SensorStrength,
                scanSpeed: Double) {
        self.maxTargetRange = maxTargetRange
        self.scanResolution = scanResolution
        self.maxLockedTargets = maxLockedTargets
        self.sensorStrength = sensorStrength
        self.scanSpeed = scanSpeed
    }
}

extension Targeting {
    /// Lock time cap, seconds (30 minutes).
    @usableFromInline
    static let maxLockTime = 30.0 * 60.0

    /// Time to lock a target with the given signature radius, seconds:
    /// `40000 / (scanResolution · asinh²(signatureRadius))`, capped at 30 minutes.
    /// Returns `scanSpeed / 1000` without `scanResolution`, `0` for a zero signature.
    @inlinable
    public func lockTime(signatureRadius: Double) -> Double {
        guard scanResolution > 0 else { return scanSpeed / 1000 }
        guard signatureRadius > 0 else { return 0 }
        let x = asinh(signatureRadius)
        guard x > 0 else { return 0 }
        return min(40_000 / scanResolution / (x * x), Self.maxLockTime)
    }

    /// ECM resistance: the jam strength at which a jam is guaranteed.
    @inlinable
    public var ecmResistance: Double {
        sensorStrength.ecmResistance
    }

    /// The hull's sensor type (by dominant strength). `nil` if there are no sensors.
    @inlinable
    public var sensorType: SensorType? {
        sensorStrength.dominant?.type
    }

    /// Chance that one activation of a jammer with `jamStrength` (for this hull's sensor
    /// type) breaks the lock. No range adjustment; see `ECM.jamProbability(against:at:)`.
    @inlinable
    public func jamProbability(against jamStrength: Double) -> Double {
        let resistance = ecmResistance
        guard resistance > 0 else { return jamStrength > 0 ? 1 : 0 }
        return min(1, max(0, jamStrength / resistance))
    }
}
