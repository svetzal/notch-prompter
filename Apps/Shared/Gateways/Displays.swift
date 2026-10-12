import AppKit
import NotchPrompterKit

/// A connected display, as the prompter sees it.
struct DisplayInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let geometry: DisplayGeometry

    var hasNotch: Bool { geometry.notch != nil }

    static func == (lhs: DisplayInfo, rhs: DisplayInfo) -> Bool { lhs.id == rhs.id && lhs.geometry == rhs.geometry }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Reads display geometry from `NSScreen`. No logic: placement is in the Kit.
enum Displays {

    @MainActor
    static func current() -> [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return DisplayInfo(
                id: number.uint32Value,
                name: screen.localizedName,
                geometry: DisplayGeometry(
                    frame: screen.frame,
                    safeAreaTop: screen.safeAreaInsets.top,
                    auxiliaryTopLeft: screen.auxiliaryTopLeftArea ?? .zero,
                    auxiliaryTopRight: screen.auxiliaryTopRightArea ?? .zero
                )
            )
        }
    }
}
