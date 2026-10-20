import Foundation
import Combine

@MainActor
final class MacConnection: ObservableObject {
    enum State: Equatable {
        case disconnected, connecting, connected, failed(String)
    }

    @Published private(set) var state: State = .disconnected
    private var task: URLSessionWebSocketTask?
    private var writer: Task<Void, Never>?
    private let session = URLSession(configuration: .default)
    private var pointerSpeed = 1.0

    func setPointerSpeed(_ speed: Double) {
        pointerSpeed = speed.isFinite ? min(3, max(0.25, speed)) : 1
    }

    func connect(host: String, pin: String) {
        task?.cancel(with: .goingAway, reason: nil)
        writer?.cancel()
        state = .connecting
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^https?://", with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !cleanHost.isEmpty,
              let url = URL(string: "ws://\(cleanHost):8766") else {
            state = .failed("Enter the Mac’s IP address, shown in the companion window.")
            return
        }
        let connection = session.webSocketTask(with: url)
        task = connection
        connection.resume()
        enqueue(["action": "pair", "pin": pin], on: connection)
        receive(on: connection)
    }

    func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        writer?.cancel()
        writer = nil
        state = .disconnected
    }

    func move(dx: CGFloat, dy: CGFloat) {
        send(["action": "move", "dx": Double(dx) * pointerSpeed, "dy": Double(dy) * pointerSpeed])
    }

    func scroll(dx: CGFloat, dy: CGFloat) {
        send(["action": "scroll", "dx": Double(dx), "dy": Double(dy)])
    }

    func scrollState(_ phase: String) {
        send(["action": "scroll_state", "phase": phase])
    }

    func click(right: Bool = false) {
        send(["action": "click", "button": right ? "right" : "left"])
    }

    func mouseButton(down: Bool) {
        send(["action": "button", "down": down])
    }

    func releaseInput() {
        send(["action": "release"])
    }

    func key(_ key: String, down: Bool, modifiers: [String]) {
        send(["action": "key", "key": key, "down": down, "modifiers": modifiers])
    }

    func type(_ text: String) {
        guard !text.isEmpty else { return }
        send(["action": "text", "text": String(text.prefix(1000))])
    }

    private func send(_ message: [String: Any]) {
        guard let task, state == .connected else { return }
        enqueue(message, on: task)
    }

    private func enqueue(_ message: [String: Any], on connection: URLSessionWebSocketTask) {
        guard JSONSerialization.isValidJSONObject(message),
              let data = try? JSONSerialization.data(withJSONObject: message),
              let string = String(data: data, encoding: .utf8) else { return }
        let previous = writer
        writer = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, self.task === connection else { return }
            do {
                try await connection.send(.string(string))
            } catch {
                self.state = .failed("Could not send input to the Mac.")
            }
        }
    }

    private func receive(on connection: URLSessionWebSocketTask) {
        Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await connection.receive()
                    guard let self, self.task === connection else { return }
                    guard case .string(let string) = message,
                          let data = string.data(using: .utf8),
                          let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let type = payload["type"] as? String else { continue }
                    if type == "paired" {
                        self.state = .connected
                    } else if type == "error" {
                        self.state = .failed(payload["message"] as? String ?? "The Mac rejected the pairing code.")
                    }
                } catch {
                    guard let self, self.task === connection else { return }
                    self.task = nil
                    self.state = .failed("Connection closed. Check that the Mac companion is running.")
                    return
                }
            }
        }
    }
}
