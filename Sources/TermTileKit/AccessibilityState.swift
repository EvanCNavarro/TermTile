/// The three states the menu-bar fix-it row distinguishes (#23) — computed by `MenuBarViewModel`
/// from the live Accessibility trust probe + the persisted `AppSettings.wasTrusted`. Lives in Kit
/// beside the VM (its only producer); the view switches on it.
///
/// `needsFirstGrant` vs `grantBroken` is the point: a first-time user needs the generic grant
/// prompt, but a user whose grant BROKE (untrusted yet previously granted — a moved or duplicate
/// bundle, the exact failure this session hit) needs an honest, different message. Revoke and
/// move-break both read untrusted+wasTrusted and are indistinguishable via `AXIsProcessTrusted`, so
/// the `grantBroken` copy is hedged to cover both.
public enum AccessibilityState: Equatable, Sendable {
    case trusted
    case needsFirstGrant
    case grantBroken
}
