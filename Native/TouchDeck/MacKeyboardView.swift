import SwiftUI

/// Compact US ANSI layout; each main row occupies exactly 15 key units.
struct MacKeyboardView: View {
    let modifiers: Set<String>
    let onKey: (String, Bool) -> Void
    let onModifier: (String) -> Void
    @State private var capsLock = false

    private struct Key: Identifiable {
        let code: String
        let label: String
        var shifted: String = ""
        var units: CGFloat = 1
        var modifier: Bool = false
        var id: String { code }
    }
    private var functionRow: [Key] {
        [Key(code: "escape", label: "esc", units: 1.5)] +
        (1...12).map { Key(code: "f\($0)", label: "F\($0)") } +
        [Key(code: "forward_delete", label: "⌦", units: 1.5)]
    }
    private var numberRow: [Key] {
        zip(Array("`1234567890-="), Array("~!@#$%^&*()_+")).map {
            Key(code: String($0.0), label: String($0.0), shifted: String($0.1))
        } + [Key(code: "delete", label: "delete", units: 2)]
    }
    private func letters(_ text: String) -> [Key] {
        text.map { Key(code: String($0), label: String($0).uppercased()) }
    }
    private var upperRow: [Key] {
        [Key(code: "tab", label: "tab", units: 1.5)] + letters("qwertyuiop") +
        [Key(code: "[", label: "[", shifted: "{"), Key(code: "]", label: "]", shifted: "}"),
         Key(code: "\\", label: "\\", shifted: "|", units: 1.5)]
    }
    private var homeRow: [Key] {
        [Key(code: "caps", label: "caps lock", units: 1.75)] + letters("asdfghjkl") +
        [Key(code: ";", label: ";", shifted: ":"), Key(code: "'", label: "'", shifted: "\""),
         Key(code: "return", label: "return", units: 2.25)]
    }
    private var lowerRow: [Key] {
        [Key(code: "shift", label: "⇧ shift", units: 2.25, modifier: true)] + letters("zxcvbnm") +
        [Key(code: ",", label: ",", shifted: "<"), Key(code: ".", label: ".", shifted: ">"),
         Key(code: "/", label: "/", shifted: "?"),
         Key(code: "right_shift", label: "shift ⇧", units: 2.75, modifier: true)]
    }
    private var bottomRow: [Key] {
        [Key(code: "fn", label: "fn"),
         Key(code: "control", label: "⌃", modifier: true),
         Key(code: "option", label: "⌥", modifier: true),
         Key(code: "command", label: "⌘", units: 1.25, modifier: true),
         Key(code: "space", label: "", units: 5.5),
         Key(code: "right_command", label: "⌘", units: 1.25, modifier: true),
         Key(code: "right_option", label: "⌥", modifier: true)]
    }

    var body: some View {
        GeometryReader { geometry in
            let gap: CGFloat = geometry.size.width < 800 ? 5 : 7
            let unit = (geometry.size.width - 14 * gap) / 15
            let height = max(26, min(unit * 1.25, (geometry.size.height - 65 - 5 * gap) / 5.65))
            VStack(spacing: 14) {
                HStack {
                    Text("MAC KEYBOARD · US ANSI")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                    Spacer()
                    Text("Tap modifiers to latch · Shift applies to the next key")
                        .font(.system(size: 10))
                }.foregroundStyle(.secondary)
                VStack(spacing: gap) {
                    row(functionRow, unit: unit, gap: gap, height: height * 0.65)
                    row(numberRow, unit: unit, gap: gap, height: height)
                    row(upperRow, unit: unit, gap: gap, height: height)
                    row(homeRow, unit: unit, gap: gap, height: height)
                    row(lowerRow, unit: unit, gap: gap, height: height)
                    HStack(spacing: gap) {
                        ForEach(bottomRow) { key in cap(key, unit: unit, gap: gap, height: height) }
                        arrows(unit: unit, gap: gap, height: height)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func row(_ keys: [Key], unit: CGFloat, gap: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: gap) {
            ForEach(keys) { key in cap(key, unit: unit, gap: gap, height: height) }
        }
    }

    private func modifierName(_ code: String) -> String {
        code.replacingOccurrences(of: "right_", with: "")
    }

    private func cap(_ key: Key, unit: CGFloat, gap: CGFloat, height: CGFloat) -> some View {
        let selected = key.code == "caps" ? capsLock : (key.modifier && modifiers.contains(modifierName(key.code)))
        return Button {
            if key.code == "caps" { capsLock.toggle() }
            else if key.modifier { onModifier(modifierName(key.code)) }
            else { onKey(key.code, capsLock) }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(selected ? Color(red: 0.21, green: 0.28, blue: 0.13) : Color(white: 0.14))
                RoundedRectangle(cornerRadius: 7)
                    .stroke(selected ? Color.green.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1)
                VStack(spacing: max(2, height * 0.05)) {
                    if !key.shifted.isEmpty {
                        Text(key.shifted)
                            .font(.system(size: min(16, unit * 0.28)))
                            .foregroundStyle(modifiers.contains("shift") ? .white : .gray)
                    }
                    Text(key.label)
                        .font(.system(size: key.label.count > 2 ? min(12, unit * 0.23) : min(22, unit * 0.38), weight: .medium))
                }
                if key.code == "f" || key.code == "j" {
                    Capsule().fill(Color.white.opacity(0.32))
                        .frame(width: 10, height: 2).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 6)
                }
                if key.code == "caps" {
                    Circle().fill(capsLock ? Color.green : Color.gray.opacity(0.35)).frame(width: 4, height: 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(8)
                }
            }
            .foregroundStyle(selected ? Color(red: 0.77, green: 0.94, blue: 0.35) : .white)
            .frame(width: unit * key.units + gap * (key.units - 1), height: height)
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(PhysicalKeyStyle())
        .accessibilityLabel(key.code == "space" ? "Space" : key.code.replacingOccurrences(of: "_", with: " "))
        .accessibilityValue(selected ? "On" : "")
    }

    private func arrows(unit: CGFloat, gap: CGFloat, height: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: gap) {
            cap(Key(code: "left", label: "←"), unit: unit, gap: gap, height: (height-gap)/2)
            VStack(spacing: gap) {
                cap(Key(code: "up", label: "↑"), unit: unit, gap: gap, height: (height-gap)/2)
                cap(Key(code: "down", label: "↓"), unit: unit, gap: gap, height: (height-gap)/2)
            }
            cap(Key(code: "right", label: "→"), unit: unit, gap: gap, height: (height-gap)/2)
        }.frame(height: height)
    }
}

private struct PhysicalKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? 0.13 : 0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
