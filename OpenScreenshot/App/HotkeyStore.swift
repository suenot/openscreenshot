import AppKit
import Carbon

/// Persisted hotkey configuration.
struct HotkeyConfig: Codable, Equatable {
    var keyCode: Int64       // CGKeyCode value
    var modifiers: UInt64    // CGEventFlags rawValue (only mask bits)

    static let `default` = HotkeyConfig(keyCode: 22, modifiers: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue)

    private static let key = "hotkeyConfig"

    static func load() -> HotkeyConfig {
        guard let data = UserDefaults.standard.data(forKey: key),
              let cfg = try? JSONDecoder().decode(HotkeyConfig.self, from: data) else {
            return .default
        }
        return cfg
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: HotkeyConfig.key)
        }
    }

    /// Human-readable string like "⌘⇧6"
    var displayString: String {
        let flags = CGEventFlags(rawValue: modifiers)
        var s = ""
        if flags.contains(.maskControl)  { s += "⌃" }
        if flags.contains(.maskAlternate) { s += "⌥" }
        if flags.contains(.maskShift)    { s += "⇧" }
        if flags.contains(.maskCommand)  { s += "⌘" }
        s += keyCodeToChar(Int(keyCode))
        return s
    }

    private func keyCodeToChar(_ kc: Int) -> String {
        let map: [Int: String] = [
            0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",
            11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",
            18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",
            24:"=",25:"9",26:"7",27:"-",28:"8",29:"0",
            30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",
            37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",
            43:",",44:"/",45:"N",46:"M",47:".",
            50:"`",
            36:"↩",48:"⇥",49:"Space",51:"⌫",53:"Esc",
            123:"←",124:"→",125:"↓",126:"↑",
        ]
        return map[kc] ?? "(\(kc))"
    }
}

/// Panel for recording a new hotkey.
class HotkeyRecorderPanel: NSPanel {
    var onRecord: ((HotkeyConfig) -> Void)?
    private var monitor: Any?
    private let label = NSTextField(labelWithString: "Press new shortcut…")

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 280, height: 90),
                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        self.title = "Set Hotkey"
        self.isReleasedWhenClosed = false
        label.alignment = .center
        label.font = .systemFont(ofSize: 14)
        let box = NSView()
        box.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: box.centerYAnchor),
        ])
        self.contentView = box
    }

    func startRecording() {
        label.stringValue = "Press new shortcut…"
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Require at least one modifier
            guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option) else {
                self.label.stringValue = "Need ⌘/⌃/⌥ modifier"
                return nil
            }
            var cgFlags: UInt64 = 0
            if flags.contains(.command)  { cgFlags |= CGEventFlags.maskCommand.rawValue }
            if flags.contains(.shift)    { cgFlags |= CGEventFlags.maskShift.rawValue }
            if flags.contains(.control)  { cgFlags |= CGEventFlags.maskControl.rawValue }
            if flags.contains(.option)   { cgFlags |= CGEventFlags.maskAlternate.rawValue }

            let cfg = HotkeyConfig(keyCode: Int64(event.keyCode), modifiers: cgFlags)
            self.label.stringValue = "Recorded: \(cfg.displayString)"
            self.stopRecording()
            self.onRecord?(cfg)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.close() }
            return nil
        }
    }

    func stopRecording() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    override func close() {
        stopRecording()
        super.close()
    }
}
