import Foundation
@_exported import DogmaModels
import BitField
import FlatBin


@usableFromInline
struct SDE: Sendable {
    @usableFromInline let decoder: FlatDecoder
    
    init(data: Data) {
        self.decoder = FlatDecoder(data: data)
    }
    
    @inlinable
    subscript (_ typeID: TypeID) -> DogmaSDE.TypeInfo.View? {
        @_lifetime(borrow self) get {
            let decoder = decoder
            let type = decoder.decode(DogmaSDE.self).types[typeID]
            return _overrideLifetime(type, borrowing: self)
        }
    }

    @inlinable
    subscript (_ attributeID: AttributeID) -> DogmaSDE.AttributeInfo.View? {
        @_lifetime(borrow self) get {
            let decoder = decoder
            let attribute = decoder.decode(DogmaSDE.self).attributes[attributeID]
            return _overrideLifetime(attribute, borrowing: self)
        }
    }

    @inlinable
    subscript (_ warfareBuffID: WarfareBuffID) -> DogmaSDE.WarfareBuff.View? {
        @_lifetime(borrow self) get {
            let decoder = decoder
            let buff = decoder.decode(DogmaSDE.self).warfareBuffs[warfareBuffID]
            return _overrideLifetime(buff, borrowing: self)
        }
    }

    /// Mutaplasmid by type ID. A method rather than a subscript, since the key type is the
    /// same `TypeID` as for the type table.
    @inlinable
    @_lifetime(borrow self)
    func mutaplasmid(_ typeID: TypeID) -> DogmaSDE.Mutaplasmid.View? {
        let decoder = decoder
        let mutaplasmid = decoder.decode(DogmaSDE.self).mutaplasmids[typeID]
        return _overrideLifetime(mutaplasmid, borrowing: self)
    }

    @inlinable
    subscript<T: FlatCodable> (_ reference: FlatReference<T>) -> T.View {
        @_lifetime(borrow self) get {
            let decoder = decoder
            let value = decoder.decode(by: reference)
            return _overrideLifetime(value, borrowing: self)
        }
    }

    @inlinable
    var skills: [TypeID].View {
        @_lifetime(borrow self) get {
            let decoder = decoder
            let skills = decoder.decode(DogmaSDE.self).skills
            return _overrideLifetime(skills, borrowing: self)
        }
    }
}

public actor DogmaEngine {
    
    @usableFromInline
    struct Session {
        @usableFromInline internal var entities = EntityStore()
        @usableFromInline internal var context = CalculatorContext()
        @usableFromInline internal let sde = try! SDE(data: Data(contentsOf: Bundle.module.url(forResource: "sde", withExtension: "bin")!, options: [.mappedIfSafe]))
        @usableFromInline internal var isDirty = true
        /// Read-layer options (see `FitStats.Options`); not calculation inputs, so changing
        /// them does not invalidate the context.
        @usableFromInline internal var statsOptions = FitStats.Options()
        @usableFromInline internal var skillIDMap: [TypeID: UInt16]?
        @usableFromInline mutating func invalidate() { isDirty = true }
    }
    
    @usableFromInline internal var session = Session()

    private var contextBuilder = ContextBuilder()

    /// Guard against fixed-point oscillation; on real SDE data it converges in 1–2 passes.
    private static let maxIterations = 5

    public init() {
    }

    @discardableResult
    public func edit<T: Sendable, E: Error & Sendable>(_ block: @Sendable (borrowing Fit) throws(E) -> T) throws(E) -> T {
        session.invalidate()
        return try withUnsafeMutablePointer(to: &session) { (ptr) throws (E) in
            try block(Fit(session: ptr))
        }
    }

    /// Reads stats. `reload` is the reload policy for the whole call, seen consistently by
    /// all derived stats (`cycleTime`, `dps`, `tank`, `capacitor`, `miningYield`). `spool`
    /// sets how far spooling modules are spooled up. Neither affects dogma attributes or
    /// triggers a recalculation.
    public func evaluate<T: Sendable, E: Error & Sendable>(reload: ReloadPolicy = .forcedOnly,
                                                      spool: SpoolPolicy = .none,
                                                      _ block: @Sendable (borrowing FitStats) throws(E) -> T) throws(E) -> T {
        recalculateIfNeeded()
        session.statsOptions = FitStats.Options(reload: reload, spool: spool)
        return try withUnsafeMutablePointer(to: &session) { (ptr) throws (E) in
            try block(FitStats(session: ptr))
        }
    }

    private func recalculateIfNeeded() {
        guard session.isDirty else { return }
        session.context.cleanUp()
        contextBuilder.build(in: &session)
        AttributeCalculator.calculate(&session.context, using: session.sde)
        var iteration = 1
        while contextBuilder.resolveStates(in: &session) && iteration < Self.maxIterations {
            contextBuilder.reloadBaseAttributes(in: &session)
            AttributeCalculator.calculate(&session.context, using: session.sde)
            iteration += 1
        }
        session.isDirty = false
    }
}

