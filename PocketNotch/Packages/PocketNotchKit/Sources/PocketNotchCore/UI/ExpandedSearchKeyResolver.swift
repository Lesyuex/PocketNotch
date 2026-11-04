import AppKit

/// 把展开页搜索场景下的 keyDown 事件解析为搜索动作。
///
/// 仅当修饰键为空（或仅 Shift/CapsLock/小键盘）时才消费按键；
/// 带 Command/Control/Option 的组合键一律放行，交给系统快捷键处理。
enum ExpandedSearchKeyResolver {
    enum Action: Equatable {
        case insert(Character)
        case deleteBackward
        case clear
        case submit
        case paste
        case ignored
    }

    static func resolve(
        characters: Character?,
        charactersIgnoringModifiers: Character?,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> Action {
        let flags = modifiers
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.shift, .capsLock, .numericPad, .function])

        if flags == .command {
            return charactersIgnoringModifiers == "v" ? .paste : .ignored
        }
        guard flags.isEmpty else { return .ignored }

        switch keyCode {
        case 36, 76:
            return .submit
        case 53:
            return .clear
        case 51:
            return .deleteBackward
        default:
            break
        }

        guard let character = characters, let scalar = character.unicodeScalars.first else {
            return .ignored
        }
        guard scalar.value >= 0x20, !(0xF700...0xF8FF).contains(scalar.value) else {
            return .ignored
        }
        return .insert(character)
    }
}