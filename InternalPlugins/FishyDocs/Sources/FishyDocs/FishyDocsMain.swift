// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//
import ArgumentParser
import Foundation
import Markdown

internal func log(_ log: String) {
    print("[fishy-docs] \(log)")
}

internal enum Commands {
    internal static let Namespace: String = "fishy-docs"
    internal static let Enable: String = "\(Namespace):enable"
    internal static let Disable: String = "\(Namespace):disable"
    internal static let Skip: String = "\(Namespace):skip-next"
}

/// Detects a `fishy-docs:enable` `@Comment` in a docc file, enabling the plugin for the given file.
internal struct DetectFishyDocs: MarkupWalker {
    internal var detected: Bool = false

    internal mutating func visitParagraph(_ paragraph: Paragraph) {
        self.detected = self.detected || paragraph.plainText.contains("fishy-docs:enable")
    }
}

internal struct ConcatCodeBlocks: MarkupWalker {
    internal var importBlocks: [CodeBlock] = []
    internal var codeBlocks: [CodeBlock] = []

    /// True if capturing code blocks is enabled
    internal var includeCodeBlock: Bool = true

    /// Allows for skipping a single code block, followed after the fishy-docs:skip-next
    internal var skipNextCodeBlock: Bool = false

    /// Name of the file we're compile-testing
    internal let name: String

    internal var code: String {
        var codeBlockStrings: [String] = []
        for block in importBlocks {
            codeBlockStrings.append(block.code)
        }

        codeBlockStrings.append("func __compileTest_\(self.name)() async throws {")
        for block in codeBlocks {
            var sourceCode: String = "// ==== "

            var fileNameWasSet: Bool = false
            if let range = block.range {
                let startLoc: SourceLocation = range.lowerBound
                if let fileName = startLoc.source?.pathComponents.split(separator: "/").last?.last {
                    fileNameWasSet = true
                    sourceCode += "\(fileName):\(startLoc.line)"
                }
            }

            if !fileNameWasSet {
                sourceCode += " <unknown loc>"
            }

            sourceCode += " ----------------------------------------\n"
            sourceCode += block.code

            codeBlockStrings.append(sourceCode)
        }
        codeBlockStrings.append("}")  // end of __test()

        return codeBlockStrings.joined(separator: "\n")
    }

    internal init(name: String) {
        self.name = name
    }

    internal mutating func visitParagraph(_ paragraph: Paragraph) {
        if paragraph.plainText.contains(Commands.Enable) {
            self.includeCodeBlock = true
        } else if paragraph.plainText.contains(Commands.Disable) {
            self.includeCodeBlock = false
        } else if paragraph.plainText.contains(Commands.Skip) {
            self.skipNextCodeBlock = true
            self.includeCodeBlock = false
        }
    }

    internal mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        guard !self.skipNextCodeBlock else {
            self.skipNextCodeBlock = false
            return
        }
        guard self.includeCodeBlock else {
            return
        }

        if codeBlock.code.contains("import ") {
            self.importBlocks.append(codeBlock)
        } else {
            self.codeBlocks.append(codeBlock)
        }
    }
}

@main
internal struct FishyDocsMain: ParsableCommand {
    @Option(help: "Folder containing the docc documentation to scan for fishy-docs")
    internal var doccFile: String

    @Option(help: "Where to generate the sources")
    internal var outputFile: String

    internal mutating func run() throws {
        let fileName: String = self.doccFile
        let testFileName: String = self.outputFile

        // we always have to create the target file... since we're a .buildPlugin
        // even if we won't generate anything into it.
        try Data().write(to: URL(fileURLWithPath: testFileName))

        guard let doccFileURL = URL(string: "file://\(doccFile)") else {
            log("Failed to parse: \(self.doccFile)")
            return
        }
        let document: Document = try Document(parsing: doccFileURL)

        guard self.usesFishyDocs(document: document, url: doccFileURL) else {
            return
        }

        guard let code = try makeDocsTestCode(document: document, doccFileName: fileName) else {
            return
        }

        log("Writing \(fileName) -> \(testFileName)")
        try code.write(toFile: "\(testFileName)", atomically: true, encoding: .utf8)
    }

    internal func usesFishyDocs(document: Document, url _: URL) -> Bool {
        var detectFishyDocs: DetectFishyDocs = DetectFishyDocs()
        detectFishyDocs.visit(document)
        return detectFishyDocs.detected
    }

    internal func makeDocsTestCode(document: Document, doccFileName: String) -> String? {
        assert(!doccFileName.isEmpty)

        guard var name = doccFileName.split(separator: "/").last else {
            return nil
        }
        guard let simpleName = name.split(separator: ".").first else {
            return nil
        }
        name = simpleName

        var concatCodeBlocks: ConcatCodeBlocks = ConcatCodeBlocks(name: String(name))
        concatCodeBlocks.visit(document)

        guard !concatCodeBlocks.code.isEmpty else {
            return nil
        }

        var output: String = "// ==== Concat CodeBlocks from '\(doccFileName)' -----------------------------\n"
        output += "// DO NOT EDIT THIS FILE AS IT WILL BE RE-GENERATED BY FISHY-DOCS PLUGIN.\n"
        output += "// To edit snippets in this file, edit \(doccFileName) instead.\n"
        output += "\n"
        output += concatCodeBlocks.code

        return output
    }
}
