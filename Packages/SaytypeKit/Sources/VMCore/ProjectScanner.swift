import Foundation

/// Identifiers of one code project, best first.
public struct ProjectScan: Codable, Equatable, Sendable {
    public var folder: String
    public var terms: [String]
    /// Source files read.
    public var files: Int
    public var scannedAt: Date
    public var seconds: Double
    /// A file, size or time limit cut the scan short.
    public var truncated: Bool

    public init(folder: String, terms: [String], files: Int, scannedAt: Date = Date(), seconds: Double = 0, truncated: Bool = false) {
        self.folder = folder
        self.terms = terms
        self.files = files
        self.scannedAt = scannedAt
        self.seconds = seconds
        self.truncated = truncated
    }
}

/// Reads a code folder for the names a developer dictates: declared functions, types and
/// constants, component and file names, the package name and dependencies.
///
/// Pure Foundation and synchronous; callers run it off the main thread.
public enum ProjectScanner {
    public struct Limits: Sendable {
        public var maxFiles = 6000
        public var maxFileBytes = 400_000
        public var maxSeconds = 3.0
        public var maxTerms = 400

        public init() {}
    }

    static let sourceExtensions: Set<String> = ["ts", "tsx", "js", "jsx", "mjs", "cjs", "swift", "py", "go", "rs", "kt", "java", "rb", "php", "vue", "svelte"]
    static let manifestNames: Set<String> = ["package.json", "Package.swift", "Cargo.toml", "pyproject.toml", "go.mod"]
    static let skippedDirectories: Set<String> = [
        "node_modules", "build", "dist", "DerivedData", "Pods", "vendor", "target", "out", "coverage", "Carthage",
        "bower_components", "__pycache__", "venv", "env", "site-packages",
        // Tests declare long throwaway names nobody dictates.
        "Tests", "tests", "test", "__tests__", "__mocks__", "spec", "specs", "fixtures",
    ]
    /// Words that start a declaration in one of the source languages.
    static let declarationKeywords: Set<String> = [
        "function", "class", "interface", "type", "enum", "const", "def", "func", "fn", "struct", "protocol", "trait",
        "actor", "typealias", "fun", "object", "module", "record",
    ]
    /// Declared names too generic to teach.
    static let genericNames: Set<String> = [
        "App", "Props", "State", "Error", "Config", "Options", "Result", "Context", "Provider", "Default", "Main", "Index",
        "Base", "Model", "View", "Value", "Key", "Keys", "Node", "Event", "Element", "Item", "Items", "Data", "Type", "Types",
        "CodingKeys", "Body", "Content", "Style", "Styles", "Layout", "Page", "Root", "Store", "Test", "Tests", "Utils",
        "extends", "implements", "from", "where", "self", "Self", "some", "any", "default", "export", "async",
    ]
    static let genericFileNames: Set<String> = ["index", "main", "mod", "lib", "utils", "types", "constants", "page", "layout", "route", "__init__", "setup", "test", "config"]

    // MARK: Scan

    public static func scan(_ folder: URL, limits: Limits = Limits()) -> ProjectScan {
        let started = Date()
        var counter = Counter()
        var files = 0
        var truncated = false
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey]
        if let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let url as URL in enumerator {
                let name = url.lastPathComponent
                guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                if values.isDirectory == true {
                    if skippedDirectories.contains(name) { enumerator.skipDescendants() }
                    continue
                }
                if values.isSymbolicLink == true { continue }
                let ext = url.pathExtension
                let isManifest = manifestNames.contains(name)
                guard isManifest || sourceExtensions.contains(ext) else { continue }
                if Date().timeIntervalSince(started) > limits.maxSeconds || files >= limits.maxFiles {
                    truncated = true
                    break
                }
                guard (values.fileSize ?? 0) <= limits.maxFileBytes, !name.hasSuffix(".min.js"), !name.hasSuffix(".d.ts"),
                      !isTestFile(name), let data = try? Data(contentsOf: url) else { continue }
                files += 1
                if isManifest {
                    readManifest(name: name, data: data, into: &counter)
                } else {
                    readSource(data, into: &counter)
                    counter.addFileName(url.deletingPathExtension().lastPathComponent)
                }
            }
        }
        return ProjectScan(
            folder: folder.path,
            terms: counter.ranked(limit: limits.maxTerms),
            files: files,
            scannedAt: Date(),
            seconds: Date().timeIntervalSince(started),
            truncated: truncated
        )
    }

    static func isTestFile(_ name: String) -> Bool {
        name.contains(".test.") || name.contains(".spec.") || name.hasSuffix("_test.go") || name.hasPrefix("test_") || name.hasSuffix("Tests.swift")
    }

    /// Candidate names and how often each identifier appears.
    struct Counter {
        enum Origin: Int, Comparable {
            case projectName, dependency, declaration, fileName

            static func < (a: Origin, b: Origin) -> Bool { a.rawValue < b.rawValue }
        }

        var candidates: [String: Origin] = [:]
        var frequency: [String: Int] = [:]

        mutating func add(_ name: String, _ origin: Origin) {
            if let existing = candidates[name], existing <= origin { return }
            candidates[name] = origin
        }

        mutating func addFileName(_ name: String) {
            guard !ProjectScanner.genericFileNames.contains(name) else { return }
            add(name, .fileName)
        }

        /// Multi-part identifiers first, then dependencies, then single names; frequent first.
        func ranked(limit: Int) -> [String] {
            var scored: [(term: String, tier: Int, count: Int)] = []
            for (name, origin) in candidates {
                guard let tier = ProjectScanner.tier(of: name, origin: origin) else { continue }
                scored.append((name, tier, frequency[name] ?? 0))
            }
            scored.sort { a, b in
                if a.tier != b.tier { return a.tier < b.tier }
                if a.count != b.count { return a.count > b.count }
                if a.term.count != b.term.count { return a.term.count < b.term.count }
                return a.term < b.term
            }
            var seen = Set<String>()
            var result: [String] = []
            for item in scored {
                let key = TermCanonicalizer.squash(item.term)
                guard !key.isEmpty, seen.insert(key).inserted else { continue }
                result.append(item.term)
                if result.count == limit { break }
            }
            return result
        }
    }

    /// Letters a multi-part name needs to rank with the distinctive ones: `isOn` and `builtIn` are
    /// two plain words Whisper already spells.
    static let distinctiveLength = 8

    /// 0 project name, 1 long multi-part name, 2 short multi-part name, 3 dependency, 4 single
    /// name; `nil` drops it.
    static func tier(of name: String, origin: Counter.Origin) -> Int? {
        guard name.count >= 3, name.count <= 40, DeveloperText.isASCII(name), !name.hasPrefix("_"), !name.hasPrefix("$"),
              !genericNames.contains(name) else { return nil }
        if origin == .projectName { return 0 }
        let parts = DeveloperText.parts(of: name)
        let multiPart = parts.count >= 2 ? (name.count >= distinctiveLength ? 1 : 2) : nil
        if origin == .dependency { return multiPart ?? 3 }
        guard parts.count <= 5 else { return nil }
        if let multiPart { return multiPart }
        // A single lowercase word ("fetch", "data") is English, not a project term.
        guard let first = name.first, first.isUppercase, name.dropFirst().contains(where: \.isLowercase), name.count >= 4 else { return nil }
        return 4
    }

    // MARK: Sources

    /// One pass over the bytes: identifiers after declaration keywords, and counts of the
    /// identifiers that could be terms (with a capital letter or an underscore).
    static func readSource(_ data: Data, into counter: inout Counter) {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let bytes = raw.bindMemory(to: UInt8.self)
            let n = bytes.count
            var i = 0
            var afterKeyword = false
            while i < n {
                let b = bytes[i]
                if isIdentifierStart(b) {
                    let start = i
                    var interesting = false
                    while i < n, isIdentifierByte(bytes[i]) {
                        let c = bytes[i]
                        if (c >= 0x41 && c <= 0x5A) || (c == UInt8(ascii: "_") && i > start) { interesting = true }
                        i += 1
                    }
                    let length = i - start
                    guard length >= 2, length <= 40 else {
                        afterKeyword = false
                        continue
                    }
                    // Most identifiers are plain lowercase words: skip making a string for them.
                    let mayBeKeyword = length <= 9 && bytes[start] >= 0x61
                    guard afterKeyword || interesting || mayBeKeyword else { continue }
                    let word = String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<i]), as: UTF8.self)
                    if declarationKeywords.contains(word) {
                        afterKeyword = true
                        continue
                    }
                    if afterKeyword {
                        counter.add(word, .declaration)
                        afterKeyword = false
                    }
                    if interesting { counter.frequency[word, default: 0] += 1 }
                } else if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D || b == UInt8(ascii: "*") {
                    i += 1
                } else if b == UInt8(ascii: "("), afterKeyword {
                    // Go methods: func (s *Server) Handle.
                    var depth = 0
                    while i < n {
                        if bytes[i] == UInt8(ascii: "(") { depth += 1 }
                        if bytes[i] == UInt8(ascii: ")") { depth -= 1; if depth == 0 { i += 1; break } }
                        i += 1
                    }
                } else {
                    afterKeyword = false
                    i += 1
                }
            }
        }
    }

    private static func isIdentifierStart(_ b: UInt8) -> Bool {
        (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || b == UInt8(ascii: "_") || b == UInt8(ascii: "$")
    }

    private static func isIdentifierByte(_ b: UInt8) -> Bool {
        isIdentifierStart(b) || (b >= 0x30 && b <= 0x39)
    }

    // MARK: Manifests

    static func readManifest(name: String, data: Data, into counter: inout Counter) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        switch name {
        case "package.json":
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            if let project = json["name"] as? String { counter.add(packageName(project), .projectName) }
            for section in ["dependencies", "devDependencies", "peerDependencies"] {
                guard let dependencies = json[section] as? [String: Any] else { continue }
                for dependency in dependencies.keys.sorted() where !dependency.hasPrefix("@types/") {
                    counter.add(packageName(dependency), .dependency)
                }
            }
        case "Package.swift":
            let ns = text as NSString
            let range = NSRange(location: 0, length: ns.length)
            for match in swiftPackageName.matches(in: text, range: range) {
                let value = ns.substring(with: match.range(at: 1))
                // The first name: is the package; later ones are targets and products.
                counter.add(value, counter.candidates.values.contains(.projectName) ? .declaration : .projectName)
            }
            for match in swiftPackageURL.matches(in: text, range: range) {
                counter.add(ns.substring(with: match.range(at: 1)), .dependency)
            }
        case "Cargo.toml", "pyproject.toml":
            readTOML(text, into: &counter)
        case "go.mod":
            for line in text.split(separator: "\n") {
                let words = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                if words.first == "module", words.count >= 2 {
                    counter.add(String(words[1].split(separator: "/").last ?? words[1]), .projectName)
                } else if let path = words.first(where: { $0.contains(".") && $0.contains("/") }) {
                    counter.add(String(path.split(separator: "/").last ?? path), .dependency)
                }
            }
        default:
            break
        }
    }

    /// `name = "…"` under [package], [project] or [tool.poetry]; keys and quoted names in dependency sections.
    private static func readTOML(_ text: String, into counter: inout Counter) {
        var section = ""
        var inDependencyArray = false
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                section = line.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
                inDependencyArray = false
                continue
            }
            if inDependencyArray || line.hasPrefix("dependencies") && line.contains("[") {
                for quoted in line.split(separator: "\"").enumerated() where quoted.offset % 2 == 1 {
                    let name = quoted.element.prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
                    if !name.isEmpty { counter.add(String(name), .dependency) }
                }
                inDependencyArray = !line.contains("]")
                continue
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            if ["package", "project", "tool.poetry"].contains(section), key == "name" {
                let value = line[line.index(after: equals)...].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                if !value.isEmpty { counter.add(value, .projectName) }
            } else if section.hasSuffix("dependencies"), !key.isEmpty, key != "python" {
                counter.add(key, .dependency)
            }
        }
    }

    /// "@tanstack/react-query" → react-query.
    private static func packageName(_ name: String) -> String {
        String(name.split(separator: "/").last ?? Substring(name))
    }

    nonisolated(unsafe) private static let swiftPackageName = try! NSRegularExpression(pattern: #"\bname:\s*"([^"]+)""#)
    nonisolated(unsafe) private static let swiftPackageURL = try! NSRegularExpression(pattern: #"\.package\(\s*url:\s*"[^"]*/([^/"]+?)(?:\.git)?""#)

    // MARK: Several projects

    /// Terms of several projects, taking each project's best terms in turn, without duplicates.
    public static func merge(_ lists: [[String]], limit: Int) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        let longest = lists.map(\.count).max() ?? 0
        for index in 0..<longest {
            for list in lists where index < list.count {
                let term = list[index]
                guard seen.insert(TermCanonicalizer.squash(term)).inserted else { continue }
                result.append(term)
                if result.count == limit { return result }
            }
        }
        return result
    }

    // MARK: Cache

    public static var defaultCacheDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "dev.kovalskyi.saytype/projects", directoryHint: .isDirectory)
    }

    /// `projects/<hash>.json`; the hash is FNV-1a of the folder path.
    public static func cacheURL(for folder: String, in directory: URL = defaultCacheDirectory) -> URL {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in folder.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return directory.appending(path: String(format: "%016llx.json", hash))
    }

    public static func loadCache(for folder: String, in directory: URL = defaultCacheDirectory) -> ProjectScan? {
        guard let data = try? Data(contentsOf: cacheURL(for: folder, in: directory)),
              let scan = try? JSONDecoder().decode(ProjectScan.self, from: data),
              scan.folder == folder else { return nil }
        return scan
    }

    public static func saveCache(_ scan: ProjectScan, in directory: URL = defaultCacheDirectory) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(scan).write(to: cacheURL(for: scan.folder, in: directory), options: .atomic)
    }

    public static func removeCache(for folder: String, in directory: URL = defaultCacheDirectory) {
        try? FileManager.default.removeItem(at: cacheURL(for: folder, in: directory))
    }
}
