//
//  Options.swift
//  DogmaKit
//

/// How clip reloads are accounted for in derived stats: cycle time and everything computed
/// from it (DPS, repair rates, mining, capacitor use).
public enum ReloadPolicy: Sendable, Hashable, CaseIterable {
    /// Reloads are spread over the cycle for every module with a clip: the sustained average.
    case factored

    /// Reloads are counted only for modules with `Entity.Module.Flags.forceReload`
    /// (cap boosters, nanite paste consumers). The default.
    case forcedOnly

    /// Reloads are ignored entirely: peak rates for the duration of a clip (burst tank).
    /// Not allowed for the capacitor simulation, see `forCapacitor`.
    case ignored

    /// Whether to count the clip of a module; `forced` is its `forceReload` flag.
    @inlinable
    public func countsClip(forced: Bool) -> Bool {
        switch self {
        case .factored: true
        case .forcedOnly: forced
        case .ignored: false
        }
    }

    /// A policy safe for the capacitor: `.ignored` would make a cap booster an infinite
    /// charge source.
    @inlinable
    public var forCapacitor: ReloadPolicy {
        self == .ignored ? .forcedOnly : self
    }
}

extension FitStats {
    /// Read-layer options. They affect only derived arithmetic in `FitStats`, never dogma
    /// attributes, so changing them does not require a recalculation. Set on entry to
    /// `DogmaEngine.read(reload:_:)` for the duration of one call.
    ///
    /// `ContextBuilder` and `AttributeCalculator` must not read these options.
    public struct Options: Sendable, Hashable {
        /// How to account for clip reloads.
        public var reload: ReloadPolicy

        /// How far spooling modules are spooled up, see `SpoolPolicy`.
        public var spool: SpoolPolicy

        public init(reload: ReloadPolicy = .forcedOnly, spool: SpoolPolicy = .none) {
            self.reload = reload
            self.spool = spool
        }
    }
}

extension DogmaEngine.Session {
    /// Reload policy of the current read.
    @usableFromInline
    var reload: ReloadPolicy { statsOptions.reload }

    /// Spool policy of the current read.
    @usableFromInline
    var spool: SpoolPolicy { statsOptions.spool }
}
