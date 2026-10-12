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
- The take controls are in the main window's toolbar (`MainToolbar`). The
  session column holds the camera, effects state, and last take only; do not
  add run controls back to it. The Prompter menu and the toolbar tooltips
  share their shortcuts through `Shortcuts`, and the toolbar's status comes
  from `TakeSession.status(at:)` in the Kit.
- The prompter's geometry (frame, top inset, corner radii) is decided by
  `PrompterPlacement` in the Kit. `NotchShape` and `PrompterView` only draw
  it. Keep the panel fill pure black, so it merges with the hardware notch.
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

## Video format: how a take gets its shape

- Vertical first uses the camera's native portrait format, when it has one.
  `NativeFormat` in the Kit decides which format (9:16 shape, at least 30
  fps, keeps every effect the preset's format supports, most pixels). The
  session gateway applies it in `applyCameraFormat`, on the session queue,
  when the format picker or the camera changes, never at Record.
- `.inputPriority` is unavailable on macOS. The session stays on `.high`,
  which may change its inputs' formats at any time, so setting
  `activeFormat` alone does not last. The device lock is what keeps a
  native format: set `activeFormat` inside one session
  `beginConfiguration`/`commitConfiguration` block with the device locked,
  and keep the lock while Vertical uses the native format. For Horizontal
  or a camera without one, set `activeFormat` back to the preset format
  remembered when the input was added (never rely on the preset to do it),
  then unlock. Release the lock before the camera's input is removed or
  replaced. Never leave a device locked that is not in the session. The
  session runs until the app quits, and process exit releases the lock.
- The crop geometry (kept size, centring, even sizes, the preview's kept
  region) is `VideoCrop` in the Kit. The gateways only apply it. It is the
  path for cameras without a native portrait format; with one, the source
  already has the shape and `needsCrop` is false.
- The crop path is the movie output's video settings: width, height,
  and `AVVideoScalingModeResizeAspectFill`, set at the start of each take.
  When no crop is needed, leave the connection at the session preset's own
  settings. Do not rely on `AVVideoCleanApertureKey`; players and upload
  services ignore it.
- Keep the self-check after each take (`CaptureModel.confirmShape`): it
  reads the movie's displayed size and re-crops by export when the shape is
  wrong. Its log line says which path ran. Do not remove it until live
  takes have shown the native format and the encoder crop both give the
  right shape on every camera in use.
- `centerStageRectOfInterest` is unavailable on macOS. Do not try to steer
  Center Stage to the crop.

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
notched screen: the panel flush with the top edge around the real notch,
effects state, an actual recording, and the shape of a vertical take. After changing those paths, run the app and check them by
hand.
