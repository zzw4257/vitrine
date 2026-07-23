import SwiftUI
import Observation

// MARK: - Model

/// A rebindable command. `key` is a single character; modifiers is a raw bitset we can persist.
struct Keybinding: Codable, Hashable {
    var key: String            // "1", "r", "," …
    var modifiers: Int         // EventModifiers rawValue

    var eventModifiers: EventModifiers { EventModifiers(rawValue: modifiers) }
    var keyEquivalent: KeyEquivalent { KeyEquivalent(Character(key.isEmpty ? "?" : key)) }

    var display: String {
        var s = ""
        let m = eventModifiers
        if m.contains(.control) { s += "⌃" }
        if m.contains(.option) { s += "⌥" }
        if m.contains(.shift) { s += "⇧" }
        if m.contains(.command) { s += "⌘" }
        let label: String
        switch key {
        case ",": label = ","
        case " ": label = "Space"
        default: label = key.uppercased()
        }
        return s + label
    }
}

enum KeyAction: String, CaseIterable, Identifiable {
    case dashboard, projects, search, memory, distillery, dispatch, pinned, refresh, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "跳转 · 总览"
        case .projects: "跳转 · 项目"
        case .search: "跳转 · 检索"
        case .memory: "跳转 · 记忆工坊"
        case .distillery: "跳转 · 技能蒸馏"
        case .dispatch: "跳转 · 任务调配"
        case .pinned: "跳转 · 已置顶"
        case .refresh: "重新扫描"
        case .settings: "打开设置"
        }
    }

    var section: Section? {
        switch self {
        case .dashboard: .dashboard
        case .projects: .projects
        case .search: .search
        case .memory: .memory
        case .distillery: .distillery
        case .dispatch: .dispatch
        case .pinned: .pinned
        default: nil
        }
    }

    var defaultBinding: Keybinding {
        let cmd = EventModifiers.command.rawValue
        switch self {
        case .dashboard: return .init(key: "1", modifiers: cmd)
        case .projects: return .init(key: "2", modifiers: cmd)
        case .search: return .init(key: "3", modifiers: cmd)
        case .memory: return .init(key: "4", modifiers: cmd)
        case .distillery: return .init(key: "5", modifiers: cmd)
        case .dispatch: return .init(key: "6", modifiers: cmd)
        case .pinned: return .init(key: "7", modifiers: cmd)
        case .refresh: return .init(key: "r", modifiers: cmd)
        case .settings: return .init(key: ",", modifiers: cmd)
        }
    }
}

// MARK: - Manager

@Observable
final class KeybindingManager {
    static let shared = KeybindingManager()
    var bindings: [String: Keybinding]   // KeyAction.rawValue → binding

    func binding(_ a: KeyAction) -> Keybinding { bindings[a.rawValue] ?? a.defaultBinding }

    func set(_ a: KeyAction, _ b: Keybinding) {
        bindings[a.rawValue] = b
        persist()
    }

    func reset(_ a: KeyAction) {
        bindings[a.rawValue] = a.defaultBinding
        persist()
    }

    func resetAll() {
        bindings = Dictionary(uniqueKeysWithValues: KeyAction.allCases.map { ($0.rawValue, $0.defaultBinding) })
        persist()
    }

    /// Which other action currently holds the same chord (for conflict warnings).
    func conflict(_ a: KeyAction, _ b: Keybinding) -> KeyAction? {
        KeyAction.allCases.first { $0 != a && binding($0) == b && !b.key.isEmpty }
    }

    private static let storeKey = "vitrine.keybindings.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let dict = try? JSONDecoder().decode([String: Keybinding].self, from: data) {
            bindings = dict
        } else {
            bindings = Dictionary(uniqueKeysWithValues: KeyAction.allCases.map { ($0.rawValue, $0.defaultBinding) })
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(bindings) {
            UserDefaults.standard.set(data, forKey: Self.storeKey)
        }
    }
}
