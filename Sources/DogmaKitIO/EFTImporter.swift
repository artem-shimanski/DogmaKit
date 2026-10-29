//
//  EFTImporter.swift
//  DogmaKitIO
//
//  Created by Artem Shimanski on 02.08.2026.
//
//  EFT is the game's clipboard format and the de facto third-party standard, with a mutation extension.
//  Spec: https://developers.eveonline.com/docs/guides/fitting/
//

#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif
import DogmaKit

struct EFTImporter {

    private let context: FitImporter

    init(_ context: FitImporter) {
        self.context = context
    }

    // MARK: - Input

    func parse(_ text: String) -> ImportResult {
        var result = ImportResult()
        // Split on `\n` only: `components(separatedBy: .newlines)` treats CRLF as two separators, inserting an empty
        // line between every pair and breaking sections. A leftover `\r` is removed by `trimmed`.
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(\.trimmed)

        // Several fits in one text are common for a clipboard, so split on headers.
        var chunks: [[String]] = []
        for line in lines {
            if Self.isHeader(line) {
                chunks.append([line])
            } else if !chunks.isEmpty {
                chunks[chunks.count - 1].append(line)
            }
        }
        guard !chunks.isEmpty else {
            return ImportResult(warnings: [.malformedHeader(lines.first ?? "")])
        }

        for chunk in chunks {
            parse(chunk: chunk, into: &result)
        }
        if result.documents.isEmpty && result.warnings.isEmpty {
            result.warnings.append(.noFitsFound)
        }
        return result
    }

    /// The header is the only line of the form `[Hull, Fit name]`. An empty-slot stub (`[Empty High slot]`) has no
    /// comma and a mutation block header (`[1] Base Item`) does not end with a bracket.
    private static func isHeader(_ line: String) -> Bool {
        line.hasPrefix("[") && line.hasSuffix("]") && line.contains(",")
    }

    private func parse(chunk: [String], into result: inout ImportResult) {
        var lines = chunk
        let mutations = Self.extractMutations(&lines)

        let header = lines.removeFirst()
        guard let (shipName, fitName) = Self.parseHeader(header) else {
            result.warnings.append(.malformedHeader(header))
            return
        }
        guard let shipID = context.resolver.typeID(named: shipName) else {
            result.warnings.append(.unknownType(shipName))
            return
        }

        var document = context.makeDocument(name: fitName, ship: shipID)
        var modules: [FitDocument.Module] = []
        var drones: [FitDocument.Drone] = []
        var implants: [FitDocument.Item] = []
        var boosters: [FitDocument.Item] = []

        for section in Self.sections(of: lines) {
            var parsed: [(index: Int, entry: Entry)] = []
            for (index, line) in section.enumerated() {
                guard let entry = parse(line: line, into: &result) else { continue }
                parsed.append((index, entry))
            }
            // An empty-slot stub (`[Empty High slot]`) is significant: it shifts its neighbours in the rack and thus
            // heat propagation. The position within a section is the socket number; an EFT section is exactly one rack.
            let hasGaps = section.contains(where: Self.isStub)

            for (index, entry) in parsed {
                switch entry {
                case let .item(typeID, spec):
                    switch context.placement(of: typeID) {
                    case .module:
                        var module = FitDocument.Module(type: typeID)
                        module.socket = hasGaps ? index : nil
                        module.state = spec.offline ? .offline : nil
                        if let chargeID = spec.chargeID { module.charge = .init(chargeID) }
                        module.mutation = mutation(spec.mutationRef,
                                                   from: mutations,
                                                   on: typeID,
                                                   into: &result)
                        modules.append(module)
                    case .drone:
                        var drone = FitDocument.Drone(type: typeID)
                        drone.count = UInt8(clamping: max(1, spec.amount ?? 1))
                        // EFT cannot tell "in bay" from "in space"; assume a posted fit shows its combat setup.
                        drone.active = true
                        drone.mutation = mutation(spec.mutationRef,
                                                  from: mutations,
                                                  on: typeID,
                                                  into: &result)
                        drones.append(drone)
                    case .implant:
                        implants.append(.init(typeID))
                    case .booster:
                        boosters.append(.init(typeID))
                    case .charge, .cargo, .none:
                        result.warnings.append(.droppedCargo(typeID, quantity: spec.amount ?? 1))
                    }
                case .stub:
                    continue
                }
            }
        }

        document.pilots[0].implants = implants
        document.pilots[0].boosters = boosters
        document.pilots[0].ship?.modules = modules
        document.pilots[0].ship?.drones = drones
        result.documents.append(document)
    }

    // MARK: - Lines

    private struct ItemSpec {
        var chargeID: TypeID?
        var amount: Int?
        var offline = false
        var mutationRef: Int?
    }

    private enum Entry {
        case item(TypeID, ItemSpec)
        case stub
    }

    private static func isStub(_ line: String) -> Bool {
        line.hasPrefix("[") && line.hasSuffix("]")
    }

    private func parse(line: String, into result: inout ImportResult) -> Entry? {
        guard !line.isEmpty else { return nil }
        if Self.isStub(line) { return .stub }

        var rest = line
        var spec = ItemSpec()

        // Suffixes are stripped from the tail in the reverse of the order they are written: `name, charge /offline [1]`.
        if let ref = Self.stripMutationReference(&rest) { spec.mutationRef = ref }
        spec.offline = Self.stripOffline(&rest)
        if let amount = Self.stripAmount(&rest) { spec.amount = amount }

        var name = rest
        if let comma = rest.firstIndex(of: ",") {
            name = String(rest[rest.startIndex..<comma]).trimmed
            let chargeName = String(rest[rest.index(after: comma)...]).trimmed
            if !chargeName.isEmpty {
                if let chargeID = context.resolver.typeID(named: chargeName) {
                    spec.chargeID = chargeID
                } else {
                    result.warnings.append(.unknownType(chargeName))
                }
            }
        }
        guard !name.isEmpty else {
            result.warnings.append(.malformedLine(line))
            return nil
        }
        guard let typeID = context.resolver.typeID(named: name) else {
            result.warnings.append(.unknownType(name))
            return nil
        }
        return .item(typeID, spec)
    }

    /// ` [12]` at the end of a line references a mutation block.
    private static func stripMutationReference(_ line: inout String) -> Int? {
        guard line.hasSuffix("]"), let open = line.lastIndex(of: "[") else { return nil }
        let digits = line[line.index(after: open)..<line.index(before: line.endIndex)]
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let ref = Int(digits) else { return nil }
        line = String(line[line.startIndex..<open]).trimmed
        return ref
    }

    /// ` /offline`: the only state marker in the format. The game ignores it on import, but the user's intent is kept.
    private static func stripOffline(_ line: inout String) -> Bool {
        let suffix = "/offline"
        guard line.count > suffix.count,
              line.suffix(suffix.count).lowercased() == suffix else { return false }
        line = String(line.dropLast(suffix.count)).trimmed
        return true
    }

    /// ` x42`: quantity for drones and cargo.
    private static func stripAmount(_ line: inout String) -> Int? {
        guard let space = line.lastIndex(of: " ") else { return nil }
        let tail = line[line.index(after: space)...]
        guard tail.first == "x" else { return nil }
        let digits = tail.dropFirst()
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let amount = Int(digits) else { return nil }
        line = String(line[line.startIndex..<space]).trimmed
        return amount
    }

    private static func parseHeader(_ line: String) -> (ship: String, name: String?)? {
        guard line.hasPrefix("["), line.hasSuffix("]") else { return nil }
        let body = line.dropFirst().dropLast()
        guard let comma = body.firstIndex(of: ",") else { return nil }
        let ship = String(body[body.startIndex..<comma]).trimmed
        let name = String(body[body.index(after: comma)...]).trimmed
        guard !ship.isEmpty else { return nil }
        return (ship, name.isEmpty ? nil : name)
    }

    /// Sections are separated by empty lines. Their boundaries matter only for sockets; the engine assigns racks itself.
    private static func sections(of lines: [String]) -> [[String]] {
        var sections: [[String]] = []
        var current: [String] = []
        for line in lines {
            if line.isEmpty {
                if !current.isEmpty { sections.append(current); current = [] }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { sections.append(current) }
        return sections
    }

    // MARK: - Mutations

    /// Mutation block: `[N] <base type>` / `<mutaplasmid>` / `<attribute value, ...>`. The base name duplicates the
    /// module line, so only the second and third lines are used.
    private struct MutationBlock {
        var mutaplasmidName: String
        var rolls: [(name: String, value: Double)]
    }

    /// Extracts mutation blocks from the line stream: a `[N]` header continues until an empty line.
    private static func extractMutations(_ lines: inout [String]) -> [Int: MutationBlock] {
        var blocks: [Int: [String]] = [:]
        var currentRef: Int?
        var current: [String] = []
        var consumed = Set<Int>()

        func flush() {
            if let ref = currentRef, !current.isEmpty { blocks[ref] = current }
            currentRef = nil
            current = []
        }

        for (index, line) in lines.enumerated() {
            if let (ref, tail) = parseMutationHeader(line) {
                flush()
                currentRef = ref
                current = [tail]
                consumed.insert(index)
            } else if line.isEmpty {
                flush()
            } else if currentRef != nil {
                current.append(line)
                consumed.insert(index)
            }
        }
        flush()

        for index in consumed.sorted(by: >) {
            lines.remove(at: index)
        }

        return blocks.compactMapValues { block -> MutationBlock? in
            guard block.count >= 2 else { return nil }
            return MutationBlock(mutaplasmidName: block[1].trimmed,
                                 rolls: block.count >= 3 ? parseRolls(block[2]) : [])
        }
    }

    private static func parseMutationHeader(_ line: String) -> (ref: Int, tail: String)? {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
        let digits = line[line.index(after: line.startIndex)..<close]
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let ref = Int(digits) else { return nil }
        return (ref, String(line[line.index(after: close)...]).trimmed)
    }

    /// `speedFactor 1.6, cpu -40`: INTERNAL (`AttributeInfo.name`) attribute names, so they contain no spaces.
    private static func parseRolls(_ line: String) -> [(name: String, value: Double)] {
        line.split(separator: ",").compactMap { pair in
            let parts = pair.trimmed.split(separator: " ")
            guard parts.count == 2, let value = Double(parts[1]) else { return nil }
            return (String(parts[0]), value)
        }
    }

    private func mutation(_ ref: Int?,
                          from blocks: [Int: MutationBlock],
                          on typeID: TypeID,
                          into result: inout ImportResult) -> FitDocument.Mutation? {
        guard let ref, let block = blocks[ref] else { return nil }
        guard let mutaplasmidID = context.resolver.typeID(named: block.mutaplasmidName) else {
            result.warnings.append(.unknownMutaplasmid(block.mutaplasmidName))
            return nil
        }
        guard context.catalog.isMutaplasmid(mutaplasmidID, applicableTo: typeID) else {
            result.warnings.append(.unknownMutaplasmid(block.mutaplasmidName))
            return nil
        }

        var rolls: [FitDocument.Mutation.Roll] = []
        var unknown: [String] = []
        for roll in block.rolls {
            guard let attributeID = context.resolver.attributeID(named: roll.name) else {
                unknown.append(roll.name)
                continue
            }
            rolls.append(.init(attribute: attributeID, value: roll.value))
        }
        // If NO name resolved, the consumer simply has no attribute table: report one loss, not one warning per name.
        if !unknown.isEmpty {
            if rolls.isEmpty {
                result.warnings.append(.mutationRollsDropped(typeID))
            } else {
                result.warnings.append(contentsOf: unknown.map { .unknownAttribute($0) })
            }
        }
        return FitDocument.Mutation(mutaplasmid: .init(mutaplasmidID), rolls: rolls)
    }
}
