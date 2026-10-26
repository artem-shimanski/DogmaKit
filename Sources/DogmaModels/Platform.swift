//
//  Platform.swift
//  DogmaModels
//
//  Created by Artem Shimanski on 26.10.2026.
//

#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

extension StringProtocol {
    /// The string without leading and trailing whitespace and newlines.
    package var trimmed: String {
        #if os(WASI)
        // FoundationEssentials has no `trimmingCharacters(in:)`.
        guard let first = firstIndex(where: { !$0.isWhitespace }),
              let last = lastIndex(where: { !$0.isWhitespace }) else { return "" }
        return String(self[first...last])
        #else
        trimmingCharacters(in: .whitespacesAndNewlines)
        #endif
    }
}

#if os(WASI)
/// Where data files are read from on WebAssembly, which has no `Bundle`: the directory of the executable.
package var executableDirectory: URL {
    URL(filePath: CommandLine.arguments[0]).deletingLastPathComponent()
}
#endif
