import SwiftUI
import UIKit

struct TouchDeckView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var connection = MacConnection()
    @AppStorage("touchdeck.macHost") private var savedHost = ""
    @State private var host = ""
    @State private var pin = ""
    @State private var showPairing = true
    @State private var showFullKeys = true
    @AppStorage("touchdeck.mode") private var mode = "Combined"
    @AppStorage("touchdeck.pointerSpeed") private var pointerSpeed = 1.0
    @State private var showGestures = false
    @State private var gestureStatus = "1 finger: point · 2: scroll · 3: drag · 4: desktops"
    @State private var modifiers: Set<String> = []
    @State private var textToSend = ""

    private let rows = [Array("qwertyuiop"), Array("asdfghjkl"), Array("zxcvbnm")]

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                    .padding(.bottom, 16)

                Picker("Control mode", selection: $mode) {
                    ForEach(["Trackpad", "Combined", "Keyboard"], id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 14)

                if mode != "Keyboard" {
                    HStack {
                        label("TRACKPAD")
                        Spacer()
                        Button("Gesture guide") { showGestures = true }
                            .font(.system(size: 12)).foregroundStyle(DeckPalette.lime)
                    }.padding(.bottom, 8)
                    pointerSpeedControl.padding(.bottom, 10)
                    trackpad
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .frame(minHeight: 100)
                }
                if mode == "Keyboard" {
                    MacKeyboardView(modifiers: modifiers, onKey: tapPhysicalKey, onModifier: toggleModifier)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    shortcuts.padding(.top, 10).padding(.bottom, 10)
                    if mode == "Combined" {
                        keyboardPanel(keyHeight: geometry.size.height > 900 ? 37 : 30)
                    }
                }

                footer
                    .padding(.top, 11)
            }
            .padding(.horizontal, geometry.size.width > 800 ? 42 : 16)
            .padding(.top, 12)
            .padding(.bottom, 9)
            .frame(maxWidth: 1500, maxHeight: .infinity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DeckPalette.background.ignoresSafeArea())
            .overlay {
                if showPairing || !isConnected {
                    PairingCard(host: $host, pin: $pin, isPresented: $showPairing,
                                connection: connection, savedHost: $savedHost)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: showPairing)
            .defersSystemGestures(on: mode == "Keyboard" ? [] : .all)
            .sheet(isPresented: $showGestures) {
                NavigationStack {
                    List {
                        Label("One finger: move pointer; tap to click", systemImage: "hand.point.up.left")
                        Label("Hold one finger, then move: drag; lift to drop", systemImage: "hand.draw")
                        Label("Two fingers: scroll; tap to right-click", systemImage: "hand.point.up.braille")
                        Label("Pinch: zoom with Command + / − in compatible Mac apps", systemImage: "arrow.up.left.and.arrow.down.right")
                        Label("Three fingers: drag; lift to drop", systemImage: "hand.draw")
                        Label("Four fingers left / right: switch desktop", systemImage: "rectangle.split.3x1")
                        Label("Four fingers up: Mission Control; down: App Exposé", systemImage: "rectangle.3.group")
                        Text("Desktop gestures use macOS Control–Arrow shortcuts. Enable these shortcuts in macOS Keyboard settings if you have changed them.")
                            .foregroundStyle(.secondary)
                        Section("Test Mac actions") {
                            Button("Mission Control") { gestureShortcut("up") }
                            Button("App Exposé") { gestureShortcut("down") }
                            Button("Previous desktop") { gestureShortcut("left") }
                            Button("Next desktop") { gestureShortcut("right") }
                            Text("If these buttons work but a swipe does not, check the finger indicator on the trackpad. If neither works, check the Mac’s Control–Arrow shortcuts.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle("Gestures")
                    .toolbar { Button("Done") { showGestures = false } }
                }.preferredColorScheme(.dark)
            }
            .onChange(of: mode) { _, _ in
                connection.releaseInput()
                releaseModifiers()
            }
            .onChange(of: pointerSpeed) { _, speed in connection.setPointerSpeed(speed) }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    connection.releaseInput()
                    modifiers.removeAll()
                }
            }
            .onAppear {
                host = savedHost
                showPairing = !isConnected
                pointerSpeed = pointerSpeed.isFinite ? min(3, max(0.25, pointerSpeed)) : 1
                connection.setPointerSpeed(pointerSpeed)
            }
            .onChange(of: connection.state) { _, newState in
                if case .connected = newState {
                    savedHost = host
                    pin = ""
                    showPairing = false
                } else if case .failed = newState {
                    showPairing = true
                }
                if case .disconnected = newState { showPairing = true }
            }
        }
    }

    private var pointerSpeedControl: some View {
        HStack(spacing: 12) {
            Text("Pointer speed").font(.system(size: 12)).foregroundStyle(DeckPalette.secondary)
            Image(systemName: "tortoise").foregroundStyle(DeckPalette.muted)
            Slider(value: $pointerSpeed, in: 0.25...3, step: 0.05)
                .tint(DeckPalette.lime)
                .accessibilityLabel("Pointer speed")
                .accessibilityValue(String(format: "%.2f times", pointerSpeed))
            Image(systemName: "hare").foregroundStyle(DeckPalette.muted)
            Text(String(format: "%.2f×", pointerSpeed))
                .font(.system(size: 12, design: .monospaced))
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
            Button("Reset") { pointerSpeed = 1 }
                .font(.system(size: 12)).foregroundStyle(DeckPalette.lime)
                .accessibilityLabel("Reset pointer speed to one times")
        }
        .frame(minHeight: 32)
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 9) {
                BrandMark()
                    .frame(width: 20, height: 20)
                (Text("touch").fontWeight(.heavy) + Text("deck").foregroundColor(DeckPalette.muted))
                    .font(.system(size: 16, design: .rounded))
                    .tracking(-0.6)
            }
            Spacer()
            HStack(spacing: 8) {
                Circle().fill(isConnected ? DeckPalette.lime : DeckPalette.dim)
                    .frame(width: 7, height: 7)
                    .shadow(color: isConnected ? DeckPalette.lime.opacity(0.6) : .clear, radius: 6)
                Text(isConnected ? "CONNECTED" : "PAIR YOUR MAC")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(DeckPalette.secondary)
                Button { showPairing = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(DeckPalette.secondary)
                        .frame(width: 36, height: 34)
                }
                .accessibilityLabel("Connection settings")
            }
        }
        .frame(height: 42)
        .overlay(alignment: .bottom) { DeckPalette.line.frame(height: 1).offset(y: 9) }
    }

    private var trackpad: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(RadialGradient(colors: [DeckPalette.trackpad, DeckPalette.panel], center: .center, startRadius: 12, endRadius: 620))
            GridPattern().stroke(DeckPalette.paper.opacity(0.035), lineWidth: 0.7)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(1)
            VStack(spacing: 10) {
                ZStack {
                    Ellipse().stroke(DeckPalette.lime.opacity(0.11), lineWidth: 1).frame(width: 100, height: 62)
                    Ellipse().stroke(DeckPalette.lime.opacity(0.16), lineWidth: 1).frame(width: 72, height: 44)
                    Image(systemName: "arrow.up.left")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(DeckPalette.lime)
                        .shadow(color: DeckPalette.lime.opacity(0.35), radius: 15)
                }
                Text("GLIDE ANYWHERE")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.4).foregroundStyle(DeckPalette.paper.opacity(0.82))
                Text("ONE FINGER TO MOVE")
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .tracking(1).foregroundStyle(DeckPalette.muted)
            }
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(gestureStatus)
                        .font(.system(size: 8, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(DeckPalette.muted)
                        .padding(14)
                }
            }
            NativeTrackSurface(connection: connection) { gestureStatus = $0 }
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel("Trackpad. Move one finger, scroll with two, drag with three, swipe with four for desktops or Mission Control")
        }
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DeckPalette.line, lineWidth: 1).allowsHitTesting(false))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    private var shortcuts: some View {
        HStack(spacing: 7) {
            shortcut("⎋", "ESC") { tapKey("escape") }
            shortcut("⇥", "TAB") { tapKey("tab") }
            shortcut("▤", "MISSION") { gestureShortcut("up") }
            shortcut("⌘", "DESKTOP") { tapKey("f11") }
            shortcut("⌨", mode == "Trackpad" ? "TYPE" : "KEYS", highlighted: mode != "Trackpad") {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if mode == "Trackpad" { mode = "Keyboard" }
                    else if mode == "Keyboard" { mode = "Trackpad" }
                    else { showFullKeys.toggle() }
                }
            }
        }
        .frame(height: 50)
    }

    private func keyboardPanel(keyHeight: CGFloat) -> some View {
        VStack(spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                label("QUICK KEYS")
                Text("Shortcuts, symbols & words")
                    .font(.system(size: 10))
                    .foregroundStyle(DeckPalette.muted)
                Spacer()
                Image(systemName: "keyboard")
                    .font(.system(size: 13))
                    .foregroundStyle(DeckPalette.secondary)
            }

            HStack(spacing: 6) {
                keycap("←", key: "left")
                keycap("↓", key: "down")
                keycap("↑", key: "up")
                keycap("→", key: "right")
                Rectangle().fill(DeckPalette.line).frame(width: 1, height: 22).padding(.horizontal, 3)
                keycap("⌫", key: "delete")
                keycap("↵", key: "return")
                keycap("SPACE", key: "space", wide: true, small: true)
            }
            if showFullKeys || mode == "Keyboard" {
                if mode == "Keyboard" {
                    keyboardRow(Array("1234567890-="), height: keyHeight)
                }
                VStack(spacing: 5) {
                    keyboardRow(rows[0], height: keyHeight)
                    keyboardRow(rows[1], height: keyHeight, inset: 0.045)
                    HStack(spacing: 5) {
                        modifierKey("⇧", name: "shift", caption: nil, wide: true)
                        ForEach(rows[2], id: \.self) { key in keycap(String(key).uppercased(), key: String(key), height: keyHeight) }
                        keycap(",", key: ",", height: keyHeight)
                        keycap(".", key: ".", height: keyHeight)
                        keycap("⌫", key: "delete", height: keyHeight, wide: true)
                    }
                }
            }
            HStack(spacing: 6) {
                modifierKey("⌃", name: "control", caption: "CTRL")
                modifierKey("⌥", name: "option", caption: "OPT")
                modifierKey("⇧", name: "shift", caption: "SHIFT")
                modifierKey("⌘", name: "command", caption: "CMD", emphasized: true)
            }
            HStack(spacing: 8) {
                Image(systemName: "arrow.turn.down.right").foregroundStyle(DeckPalette.lime)
                TextField("Type a message or search…", text: $textToSend)
                    .font(.system(size: 12))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .onSubmit(sendText)
                Rectangle().fill(DeckPalette.line).frame(width: 1).padding(.vertical, 5)
                Button(action: sendText) {
                    HStack(spacing: 5) {
                        Text("SEND").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(0.7)
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(DeckPalette.lime)
                    .padding(.horizontal, 9)
                    .frame(height: 38)
                }
            }
            .padding(.leading, 12)
            .frame(height: 40)
            .background(DeckPalette.panel, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(DeckPalette.line, lineWidth: 1))
        }
        .padding(.top, 12)
        .overlay(alignment: .top) { DeckPalette.line.frame(height: 1) }
    }

    private func keyboardRow(_ row: [Character], height: CGFloat, inset: CGFloat = 0) -> some View {
        HStack(spacing: 5) {
            ForEach(row, id: \.self) { key in keycap(String(key).uppercased(), key: String(key), height: height) }
        }
        .padding(.horizontal, inset * 300)
    }

    private func keycap(_ title: String, key: String, height: CGFloat = 39, wide: Bool = false, small: Bool = false) -> some View {
        Button { tapKey(key) } label: {
            Text(title)
                .font(.system(size: small ? 8 : 14, weight: .medium, design: small ? .monospaced : .rounded))
                .tracking(small ? 0.8 : 0)
                .foregroundStyle(DeckPalette.paper.opacity(0.92))
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(DeckPalette.key, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(DeckPalette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: wide ? .infinity : nil)
        .layoutPriority(wide ? 2 : 0)
    }

    private func modifierKey(_ symbol: String, name: String, caption: String?, wide: Bool = false, emphasized: Bool = false) -> some View {
        let active = modifiers.contains(name)
        return Button { toggleModifier(name) } label: {
            HStack(spacing: 5) {
                Text(symbol).font(.system(size: 15, weight: .medium))
                if let caption { Text(caption).font(.system(size: 8, weight: .medium, design: .monospaced)) }
            }
            .foregroundStyle(active ? DeckPalette.lime : DeckPalette.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(active ? DeckPalette.activeKey : (emphasized ? DeckPalette.commandKey : DeckPalette.key), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(active ? DeckPalette.lime.opacity(0.45) : DeckPalette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .layoutPriority(wide ? 2 : 0)
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Circle().fill(DeckPalette.lime.opacity(0.7)).frame(width: 5, height: 5)
            Text("PRIVATE LOCAL CONNECTION")
            Spacer()
            Text("BUILT FOR THE BIG SCREEN")
            Text("✳").font(.system(size: 12)).foregroundStyle(DeckPalette.lime)
        }
        .font(.system(size: 8, weight: .regular, design: .monospaced))
        .tracking(0.5)
        .foregroundStyle(DeckPalette.muted)
    }

    private var isConnected: Bool { if case .connected = connection.state { return true }; return false }

    private func label(_ title: String) -> some View {
        Text(title).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.5).foregroundStyle(DeckPalette.secondary)
    }

    private func shortcut(_ symbol: String, _ title: String, highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(symbol).font(.system(size: 14, weight: .regular))
                Text(title).font(.system(size: 8, weight: .medium)).tracking(0.5)
            }
            .foregroundStyle(highlighted ? DeckPalette.lime : DeckPalette.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(highlighted ? DeckPalette.activeKey : DeckPalette.panel, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(highlighted ? DeckPalette.activeKey : DeckPalette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func releaseModifiers() {
        for name in modifiers { connection.key(name, down: false, modifiers: []) }
        modifiers.removeAll()
    }

    private func gestureShortcut(_ key: String) {
        connection.key(key, down: true, modifiers: ["control"])
        connection.key(key, down: false, modifiers: ["control"])
    }

    private func toggleModifier(_ name: String) {
        if modifiers.contains(name) {
            modifiers.remove(name)
            connection.key(name, down: false, modifiers: Array(modifiers))
        } else {
            modifiers.insert(name)
            connection.key(name, down: true, modifiers: Array(modifiers))
        }
    }

    private func tapPhysicalKey(_ key: String, capsLock: Bool) {
        var flags = modifiers
        if capsLock && key.count == 1 && key.first?.isLetter == true {
            if flags.contains("shift") { flags.remove("shift") } else { flags.insert("shift") }
        }
        connection.key(key, down: true, modifiers: Array(flags))
        connection.key(key, down: false, modifiers: Array(flags))
        if modifiers.contains("shift") { toggleModifier("shift") }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.35)
    }

    private func tapKey(_ key: String) {
        connection.key(key, down: true, modifiers: Array(modifiers))
        connection.key(key, down: false, modifiers: Array(modifiers))
        if modifiers.contains("shift") { toggleModifier("shift") }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.35)
    }

    private func sendText() {
        connection.type(textToSend)
        textToSend = ""
    }
}

private struct PairingCard: View {
    @Binding var host: String
    @Binding var pin: String
    @Binding var isPresented: Bool
    @ObservedObject var connection: MacConnection
    @Binding var savedHost: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.73).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    BrandMark().frame(width: 29, height: 29)
                    Spacer()
                    if case .connected = connection.state {
                        Button { isPresented = false } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(DeckPalette.secondary)
                                .frame(width: 34, height: 34)
                                .background(DeckPalette.key, in: Circle())
                        }
                        .accessibilityLabel("Close connection settings")
                    }
                }
                .padding(.bottom, 20)
                Text("WELCOME TO TOUCHDECK")
                    .font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1.4)
                    .foregroundStyle(DeckPalette.lime).padding(.bottom, 12)
                Text("Your Mac,\nat your fingertips.")
                    .font(.system(size: 31, weight: .semibold, design: .rounded))
                    .tracking(-1.1).lineSpacing(-1)
                    .foregroundStyle(DeckPalette.paper).padding(.bottom, 12)
                Text("Enter the Mac address and six-digit code shown in the TouchDeck companion. Both devices should be on the same Wi-Fi.")
                    .font(.system(size: 12)).lineSpacing(4)
                    .foregroundStyle(DeckPalette.secondary).padding(.bottom, 20)

                Text("MAC ADDRESS").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1)
                    .foregroundStyle(DeckPalette.secondary).padding(.bottom, 7)
                TextField("192.168.1.24", text: $host)
                    .font(.system(size: 15, design: .monospaced))
                    .keyboardType(.decimalPad).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(.horizontal, 13).frame(height: 46)
                    .background(DeckPalette.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(DeckPalette.line, lineWidth: 1))
                    .padding(.bottom, 13)

                HStack {
                    Text("PAIRING CODE").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1)
                        .foregroundStyle(DeckPalette.secondary)
                    Spacer()
                    Text("6 DIGITS").font(.system(size: 8, design: .monospaced)).tracking(0.8).foregroundStyle(DeckPalette.muted)
                }.padding(.bottom, 7)
                TextField("······", text: $pin)
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                    .keyboardType(.numberPad).multilineTextAlignment(.center)
                    .tint(DeckPalette.lime)
                    .onChange(of: pin) { _, value in pin = String(value.filter(\.isNumber).prefix(6)) }
                    .padding(.horizontal, 13).frame(height: 49)
                    .background(DeckPalette.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(DeckPalette.line, lineWidth: 1))

                Button {
                    savedHost = host
                    connection.connect(host: host, pin: pin)
                } label: {
                    HStack(spacing: 8) {
                        Text("CONNECT TO MAC")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(0.8)
                    .foregroundStyle(DeckPalette.background)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(DeckPalette.lime, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain).padding(.top, 12)

                if case .failed(let message) = connection.state {
                    Text(message).font(.system(size: 10)).foregroundStyle(Color(red: 0.93, green: 0.57, blue: 0.46))
                        .frame(maxWidth: .infinity).padding(.top, 9)
                }
                HStack(spacing: 5) {
                    Image(systemName: "lock.shield").foregroundStyle(DeckPalette.lime)
                    Text("Your pairing code stays on your local network.")
                }
                .font(.system(size: 9)).foregroundStyle(DeckPalette.muted)
                .frame(maxWidth: .infinity).padding(.top, 16)
                .overlay(alignment: .top) { DeckPalette.line.frame(height: 1) }
            }
            .padding(26)
            .frame(maxWidth: 440)
            .background(DeckPalette.panel, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(DeckPalette.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 35, y: 15)
            .padding(22)
        }
    }
}

private struct BrandMark: View {
    var body: some View {
        GeometryReader { geometry in
            let gap = geometry.size.width * 0.09
            let side = (geometry.size.width - gap) / 2
            LazyVGrid(columns: [GridItem(.fixed(side), spacing: gap), GridItem(.fixed(side), spacing: 0)], spacing: gap) {
                ForEach(0..<4) { index in
                    RoundedRectangle(cornerRadius: side * 0.16)
                        .fill(DeckPalette.lime.opacity([1, 0.65, 0.78, 0.4][index]))
                        .frame(width: side, height: side)
                }
            }
            .rotationEffect(.degrees(-8))
        }
    }
}

private struct GridPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        stride(from: CGFloat(0), through: rect.width, by: 52).forEach { x in
            path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: rect.height))
        }
        stride(from: CGFloat(0), through: rect.height, by: 52).forEach { y in
            path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        return path
    }
}

private enum DeckPalette {
    static let background = Color(red: 0.063, green: 0.067, blue: 0.067)
    static let panel = Color(red: 0.09, green: 0.102, blue: 0.098)
    static let trackpad = Color(red: 0.125, green: 0.145, blue: 0.137)
    static let key = Color(red: 0.125, green: 0.137, blue: 0.133)
    static let commandKey = Color(red: 0.145, green: 0.16, blue: 0.12)
    static let activeKey = Color(red: 0.18, green: 0.22, blue: 0.13)
    static let line = Color(red: 0.17, green: 0.19, blue: 0.18)
    static let paper = Color(red: 0.95, green: 0.95, blue: 0.91)
    static let secondary = Color(red: 0.68, green: 0.72, blue: 0.68)
    static let muted = Color(red: 0.44, green: 0.48, blue: 0.45)
    static let dim = Color(red: 0.35, green: 0.39, blue: 0.36)
    static let lime = Color(red: 0.77, green: 0.94, blue: 0.35)
}
