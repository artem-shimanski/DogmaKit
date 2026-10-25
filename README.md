# DogmaKit

The EVE Online fitting engine (Dogma) used by Neocom. Given ships, modules, charges, drones,
skills, implants, boosters and environment effects, it applies the game's attribute modifiers
and reports what the fit does: resources and slots, damage, tank, capacitor, heat, navigation,
targeting. A separate target simulates planetary production (PI) colonies.

## Scope

What the engine does:

* Builds the modifier graph from the SDE's effects and evaluates it, including stacking
  penalties, min/max clamps and warfare buffs (command bursts, environment effects), with
  module states resolved to a fixed point (`maxGroupActive`, `maxGroupOnline`,
  `activationBlocked`, disallow masks).
* Several pilots in one session (up to 7), so projected effects between ships — remote repair,
  neutralizers, webs, ECM — are part of the calculation.
* Derived stats on top of the calculated attributes: DPS and volley with application against a
  target, effective HP, local and remote repair, sustainable tank, capacitor simulation, heat
  simulation, spool-up, navigation and lock time, and the warfare buffs applied to each hull with
  their sources. Curves for plotting: DPS by range and target velocity, lock time by signature
  radius, capacitor level by time.
* Mutaplasmids (abyssal modules and drones), tactical modes, strategic cruiser subsystems.
* A native JSON fit document (`FitDocument`) for storage and round-trip, plus import and export
  of EFT, DNA and the in-game XML format.

What it does not do:

* It holds no names. `sde.bin` has IDs and numbers only; English names are an optional separate
  product (`DogmaText`), and a consumer with its own database can use that instead.
* It does not decide what exists in the game. The importer keeps every type the engine is able
  to calculate, published or not (see the type-selection rule below); which types to offer in a
  UI is the consumer's decision.
* It does not forbid overfitting on CPU, powergrid or slots — those are reported (`Resource`,
  `SlotCapacity`). Only structurally impossible fits (wrong category, rig size mismatch, an
  occupied subsystem socket, `canFitShipType`/`Group` restrictions) are rejected with a
  `DogmaError`.
* No networking. ESI data (character skills, PI colonies) is mapped by the consumer into the
  engine's own types.

## Requirements

* Swift tools 6.4, Swift language mode 6.
* macOS 26+, iOS 26+.
* Experimental features: `Lifetimes` (DogmaKit, DogmaModels, DogmaText, DogmaPlanetary) and
  `LifetimeDependence` (DogmaModels). The API makes heavy use of `~Copyable` / `~Escapable`
  types and `@_lifetime`.
* Two dependencies, resolved by SwiftPM:
  * [FlatBin](https://github.com/artem-shimanski/FlatBin) — zero-copy flat-binary serialization
    (`@FlatCodable`, `.View` types, `FlatDecoder`); the format of every `.bin` resource.
  * [BitField](https://github.com/artem-shimanski/BitField) — the `@BitField` / `@Bit` macros
    used for packed IDs and modifiers.

  Both ship macros: Xcode asks to trust them on the first build (command line:
  `-skipMacroValidation`).

If the `swift` in `PATH` is not the Xcode toolchain, use `xcrun swift`.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/artem-shimanski/DogmaKit.git", .upToNextMinor(from: "0.2.1"))
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "DogmaKit", package: "DogmaKit"),
        .product(name: "DogmaText", package: "DogmaKit")
    ])
]
```

## Products and targets

| Target | Product | Purpose |
|---|---|---|
| `DogmaIDs` | library | The typed SDE identifiers (`TypeID`, `GroupID`, `AttributeID`, `EffectID`, …). No dependencies; the `SDE` package depends on this product alone. |
| `DogmaModels` | — (re-exported) | The flat-binary schema of `sde.bin` (`DogmaSDE`), `PerfectDictionary`, the `TypeResolver` and `NameCatalog` protocols. Re-exported by `DogmaKit`. |
| `DogmaKit` | library | The engine: `DogmaEngine`, the write API (`Fit`), the read API (`FitStats`), `FitDocument`, `TypeCatalog`. Ships `Resources/sde.bin` and the generated ID constants (`TypeID.rifter`, `AttributeID.cpu`, …). |
| `DogmaKitIO` | library | Import and export of EFT, DNA and in-game XML (`FitImporter`, `FitExporter`), to and from `FitDocument`. Pure transformations; names come from a `TypeResolver` / `NameCatalog` the consumer supplies (`DogmaText.TextCatalog` implements both). |
| `DogmaText` | library | English names from the SDE (`Resources/text-en.bin`, `TextCatalog`). Independent of `DogmaKit`. `TextCatalog` is a `TypeResolver` itself and can be installed as the debug name source so IDs print as `Rifter [587]`. |
| `DogmaPlanetary` | library | Planetary production: `planetary.bin`, `PlanetaryCatalog`, the extractor formula, `Colony` built from a `ColonySnapshot`, `ColonySimulation` producing a `Forecast`, colony fitting and customs. Does not depend on `DogmaKit`. |
| `SDESchemaGenerator` | — | Executable behind the `generate-schema` plugin. |
| `DogmaDataImporter` | — | Executable behind the `sde-import` plugin. |
| `SDESchemaGeneratorPlugin` | plugin | Command plugin, verb `generate-schema`. |
| `DogmaDataImporterPlugin` | — | Command plugin, verb `sde-import`. |

Tests: `DogmaKitTests`, `DogmaKitIOTests`, `DogmaPlanetaryTests`.

## Usage

The engine is an actor. All writes go through `edit`, all reads through `evaluate`; the
calculation runs lazily on the first `evaluate` after an edit. The values handed to the blocks
(`Fit`, `FitStats` and everything reached from them) are non-escapable views that live only
inside the block — return plain values (IDs, numbers, `Resource`, `DamageVector`, …) out of it.

```swift
import DogmaKit

let engine = DogmaEngine()

// Write: one pilot with all skills at V, a Rifter, a few modules.
let hullID = try await engine.edit { fit in
    let pilot = try fit.pilots.add(skillLevel: 5)
    let hull = pilot.hull
    try hull.set(typeID: .rifter)

    let gun = try hull.modules.add(._200mmAutoCannonII)
    try gun.setCharge(.emps)
    gun.state = .active

    let ab = try hull.modules.add(._1MNAfterburnerII)
    ab.state = .active

    _ = try hull.modules.add(.damageControlII)
    return pilot.id.hull
}

// Read.
let (cpu, dps, ehp, align) = await engine.evaluate { stats in
    let hull = stats[hullID]
    let dps = hull.dps()
    return (hull.cpu,
            dps.em + dps.thermal + dps.kinetic + dps.explosive,
            hull.hitPoints.effective(resonance: hull.resonance),
            hull.navigation.alignTime)
}
print("CPU \(cpu.used)/\(cpu.total), DPS \(dps), EHP shield \(ehp.shield), align \(align) s")
```

`evaluate(reload:spool:)` takes the read-side policies — how reloads are spread over the cycle
and how far spooling modules are wound up. They do not trigger a recalculation, so comparing
two policies is two `evaluate` calls.

Storage: `engine.export(name:sde:names:)` / `engine.export(pilot:…)` produce a `FitDocument`;
`engine.load(_:strict:)` replaces the session with one, `fit.load(_:strict:)` inside `edit`
adds to it.

## Data pipeline

The engine reads its data from flat-binary resources generated from the SDE JSONL export.
Generation is done by two command plugins that write into the package directory. The SDE
export itself is expected in `.SDE/` at the package root and is not in git.

### Updating the SDE

```
Scripts/update-sde.sh [--build N]   # default: the latest build on developers.eveonline.com
Scripts/update-sde.sh --check       # requested / cached / linked / latest builds, changes nothing
```

The script keeps a shared cache of dumps outside any repository, one `<build>/` directory per
build, in `$EVE_SDE_CACHE` (default `~/Library/Caches/EVE-SDE`), downloads a build only when it
is not cached, and makes `.SDE` a symlink to it. A real `.SDE` directory is moved into the cache
under its own build number (or aside as `.replaced-<timestamp>` if that slot is taken), never
deleted. Without `--command` it then runs `generate-schema`, rebuilds the importer and runs
`sde-import`. `--package DIR --command VERB [-- args]` does the same for another package.
Packages that link the cache are listed in `$EVE_SDE_CACHE/.packages`; after a successful update the
build the package was linked to before is deleted unless another listed package still links it.

1. `generate-schema` — reads `.sde-config.json` (input directory and the list of JSONL files)
   and derives the `Codable` row schema into
   `Sources/DogmaDataImporter/Generated/SDESchema.swift`.

   ```
   xcrun swift package --allow-writing-to-package-directory generate-schema
   ```

2. `sde-import` — runs `DogmaDataImporter`, which applies the manual patches in
   `DogmaDataImporter/Patch.swift` (synthetic effects and attributes the SDE lacks) and writes:
   * `Sources/DogmaKit/Resources/sde.bin` — the engine's database;
   * `Sources/DogmaKit/Generated/*.swift` — ID constants (`TypeID`, `GroupID`, `AttributeID`,
     `EffectID`, …);
   * `Sources/DogmaIDs/Generated/SDEVersion.swift` — the SDE build number and release date;
   * `Sources/DogmaText/Resources/text-en.bin` — English names;
   * `Sources/DogmaPlanetary/Resources/planetary.bin` and
     `Sources/DogmaPlanetary/Generated/SchematicIDs.swift` — PI data.

   ```
   xcrun swift package --allow-writing-to-package-directory sde-import
   ```

All generated files are committed: the package does not build without the generated
constants, and the `.bin` resources are what ships. Rules the importer keeps:

* **Determinism.** Re-running the import on the same SDE build produces byte-identical
  `Generated/*.swift` and `.bin` files — a clean `git status`. On a name collision the lower ID
  wins; hashed tables are built from key-sorted input; flat-raw structs carry explicit zero
  padding fields so no garbage bytes reach the file.
* **Type selection.** Not "published", but "everything the engine can calculate": a type from
  the selected categories/groups that has a `typeDogma` record, plus everything published.
  `published` in the SDE does not mean "exists in the game", and the SDE has no flag that does.
  The exception is skills — only published ones, since every pilot gets all of them and an
  unpublished skill with bonuses would change the results.

## Tests

```
xcrun swift test
```

Swift Testing suites in three targets; the full run takes about 40 seconds. Some tests pin
exact numbers from the current `sde.bin` (e.g. `PlanetaryCatalogTests`), so after a re-import
with a new SDE build they may need new values. `ESIColonyTests` checks a live colony whose ESI
responses are embedded in the test.

## License

MIT, see [LICENSE](LICENSE).

## CCP disclaimer

EVE Online and the EVE logo are registered trademarks of CCP hf. The bundled data (`sde.bin`,
`text-en.bin`, `planetary.bin` and the generated ID constants) is derived from CCP's Static
Data Export and is used under the
[EVE Developer License](https://developers.eveonline.com/license-agreement). This project is
not affiliated with or endorsed by CCP.
