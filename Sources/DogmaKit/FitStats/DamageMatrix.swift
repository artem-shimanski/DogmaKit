//
//  DamageMatrix.swift
//  DogmaKit
//

/// One damage vector (EM, thermal, kinetic, explosive) per hit point layer: the storage of
/// `Resonance` and `Resistances`. Built on the standard library `SIMD4<Double>`, so it is the
/// same type on every platform.
@frozen
public struct DamageMatrix: Sendable, Hashable {
    public var shield: SIMD4<Double>
    public var armor: SIMD4<Double>
    public var hull: SIMD4<Double>

    @inlinable
    public init(_ shield: SIMD4<Double>, _ armor: SIMD4<Double>, _ hull: SIMD4<Double>) {
        self.shield = shield
        self.armor = armor
        self.hull = hull
    }

    /// All zeros.
    @inlinable
    public init() {
        self.init(.zero, .zero, .zero)
    }

    @inlinable
    public init(repeating scalar: Double) {
        let column = SIMD4<Double>(repeating: scalar)
        self.init(column, column, column)
    }

    /// Layer by index: 0 shield, 1 armor, 2 hull.
    @inlinable
    public subscript(layer: Int) -> SIMD4<Double> {
        get {
            switch layer {
            case 0: shield
            case 1: armor
            case 2: hull
            default: preconditionFailure("DamageMatrix layer \(layer) is out of range 0...2")
            }
        }
        set {
            switch layer {
            case 0: shield = newValue
            case 1: armor = newValue
            case 2: hull = newValue
            default: preconditionFailure("DamageMatrix layer \(layer) is out of range 0...2")
            }
        }
    }

    /// The share of `damage` each layer takes: `damage · layer` for shield, armor and hull.
    @inlinable
    public func applied(to damage: SIMD4<Double>) -> SIMD3<Double> {
        SIMD3((damage * shield).sum(), (damage * armor).sum(), (damage * hull).sum())
    }

    @inlinable
    public static func - (lhs: Self, rhs: Self) -> Self {
        Self(lhs.shield - rhs.shield, lhs.armor - rhs.armor, lhs.hull - rhs.hull)
    }
}
