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
        
        try Process.run(tool, arguments: [sde.path(), output.path(), textOutput.path(), planetaryOutput.path()])
    }
}
