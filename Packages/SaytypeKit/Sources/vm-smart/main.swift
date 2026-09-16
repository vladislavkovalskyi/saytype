import Foundation
import VMCore
import VMSmart

// vm-smart download
// vm-smart structure <file with texts separated by "---" lines>

let arguments = Array(CommandLine.arguments.dropFirst())
let store = SmartModelStore()

switch arguments.first {
case "download":
    try await store.download { value in
        FileHandle.standardError.write(String(format: "\r%.0f%%", value * 100).data(using: .utf8)!)
    }
    print("\n\(store.folder.path)")

case "structure":
    guard arguments.count > 1 else { fatalError("usage: vm-smart structure <file>") }
    let samples = try String(contentsOfFile: arguments[1], encoding: .utf8)
        .components(separatedBy: "\n---\n")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    let structurer = SmartStructurer(store: store)
    let loadStart = Date()
    try await structurer.load()
    _ = try await structurer.labels(for: ["Прогрев.", "Готово."])
    print(String(format: "load + warmup %.2fs\n", Date().timeIntervalSince(loadStart)))
    for sample in samples {
        let start = Date()
        let sentences = SmartStructure.sentences(sample)
        let labels = try await structurer.labels(for: sentences)
        let result = try await structurer.structure(sample)
        print(String(format: "=== %.2fs %@", Date().timeIntervalSince(start) / 2, String(labels.map(\.rawValue))))
        print(result ?? "(без изменений)\n\(sample)")
        print()
    }

default:
    print("usage: vm-smart download | structure <file>")
}
