import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

private let carbonCommand: UInt32 = UInt32(cmdKey)
private let carbonOption: UInt32 = UInt32(optionKey)
private let carbonShift: UInt32 = UInt32(shiftKey)
private let carbonControl: UInt32 = UInt32(controlKey)
private var requestedAccessibilityThisLaunch = false
private var requestedScreenRecordingThisLaunch = false

enum CaptureMode: Equatable {
    case clipboardOnly
    case clipboardAndFile
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlay: ScreenshotOverlay?
    private var statusItem: NSStatusItem!
    private var screenshotMenuItem: NSMenuItem!
    private var shortcutWindow: ShortcutWindowController?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    private var shortcutKeyCode: UInt32 {
        get {
            let saved = UserDefaults.standard.integer(forKey: "shortcutKeyCode")
            return saved == 0 ? 1 : UInt32(saved) // S
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: "shortcutKeyCode") }
    }

    private var shortcutModifiers: UInt32 {
        get {
            let saved = UserDefaults.standard.integer(forKey: "shortcutModifiers")
            return saved == 0 ? (carbonOption | carbonShift) : UInt32(saved)
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: "shortcutModifiers") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        makeStatusItem()
        installHotKey()

        if CommandLine.arguments.contains("--capture") {
            DispatchQueue.main.async { [weak self] in self?.startCapture() }
        }
    }

    private func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Vimshot")
        statusItem.button?.toolTip = "Vimshot screenshot"

        let menu = NSMenu()
        screenshotMenuItem = NSMenuItem(
            title: "Take Screenshot  \(shortcutDescription())",
            action: #selector(startCaptureFromMenu),
            keyEquivalent: ""
        )
        screenshotMenuItem.target = self
        menu.addItem(screenshotMenuItem)
        menu.addItem(.separator())

        let configure = NSMenuItem(title: "Set Keyboard Shortcut…", action: #selector(configureShortcut), keyEquivalent: "")
        configure.target = self
        menu.addItem(configure)

        let quit = NSMenuItem(title: "Quit Vimshot", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc fileprivate func startCaptureFromMenu() {
        startCapture()
    }

    private func startCapture() {
        // A hidden or interrupted overlay must never block future captures.
        // Invoking the shortcut again resets any existing session first.
        overlay?.cancel()
        overlay = nil

        let session = ScreenshotOverlay { [weak self] in
            self?.overlay = nil
        }
        overlay = session
        session.start()
    }

    @objc private func configureShortcut() {
        guard shortcutWindow == nil else {
            shortcutWindow?.show()
            return
        }
        let current = Shortcut(keyCode: shortcutKeyCode, modifiers: shortcutModifiers)
        shortcutWindow = ShortcutWindowController(current: current, onSave: { [weak self] shortcut in
            guard let self else { return }
            self.shortcutKeyCode = shortcut.keyCode
            self.shortcutModifiers = shortcut.modifiers
            self.installHotKey()
            self.updateMenuTitle()
            self.shortcutWindow = nil
        }, onClose: { [weak self] in
            self?.shortcutWindow = nil
        })
        shortcutWindow?.show()
    }

    private func updateMenuTitle() {
        screenshotMenuItem.title = "Take Screenshot  \(shortcutDescription())"
    }

    private func installHotKey() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if eventHandler == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            InstallEventHandler(
                GetApplicationEventTarget(),
                vimshotHotKeyHandler,
                1,
                &eventType,
                UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                &eventHandler
            )
        }

        let id = EventHotKeyID(signature: 0x564D5348, id: 1)
        RegisterEventHotKey(
            shortcutKeyCode,
            shortcutModifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func shortcutDescription() -> String {
        var result = ""
        if shortcutModifiers & carbonControl != 0 { result += "⌃" }
        if shortcutModifiers & carbonOption != 0 { result += "⌥" }
        if shortcutModifiers & carbonShift != 0 { result += "⇧" }
        if shortcutModifiers & carbonCommand != 0 { result += "⌘" }
        result += Shortcut.keyName(for: shortcutKeyCode)
        return result
    }

    @objc private func quit() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        NSApp.terminate(nil)
    }
} 

private func vimshotHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return noErr }
    let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
    delegate.startCaptureFromMenu()
    return noErr
}

private struct Shortcut {
    let keyCode: UInt32
    let modifiers: UInt32

    static func from(event: NSEvent) -> Shortcut {
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) { modifiers |= carbonCommand }
        if event.modifierFlags.contains(.option) { modifiers |= carbonOption }
        if event.modifierFlags.contains(.shift) { modifiers |= carbonShift }
        if event.modifierFlags.contains(.control) { modifiers |= carbonControl }
        return Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    static func keyName(for keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 25: "9", 26: "7", 28: "8", 29: "0", 24: "=", 27: "-",
            30: "]", 33: "[", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".", 49: "Space"
        ]
        return names[keyCode] ?? "Key\(keyCode)"
    }
}

private final class ShortcutRecorderView: NSView {
    var onShortcut: ((Shortcut) -> Void)?
    private var shortcut: Shortcut?

    init(shortcut: Shortcut?) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        let title: String
        if let shortcut {
            var symbols = ""
            if shortcut.modifiers & carbonControl != 0 { symbols += "⌃" }
            if shortcut.modifiers & carbonOption != 0 { symbols += "⌥" }
            if shortcut.modifiers & carbonShift != 0 { symbols += "⇧" }
            if shortcut.modifiers & carbonCommand != 0 { symbols += "⌘" }
            title = symbols + Shortcut.keyName(for: shortcut.keyCode)
        } else {
            title = "Press a shortcut…"
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let text = NSAttributedString(string: title, attributes: attributes)
        let size = text.size()
        text.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }

    override func keyDown(with event: NSEvent) {
        let modifierOnlyKeys: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        guard !modifierOnlyKeys.contains(event.keyCode) else { return }
        let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
        guard !modifiers.isEmpty else {
            NSSound.beep()
            return
        }
        shortcut = Shortcut.from(event: event)
        needsDisplay = true
        onShortcut?(shortcut!)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }
}

private final class ShortcutWindowController: NSWindowController, NSWindowDelegate {
    private let recorder: ShortcutRecorderView
    private let onSave: (Shortcut) -> Void
    private let onClose: () -> Void
    private var saved = false

    init(current: Shortcut, onSave: @escaping (Shortcut) -> Void, onClose: @escaping () -> Void = {}) {
        self.recorder = ShortcutRecorderView(shortcut: current)
        self.onSave = onSave
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Vimshot Shortcut"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        window.delegate = self
        let label = NSTextField(labelWithString: "Press the keys you want to use for screenshots")
        label.alignment = .center
        label.frame = NSRect(x: 20, y: 125, width: 340, height: 22)
        recorder.frame = NSRect(x: 95, y: 70, width: 190, height: 42)
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.frame = NSRect(x: 155, y: 22, width: 70, height: 28)
        window.contentView?.addSubview(label)
        window.contentView?.addSubview(recorder)
        window.contentView?.addSubview(cancel)

        recorder.onShortcut = { [weak self] shortcut in
            guard let self else { return }
            self.saved = true
            self.onSave(shortcut)
            self.close()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(recorder)
    }

    @objc private func cancel() { close() }

    func windowWillClose(_ notification: Notification) {
        if !saved { onClose() }
    }
}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class ScreenshotOverlay {
    private let panel: OverlayPanel
    private let view: SelectionView
    private let desktopBounds: CGRect
    private let primaryScreenHeight: CGFloat
    private let onExit: () -> Void
    private var localKeyMonitor: Any?
    private var appObservers: [NSObjectProtocol] = []
    private var isFinished = false

    init(onExit: @escaping () -> Void) {
        self.onExit = onExit
        desktopBounds = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        primaryScreenHeight = NSScreen.main?.frame.height ?? 900

        view = SelectionView(frame: CGRect(origin: .zero, size: desktopBounds.size))
        panel = OverlayPanel(
            contentRect: desktopBounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        panel.contentView = view
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = true

        view.onFinish = { [weak self] selection, mode in
            self?.capture(selection, mode: mode)
        }
        view.onCancel = { [weak self] in
            self?.finish()
        }
        view.onSnapWindow = { [weak self] in
            self?.snapToWindow()
        }
        view.onSnapElement = { [weak self] in
            self?.snapToAccessibilityElement()
        }
    }

    func start() {
        let center = NotificationCenter.default
        appObservers.append(center.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            // Accessory/menu-bar apps do not reliably receive a matching
            // activation event. Cancel instead of retaining a hidden session.
            self?.finish()
        })

        NSApp.activate(ignoringOtherApps: true)
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Keep Escape reliable even if AppKit routes the event away from
            // the transparent overlay view.
            if event.keyCode == 53 {
                self.finish()
                return nil
            }
            return event
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
        view.focusCursor()
    }

    func cancel() {
        finish()
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        for observer in appObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        appObservers.removeAll()
        panel.orderOut(nil)
        onExit()
    }

    deinit {
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        for observer in appObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func capture(_ selection: CGRect, mode: CaptureMode) {
        // Screen Recording permission is required for the native capture.
        // End only this overlay before macOS opens its permission UI so the
        // menu-bar app remains usable and no dimmed screen is stranded.
        guard CGPreflightScreenCaptureAccess() else {
            panel.orderOut(nil)
            if !requestedScreenRecordingThisLaunch {
                requestedScreenRecordingThisLaunch = true
                _ = CGRequestScreenCaptureAccess()
            }
            finish()
            return
        }

        panel.orderOut(nil)

        let rect = selection.standardized.integral
        guard rect.width > 1, rect.height > 1 else {
            NSSound.beep()
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let destination: URL
        if mode == .clipboardAndFile {
            let folder = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Pictures/Screenshots", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HHmmss-SSS"
            destination = folder.appendingPathComponent("Vimshot-\(formatter.string(from: Date())).png")
        } else {
            destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("Vimshot-\(UUID().uuidString).png")
        }

        // AppKit uses a bottom-left origin; screencapture uses the Quartz top-left origin.
        let quartzX = Int(rect.minX.rounded())
        let quartzY = Int((primaryScreenHeight - rect.maxY).rounded())
        let quartzW = Int(rect.width.rounded())
        let quartzH = Int(rect.height.rounded())

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = [
                "-x", "-R", "\(quartzX),\(quartzY),\(quartzW),\(quartzH)",
                destination.path
            ]

            var captureSucceeded = false
            do {
                let completed = DispatchSemaphore(value: 0)
                process.terminationHandler = { _ in completed.signal() }
                try process.run()

                if completed.wait(timeout: .now() + 15) == .timedOut {
                    fputs("vimshot: screencapture timed out\n", stderr)
                    process.terminate()
                } else {
                    captureSucceeded = process.terminationStatus == 0
                }
            } catch {
                fputs("vimshot: unable to run screencapture: \(error)\n", stderr)
            }

            DispatchQueue.main.async {
                var copied = false
                if captureSucceeded, let image = NSImage(contentsOf: destination) {
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.writeObjects([image])
                }

                if mode == .clipboardOnly {
                    try? FileManager.default.removeItem(at: destination)
                }

                if !captureSucceeded || !copied {
                    NSSound.beep()
                    fputs("vimshot: capture failed\n", stderr)
                } else if mode == .clipboardOnly {
                    print("Copied screenshot to clipboard")
                } else {
                    print(destination.path)
                }
                self.finish()
            }
        }
    }

    private func snapToWindow() {
        guard let quartzRect = windowRect(at: view.cursorInScreenCoordinates) else {
            NSSound.beep()
            return
        }
        view.setSelection(CGRect(
            x: quartzRect.minX - desktopBounds.minX,
            y: primaryScreenHeight - quartzRect.maxY - desktopBounds.minY,
            width: quartzRect.width,
            height: quartzRect.height
        ))
    }

    private func snapToAccessibilityElement() {
        // Only ask macOS to show Settings once, and never prompt when the
        // permission is already granted. Re-prompting on every `e` press can
        // happen if the permission dialog caused the overlay to lose focus.
        guard AXIsProcessTrusted() else {
            // End only this capture session before opening Settings. Vimshot
            // remains alive in the menu bar, so there can never be a stranded
            // full-screen overlay behind the permission window.
            panel.orderOut(nil)
            if !requestedAccessibilityThisLaunch {
                requestedAccessibilityThisLaunch = true
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            }
            finish()
            return
        }

        let point = view.cursorInScreenCoordinates
        let quartzPoint = CGPoint(x: point.x, y: primaryScreenHeight - point.y)
        let system = AXUIElementCreateSystemWide()
        var element: AXUIElement?

        guard AXUIElementCopyElementAtPosition(system, Float(quartzPoint.x), Float(quartzPoint.y), &element) == .success,
              let element else {
            NSSound.beep()
            return
        }

        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue else {
            NSSound.beep()
            return
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              size.width > 1, size.height > 1 else {
            NSSound.beep()
            return
        }

        view.setSelection(CGRect(
            x: position.x - desktopBounds.minX,
            y: primaryScreenHeight - position.y - size.height - desktopBounds.minY,
            width: size.width,
            height: size.height
        ))
    }

    private func windowRect(at appKitPoint: CGPoint) -> CGRect? {
        let quartzPoint = CGPoint(x: appKitPoint.x, y: primaryScreenHeight - appKitPoint.y)
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        for window in windows {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width > 4, rect.height > 4,
                  rect.contains(quartzPoint) else { continue }
            return rect
        }
        return nil
    }
}

final class SelectionView: NSView {
    var onFinish: ((CGRect, CaptureMode) -> Void)?
    var onCancel: (() -> Void)?
    var onSnapWindow: (() -> Void)?
    var onSnapElement: (() -> Void)?

    private(set) var cursor = CGPoint.zero
    private var anchor: CGPoint?
    private var snappedSelection: CGRect?
    private var countBuffer = ""
    private var pendingG = false
    private let step: CGFloat = 10

    var cursorInScreenCoordinates: CGPoint {
        guard let window else { return cursor }
        let pointInWindow = convert(cursor, to: nil)
        return window.convertPoint(toScreen: pointInWindow)
    }

    override var acceptsFirstResponder: Bool { true }

    func focusCursor() {
        let mouse = NSEvent.mouseLocation
        cursor = CGPoint(
            x: min(max(mouse.x - frame.minX, 0), bounds.width),
            y: min(max(mouse.y - frame.minY, 0), bounds.height)
        )
        needsDisplay = true
    }

    func setSelection(_ rect: CGRect) {
        snappedSelection = rect.standardized
        anchor = nil
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        let rawKey = event.characters ?? event.charactersIgnoringModifiers ?? ""
        let key = rawKey.lowercased()
        let isUppercase = rawKey.count == 1 && rawKey != key && rawKey == rawKey.uppercased()
        let activeModifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let hasNoCommandModifiers = activeModifiers.subtracting(.shift).isEmpty

        // g1...g9 jumps to a 3x3 screen grid. This is checked before count
        // parsing so digits after g remain jump targets.
        if pendingG {
            pendingG = false
            if key == "g" {
                jumpToSpot(1) // gg: top-left
            } else if let digit = key.first, digit >= "1", digit <= "9" {
                jumpToSpot(Int(String(digit))!)
            } else {
                switch key {
                case "h": jumpToEdge(.left)
                case "j": jumpToEdge(.bottom)
                case "k": jumpToEdge(.top)
                case "l": jumpToEdge(.right)
                default: NSSound.beep()
                }
            }
            countBuffer = ""
            needsDisplay = true
            return
        }

        // Explicit counts are pixel distances: 20j moves exactly 20 pixels.
        // Looking only at command modifiers also allows numeric-keypad input.
        if hasNoCommandModifiers, key.count == 1, let digit = key.first,
           (digit >= "1" && digit <= "9" || digit == "0") {
            if digit != "0" || !countBuffer.isEmpty {
                countBuffer.append(digit)
                needsDisplay = true
                return
            }
        }

        // Uppercase directions jump all the way to that edge. G remains the
        // bottom-right corner shortcut.
        if isUppercase {
            let edge: Edge?
            switch key {
            case "h": edge = .left
            case "j": edge = .bottom
            case "k": edge = .top
            case "l": edge = .right
            default: edge = nil
            }
            if let edge {
                countBuffer = ""
                jumpToEdge(edge)
                needsDisplay = true
                return
            }
            if key == "g" {
                countBuffer = ""
                jumpToSpot(9) // bottom-right
                needsDisplay = true
                return
            }
        }

        let explicitDistance = Int(countBuffer)
        countBuffer = ""
        let defaultDistance: CGFloat = event.modifierFlags.contains(.shift) ? 1 :
            (event.modifierFlags.contains(.control) ? 1 :
            (event.modifierFlags.contains(.option) ? 100 : step))
        let amount = explicitDistance.map { CGFloat(max($0, 1)) } ?? defaultDistance

        switch event.keyCode {
        case 123: move(dx: -amount, dy: 0) // left
        case 124: move(dx: amount, dy: 0) // right
        case 125: move(dx: 0, dy: -amount) // down
        case 126: move(dx: 0, dy: amount) // up
        case 36, 76:
            let mode: CaptureMode = event.modifierFlags.contains(.shift)
                ? .clipboardAndFile
                : .clipboardOnly
            confirm(mode: mode) // return / enter
        case 53: onCancel?() // escape
        default:
            switch key {
            case "g": pendingG = true
            case "h": move(dx: -amount, dy: 0)
            case "j": move(dx: 0, dy: -amount)
            case "k": move(dx: 0, dy: amount)
            case "l": move(dx: amount, dy: 0)
            case "0": jumpToEdge(.left)
            case "$": jumpToEdge(.right)
            case "m": jumpToSpot(5) // center
            case "o": swapCorners()
            case "r": reset()
            case "w": onSnapWindow?()
            case "e": onSnapElement?()
            case "q": onCancel?()
            default: super.keyDown(with: event)
            }
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let currentSelection = snappedSelection ?? anchor.map { CGRect(
            x: min($0.x, cursor.x), y: min($0.y, cursor.y),
            width: abs(cursor.x - $0.x), height: abs(cursor.y - $0.y)
        ) }

        context.setFillColor(NSColor.black.withAlphaComponent(0.28).cgColor)
        context.fill(bounds)

        if let selection = currentSelection, selection.width > 0, selection.height > 0 {
            context.setBlendMode(.clear)
            context.fill(selection)
            context.setBlendMode(.normal)
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(2)
            context.stroke(selection)
        }

        context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: cursor.x, y: 0))
        context.addLine(to: CGPoint(x: cursor.x, y: bounds.height))
        context.move(to: CGPoint(x: 0, y: cursor.y))
        context.addLine(to: CGPoint(x: bounds.width, y: cursor.y))
        context.strokePath()

        drawKeyboardHUD()
    }

    private func drawKeyboardHUD() {
        let prefix = countBuffer.isEmpty ? (pendingG ? "g" : "") : countBuffer
        let hasSelection = anchor != nil || snappedSelection != nil
        let status: String
        if hasSelection {
            status = "Vimshot [\(prefix)]  RESIZE  h/j/k/l · exact 20j · edges H/J/K/L · grid g1–g9\nEnter copy · ⇧Enter save + copy · o swap · r reset · Esc cancel"
        } else {
            status = "Vimshot [\(prefix)]  MOVE  h/j/k/l · exact 20j · edges H/J/K/L · grid g1–g9\nEnter set corner · w window · e element · Esc cancel"
        }

        // Size and position the HUD inside the usable area of the display
        // containing the cursor. This avoids the menu bar, Dock, MacBook
        // notch, and incorrect sizing from a multi-display virtual desktop.
        let safeBounds = safeDrawingBoundsForCursor()
        let margin: CGFloat = safeBounds.width < 500 ? 8 : 16
        let padding: CGFloat = safeBounds.width < 500 ? 9 : 12
        let availableWidth = max(safeBounds.width - margin * 2, 180)
        let hudWidth = min(availableWidth, 1_080)
        let fontSize: CGFloat = safeBounds.width < 700 ? 10.5 : (safeBounds.width < 1_100 ? 11.5 : 13)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 4
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        let text = NSAttributedString(string: status, attributes: attributes)
        let contentWidth = max(hudWidth - padding * 2, 1)
        let measured = text.boundingRect(
            with: NSSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let hudHeight = ceil(measured.height) + padding * 2
        let hudRect = NSRect(
            x: safeBounds.minX + margin,
            y: max(safeBounds.minY + margin, safeBounds.maxY - margin - hudHeight),
            width: hudWidth,
            height: min(hudHeight, safeBounds.height - margin * 2)
        )

        let background = NSBezierPath(roundedRect: hudRect, xRadius: 10, yRadius: 10)
        NSColor.black.withAlphaComponent(0.68).setFill()
        background.fill()
        NSColor.white.withAlphaComponent(0.13).setStroke()
        background.lineWidth = 1
        background.stroke()

        text.draw(in: NSRect(
            x: hudRect.minX + padding,
            y: hudRect.minY + padding,
            width: contentWidth,
            height: min(ceil(measured.height), hudRect.height - padding * 2)
        ))
    }

    private func safeDrawingBoundsForCursor() -> CGRect {
        guard let window else { return bounds }
        let screenPoint = cursorInScreenCoordinates
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(screenPoint) })
                ?? window.screen
                ?? NSScreen.main else {
            return bounds
        }

        let screenFrame = screen.frame
        let visible = screen.visibleFrame
        let insets = screen.safeAreaInsets
        let minX = max(visible.minX, screenFrame.minX + insets.left)
        let maxX = min(visible.maxX, screenFrame.maxX - insets.right)
        let minY = max(visible.minY, screenFrame.minY + insets.bottom)
        let maxY = min(visible.maxY, screenFrame.maxY - insets.top)
        guard maxX > minX, maxY > minY else { return bounds }

        let safeScreenRect = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let safeWindowRect = window.convertFromScreen(safeScreenRect)
        let safeViewRect = convert(safeWindowRect, from: nil).intersection(bounds)
        return safeViewRect.isNull || safeViewRect.isEmpty ? bounds : safeViewRect
    }

    private enum Edge {
        case left
        case right
        case top
        case bottom
    }

    private func jumpToSpot(_ number: Int) {
        guard (1...9).contains(number) else { return }
        snappedSelection = nil
        let column = CGFloat((number - 1) % 3)
        let rowFromTop = CGFloat((number - 1) / 3)
        cursor.x = bounds.width * column / 2
        cursor.y = bounds.height * (2 - rowFromTop) / 2
        needsDisplay = true
    }

    private func jumpToEdge(_ edge: Edge) {
        snappedSelection = nil
        switch edge {
        case .left: cursor.x = 0
        case .right: cursor.x = bounds.width
        case .top: cursor.y = bounds.height
        case .bottom: cursor.y = 0
        }
        needsDisplay = true
    }

    private func swapCorners() {
        guard let anchor else {
            NSSound.beep()
            return
        }
        self.anchor = cursor
        cursor = anchor
        snappedSelection = nil
        needsDisplay = true
    }

    private func move(dx: CGFloat, dy: CGFloat) {
        snappedSelection = nil
        cursor.x = min(max(cursor.x + dx, 0), bounds.width)
        cursor.y = min(max(cursor.y + dy, 0), bounds.height)
        needsDisplay = true
    }

    private func confirm(mode: CaptureMode) {
        if let snappedSelection {
            onFinish?(CGRect(
                x: snappedSelection.minX + frame.minX,
                y: snappedSelection.minY + frame.minY,
                width: snappedSelection.width,
                height: snappedSelection.height
            ), mode)
            return
        }
        if anchor == nil {
            anchor = cursor
            needsDisplay = true
        } else {
            onFinish?(CGRect(
                x: min(anchor!.x, cursor.x) + frame.minX,
                y: min(anchor!.y, cursor.y) + frame.minY,
                width: abs(cursor.x - anchor!.x),
                height: abs(cursor.y - anchor!.y)
            ), mode)
        }
    }

    private func reset() {
        anchor = nil
        snappedSelection = nil
        needsDisplay = true
    }
}

@main
struct VimshotMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}
