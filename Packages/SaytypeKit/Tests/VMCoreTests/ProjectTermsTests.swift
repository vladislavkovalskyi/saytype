import Foundation
import Testing
@testable import VMCore

@Suite struct ProjectScannerTests {
    func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "saytype-project-\(UUID().uuidString)")
        func write(_ path: String, _ text: String) throws {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        try write("package.json", #"{"name": "@acme/shop-front", "dependencies": {"@tanstack/react-query": "5", "zustand": "4"}, "devDependencies": {"@types/node": "20"}}"#)
        try write("src/components/UserProfileCard.tsx", """
        import { useUserData } from '../hooks/useUserData'
        export function UserProfileCard() {
          const { data } = useUserData()
          return <div>{data.name}</div>
        }
        export const CART_STORAGE_KEY = 'cart'
        """)
        try write("src/hooks/useUserData.ts", """
        export const useUserData = () => useQuery({ queryKey: ['user'], queryFn: fetchUserProfile })
        async function fetchUserProfile() { return api.get('/me') }
        type UserProfile = { name: string }
        """)
        try write("server/main.go", """
        package main
        func (s *Server) HandleCheckout(w http.ResponseWriter) {}
        type OrderService struct {}
        """)
        try write("App/Sources/DictationController.swift", """
        final class DictationController {
            func startRecording(handsFree: Bool) {}
        }
        """)
        try write("api/models.py", "class InvoiceRecord:\n    def mark_as_paid(self):\n        pass\n")
        try write("node_modules/left-pad/index.js", "function shouldNotAppear() {}")
        try write(".hidden/secret.ts", "function hiddenHelperName() {}")
        try write("src/components/UserProfileCard.test.tsx", "function renderProfileForTest() {}")
        return root
    }

    @Test func readsDeclarationsFileNamesAndManifests() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let scan = ProjectScanner.scan(root)
        let terms = Set(scan.terms)
        for expected in ["shop-front", "react-query", "zustand", "UserProfileCard", "useUserData", "fetchUserProfile", "UserProfile",
                         "CART_STORAGE_KEY", "HandleCheckout", "OrderService", "DictationController", "startRecording",
                         "InvoiceRecord", "mark_as_paid"] {
            #expect(terms.contains(expected), "\(expected)")
        }
        for skipped in ["shouldNotAppear", "hiddenHelperName", "renderProfileForTest", "node", "data", "name"] {
            #expect(!terms.contains(skipped), "\(skipped)")
        }
        // The package name comes first, then multi-part identifiers before single words.
        #expect(scan.terms.first == "shop-front")
        #expect(scan.terms.firstIndex(of: "useUserData")! < scan.terms.firstIndex(of: "zustand")!)
        #expect(scan.files == 6)
        #expect(!scan.truncated)
    }

    @Test func stopsAtTheFileLimit() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        var limits = ProjectScanner.Limits()
        limits.maxFiles = 2
        let scan = ProjectScanner.scan(root, limits: limits)
        #expect(scan.files == 2)
        #expect(scan.truncated)
    }

    @Test func cacheRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "saytype-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let scan = ProjectScan(folder: "/tmp/some project", terms: ["useUserData"], files: 3, scannedAt: Date(timeIntervalSince1970: 1_000))
        try ProjectScanner.saveCache(scan, in: directory)
        #expect(ProjectScanner.loadCache(for: "/tmp/some project", in: directory) == scan)
        #expect(ProjectScanner.cacheURL(for: "/tmp/some project", in: directory).lastPathComponent.count == 21)
        #expect(ProjectScanner.loadCache(for: "/tmp/other", in: directory) == nil)
        ProjectScanner.removeCache(for: "/tmp/some project", in: directory)
        #expect(ProjectScanner.loadCache(for: "/tmp/some project", in: directory) == nil)
    }

    @Test func mergeTakesEachProjectInTurn() {
        let merged = ProjectScanner.merge([["aOne", "aTwo", "aThree"], ["bOne", "AONE"], ["cOne"]], limit: 5)
        #expect(merged == ["aOne", "bOne", "cOne", "aTwo", "aThree"])
    }

    /// This repository and its package checkouts as a large corpus: prints scan time and term counts.
    @Test func scansThisRepositoryWithinLimits() {
        let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let folders = [repo, repo.appending(path: "Packages/SaytypeKit/.build/checkouts"), repo.appending(path: "build/dev/SourcePackages/checkouts")]
        for folder in folders where FileManager.default.fileExists(atPath: folder.path) {
            let scan = ProjectScanner.scan(folder)
            print(String(format: "scan %@: %.0f ms, %d files, %d terms, truncated %@, top: %@", folder.path, scan.seconds * 1000, scan.files, scan.terms.count, scan.truncated ? "yes" : "no", scan.terms.prefix(12).joined(separator: " ")))
            #expect(scan.seconds < ProjectScanner.Limits().maxSeconds + 1)
            #expect(scan.terms.count <= ProjectScanner.Limits().maxTerms)
        }
    }
}

@Suite struct ProjectCanonicalizationTests {
    let canon = TermCanonicalizer(terms: ["useEffect"], projectTerms: ["useUserData", "DataBase", "isOn", "OrderService", "Header"])

    @Test func joinsSpokenAndMiscasedIdentifiers() {
        #expect(canon.apply(to: "вызови use user data в хедере") == "вызови useUserData в хедере")
        #expect(canon.apply(to: "вызови useUserdata.") == "вызови useUserData.")
        #expect(canon.apply(to: "поправь Order Service, потом") == "поправь OrderService, потом")
        #expect(canon.apply(to: "Use Effect") == "useEffect")
    }

    @Test func leavesPlainWordsAlone() {
        #expect(canon.apply(to: "the database is on") == "the database is on")
        #expect(canon.apply(to: "open the header") == "open the header")
        #expect(canon.apply(to: "use user, data") == "use user, data")
    }

    @Test func formatterUsesProjectTerms() {
        let settings = AppSettings()
        let text = TextFormatter.format(Transcript(text: "поправь use user data в order service"), settings: settings, projectTerms: ["useUserData", "OrderService"])
        #expect(text == "поправь useUserData в OrderService")
        #expect(TextFormatter.format(Transcript(text: "поправь use user data"), settings: settings) == "поправь use user data")
    }

    @Test func promptPutsProjectTermsAfterTheUserDictionary() {
        let terms = DictionaryRewriter.promptTerms(entries: [DictionaryEntry(heard: "", written: "Next.js")], builtInTerms: ["React"], projectTerms: ["useUserData", "next.js"])
        #expect(terms == ["Next.js", "useUserData", "React"])
    }

    @Test func promptStaysWithinTheTokenEstimate() {
        #expect(PromptBuilder.estimatedTokens("useUserData") == 3)
        #expect(PromptBuilder.estimatedTokens("Next.js") == 3)
        let cyrillic = Array(repeating: "длинноетерминологическоеслово", count: 40)
        let prompt = PromptBuilder.prompt(glossary: cyrillic)!
        let estimate = prompt.split(separator: ",").map { PromptBuilder.estimatedTokens(String($0)) }.reduce(0, +)
        #expect(estimate <= PromptBuilder.tokenLimit)
    }
}

@Suite struct DeveloperPipelineTests {
    @Test func promptModeFormatsSpokenCode() {
        let settings = AppSettings()
        let mode = settings.modes.first { $0.id == DictationMode.promptID }!
        let transcript = Transcript(text: "Эээ, поправь кэмел кейс юзер дата в хедер точка tsx, если x не равно null.")
        let result = DictationPipeline.format(transcript, settings: settings, mode: mode)
        #expect(result.text == "Поправь userData в header.tsx, если x != null.")
        #expect(Backticks.wrap(result.text) == "Поправь `userData` в `header.tsx`, если x != null.")
    }
}
