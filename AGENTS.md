# Notch Prompter agent guidance

Native macOS teleprompter that sits under the camera and records the take.
`CHARTER.md` is the approved scope; do not add what it puts out of scope
(app-made background or lighting effects, video editing, uploading,
voice-following scroll, iOS). `README.md` covers the build, the cue syntax,
and the effects facts.

**Agent**: swift-craftsperson

## Where code goes

- Logic belongs in `Sources/NotchPrompterKit`: script parsing, layout, the
  scroll engine, panel placement, the take state machine, the effects model,
  and naming. It must not import SwiftUI, AppKit, or AVFoundation. It is the
  functional core, tested with `swift test` alone.
- `Apps/Shared/Gateways` holds thin adapters over AppKit, AVFoundation, and
  `FileManager`. Keep logic out of them. If a gateway grows a decision, move
  the decision into the Kit and test it there.
- `Apps/Shared/Models` holds the observable models that carry out the Kit's
  decisions. `TakeSession` decides; `PrompterController` executes its
  commands. Keep that split.
- `Apps/Shared/Views` holds SwiftUI. `Apps/macOS` stays thin.
- `NotchPrompter.xcodeproj` is **generated**. Never edit it. Change
  `project.yml` and run `xcodegen generate`. `Apps/macOS/Info.plist` is also
  rewritten from `project.yml`, so change plist keys there.

## Video effects: what the app may and may not do

- Do not try to set `portraitEffectEnabled`, `studioLightEnabled`, or
  `backgroundReplacementEnabled`. They are read-only class properties. The
  only control for them is `AVCaptureDevice.showSystemUserInterface(.videoEffects)`.
- Keep `AVCaptureDevice.centerStageControlMode` at `.cooperative`. Never set
  `.app`: it takes Center Stage away from the user and greys out the Control
  Center switch.
- Only call `performEffect(for:)` with a type from `availableReactionTypes`
  while `canPerformReactionEffects` is true. Anything else raises an
  Objective-C exception.
- Do not add app-made effects (Vision, Core Image). The charter rules them out.

## Concurrency

Swift 6 language mode with complete strict concurrency.

- `CaptureSessionGateway` confines the `AVCaptureSession` to one serial
  queue; that is why it is `@unchecked Sendable`. Every session call goes
  through `onQueue`. Do not touch the session from anywhere else.
- Models and AppKit gateways are `@MainActor`. KVO and notification
  callbacks hop to the main actor before touching them.

## Before committing

Run every gate in `.hone-gates.json`:

```bash
swift test && swiftlint lint --strict && xcodegen generate && \
  xcodebuild -project NotchPrompter.xcodeproj -scheme NotchPrompterMac \
    -configuration Debug -destination 'platform=macOS' build
```

The gates cannot check the parts that need a camera, a microphone, or a
notched screen: panel placement under the real notch, effects state, and an
actual recording. After changing those paths, run the app and check them by
hand.
