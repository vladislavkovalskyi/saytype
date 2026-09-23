import ApplicationServices
import Foundation
import VMCore

/// Reads the text of the window in front through Accessibility, for one dictation: its title,
/// the focused field around the caret, and the text visible in it.
///
/// Blocking and bounded: a deadline, a node cap and a character cap, and a messaging timeout per
/// call so a hung app cannot hold it. Call it off the main thread. Secure text fields are never
/// asked for their value. Nothing is set on the app: accessibility trees an app keeps off
/// (Electron without `AXManualAccessibility`) stay off, and such an app gives its window title.
public enum ScreenContextReader {
    public struct Limits: Sendable {
        public var budget = Duration.milliseconds(80)
        public var maxNodes = 600
        public var maxCharacters = 20_000
        /// The focused field: its visible part, or this much around the caret.
        public var focusedCharacters = 4_000
        /// A web page, from the top of the part in view: about a screenful.
        public var webCharacters = 6_000
        /// Seconds one Accessibility call may take before it gives up.
        public var messagingTimeout: Float = 0.04

        public init() {}
    }

    public struct Reading: Sendable {
        public var text = ScreenText()
        /// Elements of the window looked at.
        public var nodes = 0
        public var elapsed = Duration.zero
        /// The deadline or a cap cut the walk short.
        public var truncated = false
        /// Role of the focused element, for the debug command.
        public var focusedRole: String?
        /// The window's web area gave its text in one piece.
        public var webText = false
    }

    /// Reads the focused window of the app with this process id.
    public static func read(pid: pid_t, limits: Limits = Limits()) -> Reading {
        let clock = ContinuousClock()
        let start = clock.now
        var walk = Walk(deadline: start + limits.budget, limits: limits)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, limits.messagingTimeout)
        var reading = Reading()
        guard let window = element(app, kAXFocusedWindowAttribute) ?? element(app, kAXMainWindowAttribute) else {
            reading.elapsed = clock.now - start
            return reading
        }
        reading.text.title = string(window, kAXTitleAttribute) ?? ""
        walk.characters += reading.text.title.count

        var focused: AXUIElement?
        if let element = element(app, kAXFocusedUIElementAttribute) {
            focused = element
            reading.focusedRole = string(element, kAXRoleAttribute)
            if !isSecure(element) {
                reading.text.focused = fieldText(element, limit: limits.focusedCharacters)
                walk.characters += reading.text.focused.count
            }
        }

        walk.run(from: window, skipping: focused)
        reading.text.visible = walk.texts
        reading.nodes = walk.nodes
        reading.truncated = walk.truncated
        reading.webText = walk.webText
        reading.elapsed = clock.now - start
        return reading
    }

    // MARK: The walk

    /// Breadth first from the window: the toolbar and the sidebar come before what is deep in the
    /// content, and a node cap keeps a big window from taking the whole budget.
    struct Walk {
        let deadline: ContinuousClock.Instant
        let limits: Limits
        var nodes = 0
        var characters = 0
        var texts: [String] = []
        var seen = Set<String>()
        var truncated = false
        var webText = false

        init(deadline: ContinuousClock.Instant, limits: Limits) {
            self.deadline = deadline
            self.limits = limits
        }

        /// Role, subrole, title, description and children in one call per element.
        static let attributes: [String] = [
            kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute,
            kAXChildrenAttribute, kAXVisibleChildrenAttribute, kAXVisibleRowsAttribute,
        ]

        mutating func run(from window: AXUIElement, skipping focused: AXUIElement?) {
            var queue: [AXUIElement] = [window]
            var head = 0
            // Toolbars are buttons with everyday names: they wait until the content is read.
            var later: [AXUIElement] = []
            let clock = ContinuousClock()
            while head < queue.count || !later.isEmpty {
                guard nodes < limits.maxNodes, characters < limits.maxCharacters, clock.now < deadline else {
                    truncated = true
                    return
                }
                if head == queue.count {
                    queue.append(contentsOf: later)
                    later.removeAll()
                }
                let element = queue[head]
                head += 1
                nodes += 1
                var values: CFArray?
                guard AXUIElementCopyMultipleAttributeValues(element, Self.attributes as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &values) == .success,
                      let values = values as? [AnyObject], values.count == 7
                else { continue }
                let role = Self.value(values[0]) as? String ?? ""
                let subrole = Self.value(values[1]) as? String
                if subrole == (kAXSecureTextFieldSubrole as String) || Self.skipped.contains(role) { continue }
                add(Self.value(values[2]) as? String)
                add(Self.value(values[3]) as? String)

                if let focused, CFEqual(element, focused) { continue }
                switch role {
                case kAXStaticTextRole as String:
                    add(ScreenContextReader.string(element, kAXValueAttribute))
                case kAXTextAreaRole as String, kAXTextFieldRole as String, kAXComboBoxRole as String:
                    add(ScreenContextReader.fieldText(element, limit: limits.focusedCharacters))
                case "AXWebArea":
                    // A web page gives the text in view in one piece; its elements need not be walked.
                    if let text = ScreenContextReader.webText(element, limit: min(limits.webCharacters, limits.maxCharacters - characters)) {
                        add(text)
                        webText = true
                        continue
                    }
                default:
                    break
                }
                // Lists and tables name their visible rows; everything else its children.
                let children = (Self.value(values[6]) as? [AXUIElement]).flatMap { $0.isEmpty ? nil : $0 }
                    ?? (Self.value(values[5]) as? [AXUIElement]).flatMap { $0.isEmpty ? nil : $0 }
                    ?? (Self.value(values[4]) as? [AXUIElement])
                    ?? []
                if role == kAXToolbarRole as String {
                    later.append(contentsOf: children)
                } else {
                    queue.append(contentsOf: children)
                }
            }
        }

        private mutating func add(_ text: String?) {
            guard let text else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return }
            let room = limits.maxCharacters - characters
            guard room > 0 else { return }
            let kept = trimmed.count > room ? ScreenContextReader.wholeWords(String(trimmed.prefix(room)), cutStart: false, cutEnd: true) : trimmed
            texts.append(kept)
            characters += kept.count
        }

        /// Elements with no words in them or under them.
        static let skipped: Set<String> = [
            kAXScrollBarRole as String, kAXImageRole as String, kAXValueIndicatorRole as String,
            kAXSplitterRole as String, kAXGrowAreaRole as String, kAXMenuBarRole as String, "AXRuler",
        ]

        /// A missing attribute comes back as an AXValue holding an error.
        static func value(_ object: AnyObject) -> AnyObject? {
            if CFGetTypeID(object) == AXValueGetTypeID(), AXValueGetType(object as! AXValue) == .axError { return nil }
            return object
        }
    }

    // MARK: Fields

    /// The visible part of a text field or text area; without one, the text around the caret;
    /// without that, the start of its value.
    static func fieldText(_ element: AXUIElement, limit: Int) -> String {
        let count = number(element, kAXNumberOfCharactersAttribute)
        if let visible = range(element, kAXVisibleCharacterRangeAttribute), visible.length > 0 {
            var wanted = visible
            let cut = visible.length > limit
            if cut {
                // A tall editor: the part around the caret, if the caret is in view.
                let caret = range(element, kAXSelectedTextRangeAttribute)?.location ?? visible.location
                let center = (visible.location...(visible.location + visible.length)).contains(caret) ? caret : visible.location + visible.length / 2
                let start = max(visible.location, min(center - limit / 2, visible.location + visible.length - limit))
                wanted = CFRange(location: start, length: limit)
            }
            if let text = string(element, forRange: wanted) { return wholeWords(text, cutStart: cut, cutEnd: cut) }
        }
        if let count, count > limit, let caret = range(element, kAXSelectedTextRangeAttribute) {
            let start = max(0, min(caret.location - limit / 2, count - limit))
            if let text = string(element, forRange: CFRange(location: start, length: limit)) {
                return wholeWords(text, cutStart: start > 0, cutEnd: start + limit < count)
            }
        }
        // Past this size a field is a document, and its value would be copied whole.
        if let count, count > limit * 4 { return "" }
        guard let value = string(element, kAXValueAttribute) else { return "" }
        return value.count > limit ? wholeWords(String(value.prefix(limit)), cutStart: false, cutEnd: true) : value
    }

    /// Text cut out of a longer one loses the word cut in two at either end: "ctationController"
    /// is no term.
    static func wholeWords(_ text: String, cutStart: Bool, cutEnd: Bool) -> String {
        var slice = Substring(text)
        if cutStart, let space = slice.firstIndex(where: \.isWhitespace) { slice = slice[space...] }
        if cutEnd, let space = slice.lastIndex(where: \.isWhitespace) { slice = slice[..<space] }
        return String(slice)
    }

    /// The text of a web area through WebKit's and Chromium's text markers: from the top of the
    /// part scrolled into view, `limit` characters at most. Without a way to find the view, the
    /// page from its start. A long page is never copied whole.
    static func webText(_ element: AXUIElement, limit: Int) -> String? {
        guard limit > 0 else { return nil }
        // A marker with no index (a form field at the top) comes back as NSNotFound.
        if let start = viewStart(of: element),
           let index = parameter(element, "AXIndexForTextMarker", start) as? Int, sane.contains(index),
           let text = webText(element, from: start, to: index + limit) {
            return wholeWords(text, cutStart: false, cutEnd: text.count >= limit)
        }
        guard let whole = parameter(element, "AXTextMarkerRangeForUIElement", element) else { return nil }
        if let length = parameter(element, "AXLengthForTextMarkerRange", whole) as? Int, length > limit {
            guard let first = parameter(element, "AXTextMarkerForIndex", NSNumber(value: 0)) else { return nil }
            return webText(element, from: first, to: limit).map { wholeWords($0, cutStart: false, cutEnd: true) }
        }
        return (parameter(element, "AXStringForTextMarkerRange", whole) as? String).map { String($0.prefix(limit)) }
    }

    /// The text marker at the top left of the part of the page in view. A web area is as tall as
    /// the page; the scroll area around it is the view.
    private static func viewStart(of element: AXUIElement) -> CFTypeRef? {
        guard var bounds = frame(of: element) else { return nil }
        if let parent = self.element(element, kAXParentAttribute), let view = frame(of: parent) {
            bounds = bounds.intersection(view)
        }
        guard !bounds.isEmpty, let value = AXValueCreate(.cgRect, &bounds) else { return nil }
        return parameter(element, "AXStartTextMarkerForBounds", value)
    }

    /// From a marker to the marker at `endIndex`, or to the end of the page when that is closer.
    private static func webText(_ element: AXUIElement, from start: CFTypeRef, to endIndex: Int) -> String? {
        let end = parameter(element, "AXTextMarkerForIndex", NSNumber(value: endIndex))
            ?? parameter(element, "AXTextMarkerRangeForUIElement", element).flatMap { parameter(element, "AXEndTextMarkerForTextMarkerRange", $0) }
        guard let end, let range = parameter(element, "AXTextMarkerRangeForUnorderedTextMarkers", [start, end] as CFArray) else { return nil }
        return parameter(element, "AXStringForTextMarkerRange", range) as? String
    }

    private static func parameter(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, value, &result) == .success else { return nil }
        return result
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    // MARK: Attributes

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// Numbers and ranges come from another app: NSNotFound and garbage must not reach arithmetic.
    static let sane = 0..<Int(Int32.max)

    static func number(_ element: AXUIElement, _ attribute: String) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let number = value as? Int, sane.contains(number)
        else { return nil }
        return number
    }

    static func range(_ element: AXUIElement, _ attribute: String) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range), sane.contains(range.location), sane.contains(range.length) else { return nil }
        return range
    }

    static func string(_ element: AXUIElement, forRange range: CFRange) -> String? {
        var range = range
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &value) == .success
        else { return nil }
        return value as? String
    }

    static func isSecure(_ element: AXUIElement) -> Bool {
        string(element, kAXSubroleAttribute) == (kAXSecureTextFieldSubrole as String)
    }
}
