/// Picks which of the available things to use: a camera, a microphone, a display.
///
/// The person's own choice wins while it is still connected. When it goes
/// away (an iPhone walks off, a monitor is unplugged), the first fallback
/// that is available takes over, then the first available item. The choice
/// itself is kept by the caller, so the original device comes back into use
/// when it reconnects.
public enum PreferredSelection {

    public static func resolve<ID: Hashable>(preferred: ID?, available: [ID], fallbacks: [ID?] = []) -> ID? {
        for candidate in [preferred] + fallbacks {
            if let candidate, available.contains(candidate) {
                return candidate
            }
        }
        return available.first
    }
}
