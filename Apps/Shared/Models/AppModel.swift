import Foundation
import Observation

/// The composition root: one instance per app run, owning every model.
@MainActor
@Observable
final class AppModel {

    let library: ScriptLibrary

    init(library: ScriptLibrary = ScriptLibrary()) {
        self.library = library
    }
}
