//
//  SensorStrength.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 27.07.2026.
//

import simd

/// Sensor type. A ship has exactly one non-zero type; an ECM module has a strength for
/// each of the four.
public enum SensorType: UInt8, BitwiseCopyable, Sendable, CaseIterable {
    case radar
    case ladar
    case magnetometric
    case gravimetric
}

extension SensorType {
    /// Ship sensor strength attribute (jam resistance).
    @inlinable
    public var strengthAttributeID: AttributeID {
        switch self {
        case .radar: .scanRadarStrength
        case .ladar: .scanLadarStrength
        case .magnetometric: .scanMagnetometricStrength
        case .gravimetric: .scanGravimetricStrength
        }
    }

    /// ECM module jam strength attribute for this sensor type. Despite the `Bonus` suffix,
    /// it is an absolute value on jammers.
    @inlinable
    public var jamStrengthAttributeID: AttributeID {
        switch self {
        case .radar: .scanRadarStrengthBonus
        case .ladar: .scanLadarStrengthBonus
        case .magnetometric: .scanMagnetometricStrengthBonus
        case .gravimetric: .scanGravimetricStrengthBonus
        }
    }
}

/// Sensor strength for the four types, in `SensorType` order. Used both for ships
/// (ECM resistance) and jammers (jam strength).
@frozen
public struct SensorStrength: SIMD, Sendable {
    public typealias Storage = SIMD4<Double>
    public typealias MaskStorage = Storage.MaskStorage
    public typealias ArrayLiteralElement = Storage.ArrayLiteralElement
    public typealias Scalar = Storage.Scalar

    public var storage: Storage

    @inlinable
    public var scalarCount: Int {
        storage.scalarCount
    }

    @inlinable
    public init() {
        storage = Storage()
    }

    @inlinable
    public init(storage: Storage) {
        self.storage = storage
    }

    @inlinable
    public init(radar: Scalar, ladar: Scalar, magnetometric: Scalar, gravimetric: Scalar) {
        storage = Storage(radar, ladar, magnetometric, gravimetric)
    }

    @inlinable
    public subscript(index: Int) -> Storage.Scalar {
        get { storage[index] }
        set { storage[index] = newValue }
    }
}

extension SensorStrength {
    @inlinable
    public var radar: Scalar {
        get { storage.x }
        set { storage.x = newValue }
    }

    @inlinable
    public var ladar: Scalar {
        get { storage.y }
        set { storage.y = newValue }
    }

    @inlinable
    public var magnetometric: Scalar {
        get { storage.z }
        set { storage.z = newValue }
    }

    @inlinable
    public var gravimetric: Scalar {
        get { storage.w }
        set { storage.w = newValue }
    }

    @inlinable
    public subscript(type: SensorType) -> Scalar {
        get { storage[Int(type.rawValue)] }
        set { storage[Int(type.rawValue)] = newValue }
    }
}

extension SensorStrength {
    /// The dominant sensor: a ship's only non-zero type, or the first of equals for a
    /// multispectral jammer. `nil` if all are zero.
    @inlinable
    public var dominant: (type: SensorType, strength: Scalar)? {
        var best = SensorType.radar
        var value = storage.x
        for type in SensorType.allCases.dropFirst() where self[type] > value {
            value = self[type]
            best = type
        }
        guard value > 0 else { return nil }
        return (best, value)
    }

    /// Jam resistance: the jam strength at which the jam chance reaches 100%.
    @inlinable
    public var ecmResistance: Scalar {
        storage.max()
    }
}
