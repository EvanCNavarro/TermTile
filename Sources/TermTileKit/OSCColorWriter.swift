import Foundation
import TermTileCore

/// The PRODUCTION `SessionTinting` adapter: OSC 1337 `SetColors` written to the session's tty.
///
/// This is the write half of ADR-0006 Tier 1, and the reason no Apple Events entitlement is
/// needed. Proven against live iTerm2 on 2026-08-28 by reading the colour back through
/// AppleScript after writing, and shown safe under load on 2026-08-31: 200 rapid writes during
/// an active TUI render left the scrollback byte-identical (36,652 chars, 3,937 control
/// characters, unchanged).
public actor OSCColorWriter: SessionTinting {
    /// Injected so tests never write to a real terminal.
    public typealias DeviceWriter = @Sendable (_ path: String, _ bytes: String) -> Bool

    private let write: DeviceWriter

    public init(write: @escaping DeviceWriter = OSCColorWriter.writeToDevice) {
        self.write = write
    }

    @discardableResult
    public func setBackground(_ color: TintColor, onTTY tty: String) async -> Bool {
        // VALIDATE BEFORE OPENING. The tty string comes from parsed `ps` output; without this
        // check a malformed value would make TermTile write escape bytes into an arbitrary file.
        guard OSCSequence.isWritableTerminalDevice(tty) else { return false }
        return write(tty, OSCSequence.setBackground(color))
    }

    /// Appends to the device. Fails closed: any error means the session simply is not tinted.
    ///
    /// Opened per write rather than held: a tty can disappear when a window closes, and a stale
    /// descriptor would either fail silently or, once the number is recycled, write into a
    /// DIFFERENT session.
    public static let writeToDevice: DeviceWriter = { path, bytes in
        guard OSCSequence.isWritableTerminalDevice(path),
              let data = bytes.data(using: .utf8),
              let handle = FileHandle(forWritingAtPath: path) else { return false }
        defer { try? handle.close() }
        do {
            try handle.write(contentsOf: data)
            return true
        } catch {
            return false
        }
    }
}
