import AppKit
import Observation
import VMCore

/// Identifiers from the user's code folders, for the Whisper prompt and the text formatter.
///
/// Scans run in the background at utility priority: when a folder is added, on demand, and at
/// launch for folders whose cache is older than a day. Preview launches show sample projects
/// and never read, scan or cache a folder.
@MainActor
@Observable
final class ProjectTermsService {
    struct Project: Identifiable, Equatable {
        let path: String
        var termCount: Int
        var scannedAt: Date?
        var isScanning: Bool
        var isMissing: Bool

        var id: String { path }
        var name: String { URL(fileURLWithPath: path).lastPathComponent }
        /// "~/Code/shop".
        var displayPath: String { (path as NSString).abbreviatingWithTildeInPath }
    }

    private(set) var projects: [Project] = []
    /// Every folder's terms, best first, taking each folder in turn.
    private(set) var terms: [String] = []

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private var scans: [String: ProjectScan] = [:]
    @ObservationIgnored private var scanning: Set<String> = []
    @ObservationIgnored private var activated = false

    static let staleAfter: TimeInterval = 24 * 60 * 60
    static let termLimit = 400

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func activate() {
        guard !activated else { return }
        activated = true
        if AppModel.isPreviewLaunch {
            projects = Self.sampleProjects()
            terms = ["UserProfileCard", "useCartStore", "CheckoutForm", "OrderService", "fetchOrders", "PAYMENT_TIMEOUT", "useAuthSession", "ProductGrid", "InvoiceRecord", "react-query"]
            return
        }
        let folders = settings.value.projectFolders
        refresh()
        Task {
            let cached = await Task.detached(priority: .utility) {
                // The word tables of the developer rules are built here rather than in the first dictation.
                DeveloperFormatter.prepare()
                return folders.compactMap { ProjectScanner.loadCache(for: $0) }
            }.value
            for scan in cached { scans[scan.folder] = scan }
            refresh()
            let now = Date()
            for folder in folders where scans[folder].map({ now.timeIntervalSince($0.scannedAt) > Self.staleAfter }) ?? true {
                scan(folder)
            }
        }
    }

    // MARK: Folders

    func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Add", comment: "Button of the panel that picks code folders")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { add(url.standardizedFileURL.path) }
    }

    func add(_ path: String) {
        guard !projects.contains(where: { $0.path == path }) else { return }
        if AppModel.isPreviewLaunch {
            projects.append(Project(path: path, termCount: 0, scannedAt: nil, isScanning: false, isMissing: false))
            return
        }
        settings.value.projectFolders.append(path)
        refresh()
        scan(path)
    }

    func rescan(_ path: String) {
        guard !AppModel.isPreviewLaunch else { return }
        scan(path)
    }

    func remove(_ path: String) {
        if AppModel.isPreviewLaunch {
            projects.removeAll { $0.path == path }
            return
        }
        settings.value.projectFolders.removeAll { $0 == path }
        scans[path] = nil
        Task.detached(priority: .utility) { ProjectScanner.removeCache(for: path) }
        refresh()
    }

    // MARK: Scanning

    private func scan(_ path: String) {
        guard settings.value.projectFolders.contains(path), !scanning.contains(path) else { return }
        scanning.insert(path)
        refresh()
        Task {
            let result = await Task.detached(priority: .utility) {
                let scan = ProjectScanner.scan(URL(fileURLWithPath: path))
                try? ProjectScanner.saveCache(scan)
                return scan
            }.value
            scanning.remove(path)
            if settings.value.projectFolders.contains(path) {
                scans[path] = result
            } else {
                // Removed while it was being read.
                Task.detached(priority: .utility) { ProjectScanner.removeCache(for: path) }
            }
            refresh()
        }
    }

    private func refresh() {
        let folders = settings.value.projectFolders
        let next = folders.map { path in
            Project(
                path: path,
                termCount: scans[path]?.terms.count ?? 0,
                scannedAt: scans[path]?.scannedAt,
                isScanning: scanning.contains(path),
                isMissing: !FileManager.default.fileExists(atPath: path)
            )
        }
        if next != projects { projects = next }
        let merged = ProjectScanner.merge(folders.compactMap { scans[$0]?.terms }, limit: Self.termLimit)
        if merged != terms { terms = merged }
    }

    /// Previews draw made-up folders under the home folder and never touch the disk.
    private static func sampleProjects() -> [Project] {
        let home = NSHomeDirectory()
        let hour: TimeInterval = 60 * 60
        return [
            Project(path: home + "/Code/shop-front", termCount: 386, scannedAt: Date().addingTimeInterval(-2 * hour), isScanning: false, isMissing: false),
            Project(path: home + "/Code/api-server", termCount: 212, scannedAt: Date().addingTimeInterval(-20 * hour), isScanning: false, isMissing: false),
            Project(path: home + "/Code/design-system", termCount: 0, scannedAt: nil, isScanning: true, isMissing: false),
        ]
    }
}
