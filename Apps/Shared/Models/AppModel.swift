import Foundation
import Observation

/// The composition root: one instance per app run, owning every model.
@MainActor
@Observable
final class AppModel {

    let library: ScriptLibrary
    let prompter: PrompterController

    init(library: ScriptLibrary = ScriptLibrary(), prompter: PrompterController = PrompterController()) {
        self.library = library
        self.prompter = prompter
        prompter.setDocument(library.document)
        prompter.scriptTitle = library.selectedTitle
        library.onChange = { [weak prompter, weak library] in
            guard let prompter, let library else { return }
            prompter.setDocument(library.document)
            prompter.scriptTitle = library.selectedTitle
        }
    }
}
