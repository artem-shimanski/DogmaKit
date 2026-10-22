//
//  DogmaDataImporterPlugin.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 11.06.2026.
//

import PackagePlugin
import Foundation

@main
struct DogmaDataImporterPlugin: CommandPlugin {
    func performCommand(context: PackagePlugin.PluginContext, arguments: [String]) async throws {
        let sde = context.package.directoryURL.appending(path: ".SDE")
        let output = context.package.directoryURL.appending(path: "Sources/DogmaKit")
        let textOutput = context.package.directoryURL.appending(path: "Sources/DogmaText")
        let planetaryOutput = context.package.directoryURL.appending(path: "Sources/DogmaPlanetary")
        let tool = try context.tool(named: "DogmaDataImporter").url
        
        let process = Process()
        process.executableURL = tool
        process.arguments = [sde.path(), output.path(), textOutput.path(), planetaryOutput.path()]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ImportError(terminationStatus: process.terminationStatus)
        }
    }
}

struct ImportError: Error, CustomStringConvertible {
    var terminationStatus: Int32
    var description: String { "DogmaDataImporter failed with exit status \(terminationStatus)" }
}
