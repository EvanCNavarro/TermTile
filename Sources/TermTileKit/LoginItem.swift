import Foundation
import ServiceManagement

/// The launch-at-login registration status — a Kit-owned mirror of `SMAppService.Status` so the
/// port (and its fake) carry a domain type instead of leaking the system enum to every consumer.
/// The source of truth for "launch at login on?" is this status, NEVER a persisted UserDefaults
/// bool (`AppSettings.swift`: persisting it too would be a double-source-of-truth bug).
public enum LoginItemStatus: Sendable, Equatable {
    /// Not currently registered as a login item.
    case notRegistered
    /// Registered and enabled — launches at login.
    case enabled
    /// Registered but the user must approve it in System Settings > General > Login Items.
    case requiresApproval
    /// No such service found (e.g. an unsigned/unbundled binary, or a stale registration).
    case notFound
}

/// The launch-at-login port (ADR-0001 imperative-shell seam). The production adapter wraps
/// `SMAppService.mainApp`; tests inject `InMemoryLoginItem`. Synchronous by design — like
/// `SettingsStore`, these are cheap non-blocking calls, so (unlike the `WindowSystem` port) there
/// is no `async`/actor requirement. `register()`/`unregister()` throw because the underlying
/// `SMAppService` calls surface `NSError` (e.g. `kSMErrorInvalidSignature` on an unsigned binary).
public protocol LoginItem: Sendable {
    /// The current registration status (the launch-at-login source of truth).
    var status: LoginItemStatus { get }
    /// Register the containing app as a login item. Throws on failure (unsigned app, XPC error).
    func register() throws
    /// Remove the login-item registration. Throws on failure.
    func unregister() throws
}

/// The production `LoginItem`, backed by `SMAppService.mainApp`. Stores NOTHING and resolves
/// `SMAppService.mainApp` per call: `SMAppService` is a non-`Sendable` `NSObject`, so a stored
/// reference would break this struct's `Sendable` conformance under Swift 6 strict concurrency
/// (the same per-call-resolve fix as `UserDefaultsSettingsStore`, stoke-plan-12a audit F1).
///
/// LIVE `register()`/`unregister()` require the packaged, code-signed `.app` (Apple documents
/// `SMAppService` callers "must be code signed"; an unsigned/unbundled binary gets
/// `kSMErrorInvalidSignature`) — proven live in #13, not from a `swift run` binary.
public struct SMAppServiceLoginItem: LoginItem {
    public init() {}

    public var status: LoginItemStatus { Self.map(SMAppService.mainApp.status) }

    public func register() throws { try SMAppService.mainApp.register() }

    public func unregister() throws { try SMAppService.mainApp.unregister() }

    /// Translate the system status to the domain status. An EXPLICIT named-case switch (not a
    /// `rawValue` bridge, which would couple to Apple's declaration order and defeat the
    /// invert-check) — the keystone `LoginItemTests.statusMappingIsFaithful` pins every arm.
    /// `SMAppService.Status` is a non-frozen `NS_ENUM`, so `@unknown default` is required; an
    /// unknown future case reads as the fail-safe `.notFound` ("can't confirm it's on").
    static func map(_ status: SMAppService.Status) -> LoginItemStatus {
        switch status {
        case .notRegistered: return .notRegistered
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .notFound
        }
    }
}
