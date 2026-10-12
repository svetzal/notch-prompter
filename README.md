# Notch Prompter

A native macOS app for talking to camera. You write a script, then record
yourself reading it from a teleprompter that sits directly under the camera:
in the notch on a MacBook, or at the top centre of other displays. Your eyes
stay near the lens.

The app owns the whole session: the script, the camera and its effects, the
scroll, and the recording. `CHARTER.md` sets the scope.

## Layout

| Path | What lives there |
| --- | --- |
| `Sources/NotchPrompterKit` | Functional core. Script parsing, prompter layout, the scroll engine, panel placement, the take state machine, the effects model, file naming. No SwiftUI, AppKit, or AVFoundation. |
| `Tests/NotchPrompterKitTests` | Swift Testing suites for the Kit. |
| `Apps/Shared/Gateways` | Thin adapters over AppKit, AVFoundation, and the file system. |
| `Apps/Shared/Models` | Observable app models that run the Kit's logic against the gateways. |
| `Apps/Shared/Views` | SwiftUI views. |
| `Apps/macOS` | App entry point, Info.plist, entitlements. |
| `project.yml` | XcodeGen source of truth. `NotchPrompter.xcodeproj` is generated and gitignored. |

## Building

Requires Xcode with the macOS 15 SDK or later, and XcodeGen.

```bash
xcodegen generate && open NotchPrompter.xcodeproj
```

The Kit builds and tests on its own, without Xcode:

```bash
swift test
```

The quality gates are in `.hone-gates.json`: `swift test`,
`swiftlint lint --strict`, and a full `xcodebuild` of the `NotchPrompterMac`
scheme.

## Using it

1. Pick or write a script in the left column. Scripts autosave a second after
   you stop typing, and on ⌘S.
2. Check the camera, microphone, and effects in the right column.
3. Click Record in the toolbar, or press ⌘R. After the countdown, the
   prompter scrolls and the recording runs. Click Stop or press Esc to stop
   both. Finder shows the new movie.

Rehearse (⇧⌘R, or Space while the prompter shows) runs the prompter without
recording. The Prompter toggle (⇧⌘P) puts the panel up without starting it,
so you can park it at a paragraph before a take.

### The toolbar

The run controls are in the main window's toolbar. To rearrange them,
Control-click the toolbar, or choose View > Customize Toolbar.

| Where | Control |
| --- | --- |
| Left | Prompter (show or hide it), Rehearse |
| Centre | Take status: Ready, the countdown, Rehearsing, or a red dot with the recording time. Saving… while the movie file closes. |
| Right | Speed (− / wpm / +), Prompter Settings, Video Effects, Record |

Prompter Settings holds the text size, the number of lines, the width, the
countdown, the display, and the keys reference. Video Effects opens the
system Video Effects panel. Record becomes Stop while a countdown, a run, or
saving is under way. Each control's tooltip names its keyboard shortcut.

The right column keeps the camera preview, the camera and microphone
pickers, the effects state, and a link to the last take.

### Keys while the prompter shows

| Key | Action |
| --- | --- |
| Space | Start a rehearsal, or pause and resume the scroll |
| Esc | Stop the take or rehearsal; press again to hide the prompter |
| + / − | Faster / slower, 10 words per minute a step |
| ↑ / ↓ | Back / forward one line |
| ← / → | Back / forward a paragraph. Back restarts the current paragraph if you are past its first half-line. |
| Home or ⌘↑ | Back to the start |
| ⌘+ / ⌘− | Larger / smaller text |

The keys work while Notch Prompter is the active app. The prompter panel
never takes focus, so the main window keeps it. While the prompter is ready
and the script editor has focus, keys go to the editor; once a run starts,
they go to the prompter. Keys typed into other apps do not reach it, because
that would need Accessibility permission.

## Scripts

Scripts are Markdown files in `~/Documents/Notch Prompter/Scripts`, created on
first run with a `Welcome.md` that shows the cue syntax. "Change…" at the
bottom of the list picks another folder. Files ending `.md` or `.markdown`
are listed.

The prompter shows readable text, not rendered Markdown:

- Blank lines separate paragraphs. Line breaks inside a paragraph become
  spaces.
- Each list item is its own paragraph, without its marker.
- Headings show as notes: visible, but not timed as speech.
- Emphasis, code, and link markup is removed. Link text stays. Images are
  dropped.
- HTML comments (`<!-- like this -->`) are removed. Use them for remarks you
  never want on the prompter.
- YAML front matter is ignored.

### Cues

Cues go anywhere in the text, on their own line or inside a paragraph. A cue
inside a paragraph splits it at that point.

| Cue | Effect |
| --- | --- |
| `[pause]` | Hold the scroll for 2 seconds |
| `[pause 3]`, `[pause 1.5s]` | Hold for that many seconds |
| `[note: smile]` | Show "smile" as a note in yellow italics, not timed as speech |

Cue words are not case-sensitive. A pause with a length that is not a
positive number holds for the default 2 seconds.

## The prompter

### Placement

The prompter grows out of the notch. `PrompterPlacement` places it from
`NSScreen` facts alone:

- The panel's top edge is the screen's top edge. It is filled pure black
  and clipped to a notch shape: concave curves where it meets the top edge,
  and rounded bottom corners. Because the hardware notch is black too, the
  panel reads as the notch getting bigger, in light and dark mode.
- On a display with a notch, the notch is the gap between
  `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`, and its height is
  `safeAreaInsets.top`. The panel is centred on the notch and is never
  narrower than it. The text starts at the notch's bottom edge, so the
  reading line sits just under the camera.
- On a display without a notch, the same shape hangs from the top centre,
  over the middle of the menu bar. The text starts 6 points below the top
  edge.

The panel floats above the menu bar and its status items, on every Space and
over full-screen apps. It never takes focus, and clicks pass through it.

The prompter uses the display chosen in the window. If that display is not
connected, it uses one with a notch, then the first display.

### Scrolling

Speed is in words per minute (60 to 300, 140 by default). Each line stays on
the reading line for as long as its words take at that speed. Note lines
take two words' worth of time. Pause lines hold for their cue's seconds at
any speed.

The scroll position is a pure function of the clock. The engine keeps an
anchor (a position, and the moment it started playing) and computes the
position for each frame. Pause, speed changes, nudges, and jumps all
re-anchor at the current moment. Changing the text size or the width
rewraps the script and keeps your place in the paragraph.

## Video effects

The system applies its video effects before the app receives frames, so
recordings include them. What an app may control is set by AVFoundation. As
read from `AVCaptureDevice.h` in the macOS 27 SDK:

- `AVCaptureDevice.centerStageControlMode` can be `.user`, `.app`, or
  `.cooperative`. In `.app` or `.cooperative` mode the app can set
  `centerStageEnabled`. Notch Prompter uses `.cooperative`, so the Control
  Center switch keeps working, and shows a Center Stage switch.
- `performEffect(for:)` triggers a reaction when `canPerformReactionEffects`
  is true, for a type in `availableReactionTypes`. Notch Prompter shows a
  button for each available reaction. Gesture-triggered reactions stay under
  the user's control in Control Center.
- `portraitEffectEnabled`, `studioLightEnabled`, and
  `backgroundReplacementEnabled` are read-only class properties. Only the
  user can change them, in Control Center.
- `showSystemUserInterface(.videoEffects)` opens the system Video Effects
  panel. Video Effects in the toolbar calls it.

The window shows each effect's live state from key-value observation of the
device (`isPortraitEffectActive`, `isStudioLightActive`,
`isBackgroundReplacementActive`, `isCenterStageActive`,
`canPerformReactionEffects`, `activeFormat`) and of the class switches. An
effect reads "On, not active" when its switch is on but the camera is not
applying it, and "Not available" when the camera's format does not support
it.

## Cameras and microphones

Cameras come from a discovery session over built-in, Continuity Camera, and
external devices. `NSCameraUseContinuityCameraDeviceType` is set, so an
iPhone shows as a Continuity Camera. The lists follow devices as they
connect and disconnect. If the chosen camera goes away, the app uses the
system's preferred camera until it comes back.

Camera and microphone access are requested at launch. If either is denied,
the window says what that means and links to the right Privacy & Security
pane. Without the microphone, takes record video only.

## Recording

Takes are QuickTime movies in `~/Movies/Notch Prompter/`, named with a
timestamp and the script title, for example
`2026-10-12-143205-product-launch.mov`. A second take in the same second
gets `-2`. Device changes are held back while a take records.

## Signing

The app is not sandboxed. It uses the hardened runtime with the camera and
audio-input entitlements, so a notarized build can use both.

## License

MIT. See `LICENSE`.
