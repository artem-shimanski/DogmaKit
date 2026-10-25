//
//  SnapshottableMacro.swift
//  DogmaKitMacros
//

import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@Snapshottable` on a `FitStats` node: generates a nested `Snapshot` struct with one
/// `public let` per field and a `snapshot()` method that fills it.
///
/// Fields, in declaration order:
/// - every `public` instance property with an explicit type, unless marked `@SnapshotIgnored`;
/// - `public` methods without parameters marked `@SnapshotField` (expensive methods stay out
///   by default);
/// - `@SnapshotNested` properties or methods return another node or collection: the field
///   type is `T.Snapshot` (`T.Snapshot?` for `T?`) and the value is `.snapshot()` of it.
///
/// A property whose type cannot be stored (a `~Escapable` view, an opaque type) without
/// one of the markers fails to compile, so a new property is either copied or explicitly
/// excluded, never lost silently.
public struct SnapshottableMacro: MemberMacro {

    struct Field {
        var name: String
        var type: TypeSyntax
        var value: ExprSyntax
        var docs: [String]
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(StructDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: node, message: SnapshotDiagnostic.notAStruct))
            return []
        }

        var fields: [Field] = []
        var isValid = true

        for member in declaration.memberBlock.members {
            if let variable = member.decl.as(VariableDeclSyntax.self) {
                guard isPublicInstance(variable.modifiers),
                      !variable.attributes.contains(named: "SnapshotIgnored")
                else { continue }
                let isNested = variable.attributes.contains(named: "SnapshotNested")
                for binding in variable.bindings {
                    guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.trimmed else {
                        continue
                    }
                    guard let type = binding.typeAnnotation?.type.trimmed else {
                        context.diagnose(Diagnostic(node: binding, message: SnapshotDiagnostic.missingType(name.text)))
                        isValid = false
                        continue
                    }
                    fields.append(field(name: name.text,
                                        type: type,
                                        access: ExprSyntax(DeclReferenceExprSyntax(baseName: name)),
                                        isNested: isNested,
                                        docs: docs(of: variable)))
                }
            }
            else if let function = member.decl.as(FunctionDeclSyntax.self),
                    function.attributes.contains(named: "SnapshotField")
                        || function.attributes.contains(named: "SnapshotNested") {
                let signature = function.signature
                guard isPublicInstance(function.modifiers),
                      signature.parameterClause.parameters.isEmpty,
                      signature.effectSpecifiers == nil,
                      let type = signature.returnClause?.type.trimmed
                else {
                    context.diagnose(Diagnostic(node: function.name,
                                                message: SnapshotDiagnostic.invalidMethod(function.name.text)))
                    isValid = false
                    continue
                }
                let name = function.name.trimmed
                fields.append(field(name: name.text,
                                    type: type,
                                    access: "\(name)()",
                                    isNested: function.attributes.contains(named: "SnapshotNested"),
                                    docs: docs(of: function)))
            }
        }

        guard isValid else { return [] }
        return [structDecl(fields), methodDecl(fields)]
    }

    private static func field(name: String,
                              type: TypeSyntax,
                              access: ExprSyntax,
                              isNested: Bool,
                              docs: [String]) -> Field {
        guard isNested else {
            return Field(name: name, type: type, value: access, docs: docs)
        }
        if let optional = type.as(OptionalTypeSyntax.self) {
            return Field(name: name,
                         type: "\(optional.wrappedType.trimmed).Snapshot?",
                         value: "\(access)?.snapshot()",
                         docs: docs)
        }
        return Field(name: name, type: "\(type).Snapshot", value: "\(access).snapshot()", docs: docs)
    }

    private static func structDecl(_ fields: [Field]) -> DeclSyntax {
        var body = ""
        for field in fields {
            for line in field.docs {
                body += "    \(line)\n"
            }
            body += "    public let \(field.name): \(field.type)\n"
        }
        return """
        /// Values of this node's read stats, detached from the engine: a plain value that
        /// outlives `DogmaEngine.evaluate` and can be sent across actors. Generated by
        /// `@Snapshottable`; see `snapshot()`.
        public struct Snapshot: Sendable, Equatable {
        \(raw: body)}
        """
    }

    private static func methodDecl(_ fields: [Field]) -> DeclSyntax {
        let arguments = fields
            .map { "        \($0.name): \($0.value)" }
            .joined(separator: ",\n")
        let call = fields.isEmpty ? "Snapshot()" : "Snapshot(\n\(arguments)\n    )"
        return """
        /// Copies this node's read stats into a `Snapshot`.
        public func snapshot() -> Snapshot {
            \(raw: call)
        }
        """
    }

    private static func isPublicInstance(_ modifiers: DeclModifierListSyntax) -> Bool {
        var isPublic = false
        for modifier in modifiers {
            switch modifier.name.tokenKind {
            case .keyword(.public), .keyword(.open):
                isPublic = true
            case .keyword(.static), .keyword(.class):
                return false
            default:
                break
            }
        }
        return isPublic
    }

    /// Doc comment lines (`///`) of a declaration, carried over to its field.
    private static func docs(of declaration: some SyntaxProtocol) -> [String] {
        declaration.leadingTrivia.compactMap { piece in
            if case let .docLineComment(text) = piece { return text }
            return nil
        }
    }
}

/// Marker macros for `@Snapshottable`. They expand to nothing: the member macro reads
/// them from the syntax.
public struct SnapshotMarkerMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

enum SnapshotDiagnostic: DiagnosticMessage {
    case notAStruct
    case missingType(String)
    case invalidMethod(String)

    var message: String {
        switch self {
        case .notAStruct:
            "@Snapshottable can only be applied to a struct"
        case let .missingType(name):
            "'\(name)' needs an explicit type to be part of the snapshot; mark it @SnapshotIgnored to exclude it"
        case let .invalidMethod(name):
            "'\(name)' must be a public instance method without parameters, 'async' or 'throws' to be a snapshot field"
        }
    }

    var diagnosticID: MessageID {
        switch self {
        case .notAStruct: MessageID(domain: "Snapshottable", id: "notAStruct")
        case .missingType: MessageID(domain: "Snapshottable", id: "missingType")
        case .invalidMethod: MessageID(domain: "Snapshottable", id: "invalidMethod")
        }
    }

    var severity: DiagnosticSeverity { .error }
}

extension AttributeListSyntax {
    func contains(named name: String) -> Bool {
        contains { element in
            element.as(AttributeSyntax.self)?.attributeName.trimmedDescription == name
        }
    }
}

@main
struct DogmaKitMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        SnapshottableMacro.self,
        SnapshotMarkerMacro.self
    ]
}
