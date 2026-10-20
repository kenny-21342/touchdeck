#!/usr/bin/env python3
"""TouchDeck Mac companion: local web UI + paired WebSocket input bridge."""
from __future__ import annotations

import asyncio
import json
import ipaddress
import math
import secrets
import socket
import subprocess
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import Quartz
import websockets

ROOT = Path(__file__).parent / "static"
WEB_PORT = 8765
SOCKET_PORT = 8766
PIN = f"{secrets.randbelow(1_000_000):06d}"
ACCESS_MESSAGE = (
    "Mac input permission is missing. On the Mac, open System Settings → "
    "Privacy & Security → Accessibility and enable Terminal (or Python). "
    "Then reconnect. If needed, restart the Mac companion."
)

KEY_CODES = {
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6,
    "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14,
    "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20,
    "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
    "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32,
    "[": 33, "i": 34, "p": 35, "return": 36, "l": 37, "j": 38,
    "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
    "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49,
    "`": 50, "delete": 51, "escape": 53, "command": 55,
    "shift": 56, "caps": 57, "option": 58, "control": 59,
    "right_shift": 60, "right_option": 61, "right_control": 62,
    "fn": 63, "f17": 64, "keypad_decimal": 65, "keypad_multiply": 67,
    "keypad_plus": 69, "keypad_clear": 71, "volume_up": 72,
    "volume_down": 73, "mute": 74, "keypad_divide": 75,
    "keypad_enter": 76, "keypad_minus": 78, "f18": 79, "f19": 80,
    "keypad_equals": 81, "keypad0": 82, "keypad1": 83, "keypad2": 84,
    "keypad3": 85, "keypad4": 86, "keypad5": 87, "keypad6": 88,
    "keypad7": 89, "f20": 90, "keypad8": 91, "keypad9": 92,
    "f5": 96, "f6": 97, "f7": 98, "f3": 99, "f8": 100,
    "f9": 101, "f11": 103, "f13": 105, "f16": 106, "f14": 107,
    "f10": 109, "f12": 111, "f15": 113, "help": 114, "home": 115,
    "pageup": 116, "forward_delete": 117, "f4": 118, "end": 119,
    "f2": 120, "pagedown": 121, "f1": 122, "left": 123,
    "right": 124, "down": 125, "up": 126,
}


def post_mouse(kind: str, button: str = "left", x: float | None = None, y: float | None = None, dragging: bool = False):
    current = Quartz.CGEventGetLocation(Quartz.CGEventCreate(None))
    bounds = Quartz.CGDisplayBounds(Quartz.CGMainDisplayID())
    px = max(bounds.origin.x, min(bounds.origin.x + bounds.size.width - 1, (x if x is not None else current.x)))
    py = max(bounds.origin.y, min(bounds.origin.y + bounds.size.height - 1, (y if y is not None else current.y)))
    point = Quartz.CGPointMake(px, py)
    if kind == "move":
        event = Quartz.CGEventCreateMouseEvent(None, (Quartz.kCGEventLeftMouseDragged if dragging else Quartz.kCGEventMouseMoved), point, Quartz.kCGMouseButtonLeft)
    elif kind in ("down", "up"):
        btn = Quartz.kCGMouseButtonRight if button == "right" else Quartz.kCGMouseButtonLeft
        event_type = (Quartz.kCGEventRightMouseDown if kind == "down" else Quartz.kCGEventRightMouseUp) if button == "right" else (Quartz.kCGEventLeftMouseDown if kind == "down" else Quartz.kCGEventLeftMouseUp)
        event = Quartz.CGEventCreateMouseEvent(None, event_type, point, btn)
    else:
        return
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)


def post_key(key: str, down: bool, modifiers: list[str] | None = None):
    key = key.lower()
    code = KEY_CODES.get(key)
    if code is None:
        return
    event = Quartz.CGEventCreateKeyboardEvent(None, code, down)
    # macOS symbolic shortcuts distinguish navigation/function-key events
    # from ordinary character keys. Preserve that identity when adding modifiers.
    flags = (Quartz.kCGEventFlagMaskSecondaryFn
             if key in {"left", "right", "up", "down", "home", "end", "pageup", "pagedown", "forward_delete"}
             or (key.startswith("f") and key[1:].isdigit()) else 0)
    for mod in modifiers or []:
        flags |= {"shift": Quartz.kCGEventFlagMaskShift,
                  "control": Quartz.kCGEventFlagMaskControl,
                  "option": Quartz.kCGEventFlagMaskAlternate,
                  "command": Quartz.kCGEventFlagMaskCommand,
                  "fn": Quartz.kCGEventFlagMaskSecondaryFn}.get(mod, 0)
    Quartz.CGEventSetFlags(event, flags)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)


def type_text(value: str):
    # Unicode keyboard events preserve non-ASCII text and use the active Mac input source.
    for character in value:
        length = len(character.encode("utf-16-le")) // 2
        down = Quartz.CGEventCreateKeyboardEvent(None, 0, True)
        Quartz.CGEventKeyboardSetUnicodeString(down, length, character)
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, down)
        up = Quartz.CGEventCreateKeyboardEvent(None, 0, False)
        Quartz.CGEventKeyboardSetUnicodeString(up, length, character)
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, up)


class SmoothScroll:
    """Resample touch deltas locally, preserving fractions and adding flick inertia."""
    def __init__(self):
        self.task = None
        self.stop()

    def stop(self):
        if self.task:
            self.task.cancel()
        self.task = None
        self.pending = [0.0, 0.0]
        self.velocity = [0.0, 0.0]
        self.remainder = [0.0, 0.0]
        self.last_input = 0.0
        self.coasting = False

    def feed(self, dx, dy):
        values = [-float(dx), -float(dy)]  # Reverse both axes.
        if not all(math.isfinite(value) for value in values):
            raise ValueError("Non-finite scroll delta")
        now = asyncio.get_running_loop().time()
        elapsed = now - self.last_input
        dt = min(0.05, max(1 / 240, elapsed)) if self.last_input else 1 / 60
        if elapsed > 0.12:
            self.velocity = [0.0, 0.0]
        self.coasting = False
        for axis, value in enumerate(values):
            value = max(-500, min(500, value))
            if value * self.pending[axis] < 0:
                self.pending[axis] = 0
                self.velocity[axis] = 0
                self.remainder[axis] = 0
            self.pending[axis] += value
            self.velocity[axis] = 0.65 * self.velocity[axis] + 0.35 * value / dt
        self.last_input = now
        self.start()

    def end(self):
        # Holding still before lifting should not launch a stale flick.
        if asyncio.get_running_loop().time() - self.last_input < 0.10:
            self.velocity = [max(-2200, min(2200, v)) for v in self.velocity]
            self.coasting = True
            self.start()

    def start(self):
        if self.task is None or self.task.done():
            self.task = asyncio.create_task(self.run())

    async def run(self):
        loop = asyncio.get_running_loop()
        previous = loop.time()
        while True:
            await asyncio.sleep(1 / 120)
            now = loop.time()
            dt = min(0.04, now - previous)
            previous = now
            if not Quartz.CGPreflightPostEventAccess():
                self.stop()
                return
            blend = 1 - math.exp(-dt / 0.035)
            decay = math.exp(-dt / 0.20)
            pixels = []
            for axis in range(2):
                step = self.pending[axis] * blend
                self.pending[axis] -= step
                if self.coasting:
                    step += self.velocity[axis] * 0.20 * (1 - decay)
                    self.velocity[axis] *= decay
                self.remainder[axis] += step
                pixel = math.trunc(self.remainder[axis])
                self.remainder[axis] -= pixel
                pixels.append(pixel)
            if any(pixels):
                event = Quartz.CGEventCreateScrollWheelEvent(
                    None, Quartz.kCGScrollEventUnitPixel, 2, pixels[1], pixels[0])
                Quartz.CGEventSetIntegerValueField(event, Quartz.kCGScrollWheelEventIsContinuous, 1)
                Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)
            if max(map(abs, self.pending)) < 0.1 and (
                not self.coasting or max(map(abs, self.velocity)) < 2
            ):
                return


async def handle_client(ws):
    paired = False
    dragging = False
    held_keys = set()
    scrolling = SmoothScroll()
    try:
        async for raw in ws:
            try:
                message = json.loads(raw)
                action = message.get("action")
                if action == "pair":
                    if secrets.compare_digest(str(message.get("pin", "")), PIN):
                        if not Quartz.CGPreflightPostEventAccess():
                            print("  Pairing blocked: Accessibility permission is missing.", flush=True)
                            await ws.send(json.dumps({"type": "error", "message": ACCESS_MESSAGE}))
                            continue
                        paired = True
                        await ws.send(json.dumps({"type": "paired", "name": socket.gethostname()}))
                    else:
                        await ws.send(json.dumps({"type": "error", "message": "That PIN doesn’t match."}))
                    continue
                if not paired:
                    await ws.send(json.dumps({"type": "error", "message": "Pair with the Mac first."}))
                    continue
                if action in ("move", "click", "scroll", "scroll_state", "key", "text", "button") and not Quartz.CGPreflightPostEventAccess():
                    scrolling.stop()
                    paired = False
                    await ws.send(json.dumps({"type": "error", "message": ACCESS_MESSAGE}))
                    continue
                if action == "move":
                    current = Quartz.CGEventGetLocation(Quartz.CGEventCreate(None))
                    post_mouse("move", x=current.x + float(message.get("dx", 0)) * 1.55,
                               y=current.y + float(message.get("dy", 0)) * 1.55, dragging=dragging)
                elif action == "button":
                    dragging = bool(message.get("down"))
                    post_mouse("down" if dragging else "up")
                elif action == "release":
                    scrolling.stop()
                    if dragging:
                        post_mouse("up")
                        dragging = False
                    for key in held_keys:
                        post_key(key, False, [])
                    held_keys.clear()
                elif action == "click":
                    scrolling.stop()
                    button = "right" if message.get("button") == "right" else "left"
                    post_mouse("down", button); post_mouse("up", button)
                elif action == "scroll":
                    scrolling.feed(message.get("dx", 0), message.get("dy", 0))
                elif action == "scroll_state":
                    if message.get("phase") == "end":
                        scrolling.end()
                    else:
                        scrolling.stop()
                elif action == "key":
                    key = str(message.get("key", ""))
                    if message.get("down"):
                        held_keys.add(key)
                    else:
                        held_keys.discard(key)
                    post_key(str(message.get("key", "")), bool(message.get("down")), message.get("modifiers", []))
                elif action == "text":
                    type_text(str(message.get("text", ""))[:1000])
                elif action == "ping":
                    await ws.send(json.dumps({"type": "pong"}))
            except (ValueError, TypeError, KeyError):
                await ws.send(json.dumps({"type": "error", "message": "Invalid input event."}))
    except websockets.exceptions.ConnectionClosed:
        # Wi-Fi loss and app replacement can close without a WebSocket handshake.
        pass
    finally:
        scrolling.stop()
        if dragging:
            post_mouse("up")
        for key in held_keys:
            post_key(key, False, [])



class QuietHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def log_message(self, *_args):
        pass


def lan_address():
    # Internet routes can point through a VPN. Use hardware interfaces so the
    # address shown is reachable by another device on the local network.
    try:
        result = subprocess.run(
            ["/usr/sbin/networksetup", "-listallhardwareports"],
            capture_output=True, text=True, timeout=5, check=True,
        )
        interfaces = []
        hardware = ""
        for line in result.stdout.splitlines():
            if line.startswith("Hardware Port:"):
                hardware = line.partition(":")[2].strip()
            elif line.startswith("Device:"):
                interfaces.append((hardware, line.partition(":")[2].strip()))
        interfaces.sort(key=lambda item: item[0] != "Wi-Fi")
        for _, interface in interfaces:
            result = subprocess.run(
                ["/usr/sbin/ipconfig", "getifaddr", interface],
                capture_output=True, text=True, timeout=3,
            )
            try:
                address = ipaddress.IPv4Address(result.stdout.strip())
            except ipaddress.AddressValueError:
                continue
            if not (address.is_loopback or address.is_link_local or address.is_unspecified):
                return str(address)
    except (OSError, subprocess.SubprocessError):
        pass
    return None


async def main():
    address = lan_address()
    http = ThreadingHTTPServer(("0.0.0.0", WEB_PORT), QuietHandler)
    threading.Thread(target=http.serve_forever, daemon=True).start()
    print("\n  TOUCHDECK  /  MAC COMPANION")
    if address:
        print(f"  Native iPad app — Mac Address: {address}  (no port)")
        print(f"  Safari browser address:       http://{address}:{WEB_PORT}")
    else:
        print("  No active LAN address found. Connect Wi-Fi or Ethernet,")
        print("  then use its IP address from macOS Network settings.")
    print(f"  PIN:   {PIN}")
    print("  Keep this window open. Press Control-C to stop.\n")
    if not Quartz.CGPreflightPostEventAccess():
        print(f"  {ACCESS_MESSAGE}\n", flush=True)
        Quartz.CGRequestPostEventAccess()
    try:
        async with websockets.serve(handle_client, "0.0.0.0", SOCKET_PORT, ping_interval=20, ping_timeout=20):
            await asyncio.Future()
    finally:
        http.shutdown()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
