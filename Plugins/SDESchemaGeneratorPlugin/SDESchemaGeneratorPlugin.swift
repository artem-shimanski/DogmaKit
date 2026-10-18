//
//  SDESchemaGeneratorPlugin.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 10.04.2026.
//


import PackagePlugin
import Foundation

import PackagePlugin
import Foundation

@main
struct SDESchemaGeneratorPlugin: CommandPlugin {
    func performCommand(context: PackagePlugin.PluginContext, arguments: [String]) async throws {
        let options = try parseOptions(arguments)
        let packageRoot = context.package.directoryURL
        let configURL = packageRoot.appending(path: options.config)
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: configURL))
        let sde = packageRoot.appending(path: config.sde)
        let output = packageRoot.appending(path: config.output)
        let tool = try context.tool(named: options.tool)

        let files = config.files

        let process = Process()
        process.executableURL = tool.url
        process.arguments = [sde.path(), output.path()] + files
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SchemaGenerationError(terminationStatus: process.terminationStatus, message: nil)
        }
    }

    private func parseOptions(_ arguments: [String]) throws -> Options {
        var options = Options()
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            guard index + 1 < arguments.count else {
                throw SchemaGenerationError(terminationStatus: 1, message: "Missing value for option \(key)")
            }
            index += 1
            let value = arguments[index]
            index += 1
            switch key {
            case "--config": options.config = value
            case "--tool": options.tool = value
            case "--target": continue
            default: throw SchemaGenerationError(terminationStatus: 1, message: "Unknown option \(key)")
            }
        }
        return options
    }
}

private struct Options {
    var config: String = ".sde-config.json"
    var tool: String = "SDESchemaGenerator"
}

private struct Config: Decodable {
    var sde: String
    var output: String
    var files: [String]
}

private struct SchemaGenerationError: Error {
    let terminationStatus: Int32
    let message: String?
}
