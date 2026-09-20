import AppKit
import Observation
import SwiftUI
import VMCore
import VMSystem

/// The menu bar icon and its native menu, rebuilt each time it opens.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    init(model: AppModel) {
        self.model = model
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        item.button?.setAccessibilityTitle("saytype")
        observeIcon()
    }

    // MARK: Icon

    private func observeIcon() {
        withObservationTracking {
            updateIcon()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeIcon() }
        }
    }

    private func updateIcon() {
        let recording: Bool
        switch model.dictation.phase {
        case .listening, .finishing: recording = true
        default: recording = false
        }
        let image = NSImage(systemSymbolName: recording ? "waveform.circle.fill" : "waveform", accessibilityDescription: "saytype")
        image?.isTemplate = true
        item.button?.image = image
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let dictation = model.dictation
        let settings = model.settings

        menu.addItem(viewItem(MenuHeader(model: model), height: 34))
        if !missingPermissions.isEmpty {
            menu.addItem(ClosureMenuItem(title: String(localized: "Grant Permissions…")) { [model] in
                model.mainSection = .permissions
                model.windows.showMain()
            })
        }
        menu.addItem(.separator())

        if let last = dictation.lastRecord {
            menu.addItem(.sectionHeader(title: String(localized: "Last Dictation")))
            menu.addItem(viewItem(MenuLastDictation(record: last), height: MenuLastDictation.height(for: last)))
            let paste = ClosureMenuItem(title: String(localized: "Paste Again")) { dictation.insertAgain(last) }
            paste.showShortcut(settings.value.shortcuts.pasteAgain)
            menu.addItem(paste)
            let copy = ClosureMenuItem(title: String(localized: "Copy")) { Paster.copy(last.text) }
            copy.showShortcut(settings.value.shortcuts.copyLast)
            menu.addItem(copy)

            let recent = NSMenuItem(title: String(localized: "Recent"), action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for record in dictation.history.prefix(8) {
                let title = record.text.replacingOccurrences(of: "\n", with: " ")
                let entry = ClosureMenuItem(title: title.count > 48 ? String(title.prefix(47)) + "…" : title) { dictation.insertAgain(record) }
                entry.toolTip = record.overlayMeta
                submenu.addItem(entry)
            }
            submenu.addItem(.separator())
            submenu.addItem(ClosureMenuItem(title: String(localized: "All History…")) { [model] in
                model.mainSection = .history
                model.windows.showMain()
            })
            recent.submenu = submenu
            menu.addItem(recent)
            menu.addItem(.separator())
        }

        let language = NSMenuItem(title: String(localized: "Language"), action: nil, keyEquivalent: "")
        let languages = NSMenu()
        for (index, value) in AppSettings.SpeechLanguage.all().enumerated() {
            let title = switch value {
            case .russian: "Русский"
            case .english: "English"
            case .auto: String(localized: "Automatic")
            default: value.localizedName()
            }
            // Russian, English and Automatic, then the rest.
            if index == 3 { languages.addItem(.separator()) }
            languages.addItem(ClosureMenuItem(title: title, isOn: settings.value.language == value) { settings.value.language = value })
        }
        language.submenu = languages
        menu.addItem(language)

        // Translate every dictation; the same switch the overlay's chip flips.
        let translate = NSMenuItem(title: String(localized: "Translate"), action: nil, keyEquivalent: "")
        let targets = NSMenu()
        targets.addItem(ClosureMenuItem(title: String(localized: "Off"), isOn: !settings.value.autoTranslate) {
            settings.value.autoTranslate = false
        })
        targets.addItem(.separator())
        // Detection is a way to listen, not a language to translate into.
        for (index, value) in AppSettings.SpeechLanguage.all().filter({ $0 != .auto }).enumerated() {
            let title = switch value {
            case .russian: "Русский"
            case .english: "English"
            default: value.localizedName()
            }
            if index == 2 { targets.addItem(.separator()) }
            let isOn = settings.value.autoTranslate && settings.value.translateTarget == value
            targets.addItem(ClosureMenuItem(title: title, isOn: isOn) {
                settings.value.translateTarget = value
                settings.value.autoTranslate = true
            })
        }
        translate.submenu = targets
        menu.addItem(translate)

        let mode = NSMenuItem(title: String(localized: "Mode"), action: nil, keyEquivalent: "")
        let modes = NSMenu()
        let current = settings.value.fixedModeID
        modes.addItem(ClosureMenuItem(title: DictationMode.automaticTitle, isOn: current == nil) { settings.value.fixedModeID = nil })
        modes.addItem(.separator())
        for value in settings.value.modes {
            modes.addItem(ClosureMenuItem(title: value.title, isOn: current == value.id) { settings.value.fixedModeID = value.id })
        }
        modes.addItem(.separator())
        modes.addItem(ClosureMenuItem(title: String(localized: "Edit Modes…")) { [model] in
            model.mainSection = .modes
            model.windows.showMain()
        })
        mode.submenu = modes
        menu.addItem(mode)

        let overlay = NSMenuItem(title: String(localized: "Overlay"), action: nil, keyEquivalent: "")
        let overlays = NSMenu()
        overlays.addItem(ClosureMenuItem(title: String(localized: "Island at the Notch"), isOn: settings.value.overlayStyle == .island) { settings.value.overlayStyle = .island })
        overlays.addItem(ClosureMenuItem(title: String(localized: "Pill Above the Dock"), isOn: settings.value.overlayStyle == .pill) { settings.value.overlayStyle = .pill })
        overlay.submenu = overlays
        menu.addItem(overlay)

        menu.addItem(ClosureMenuItem(title: String(localized: "Chat Style"), isOn: settings.value.isChatStyle) { settings.value.isChatStyle.toggle() })
        let smart = model.smartStructureBinding
        menu.addItem(ClosureMenuItem(title: String(localized: "Smart Structure"), isOn: smart.wrappedValue) { smart.wrappedValue.toggle() })
        menu.addItem(.separator())

        if let updater = model.updater, updater.isEnabled {
            let check = ClosureMenuItem(title: String(localized: "Check for Updates…")) { updater.checkForUpdates() }
            check.isEnabled = updater.canCheckForUpdates
            menu.addItem(check)
        }
        menu.addItem(ClosureMenuItem(title: String(localized: "Run Setup Again…")) { [model] in model.windows.showOnboarding() })
        let open = ClosureMenuItem(title: String(localized: "Open saytype…"), keyEquivalent: ",") { [model] in model.windows.showMain() }
        open.keyEquivalentModifierMask = [.command]
        menu.addItem(open)
        let quit = ClosureMenuItem(title: String(localized: "Quit saytype"), keyEquivalent: "q") { NSApp.terminate(nil) }
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)
    }

    private var missingPermissions: [Permission] {
        Permission.allCases.filter { model.state(of: $0) != .granted }
    }

    private func viewItem(_ view: some View, height: CGFloat) -> NSMenuItem {
        let item = NSMenuItem()
        let host = NSHostingView(rootView: view.frame(width: 300, height: height, alignment: .leading))
        host.frame = CGRect(x: 0, y: 0, width: 300, height: height)
        item.view = host
        return item
    }
}

/// App icon, name and the model state, as a non-interactive first row.
private struct MenuHeader: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 20, height: 20)
            Text("saytype").font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 8)
            Text(state).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
    }

    private var state: LocalizedStringKey {
        switch model.dictation.modelState {
        case .ready: "Whisper turbo"
        case .loading: "Preparing model"
        case .downloading(let fraction): "Model \(Int(fraction * 100))%"
        case .missing: "Model not downloaded"
        case .failed: "Model error"
        }
    }
}

private struct MenuLastDictation: View {
    let record: DictationRecord

    static func height(for record: DictationRecord) -> CGFloat {
        let text = record.text.replacingOccurrences(of: "\n", with: " ")
        let lines = min(3, max(1, Int(ceil(TextMeasure.width(text, size: 12.5) / 262))))
        return CGFloat(lines) * 17 + 26
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(CodeWords.attributed(record.text.replacingOccurrences(of: "\n", with: " "), size: 12.5))
                .font(.system(size: 12.5))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(record.overlayMeta)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 14)
        .padding(.trailing, 14)
        .padding(.vertical, 2)
    }
}
