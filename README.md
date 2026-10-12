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
| `Sources/NotchPrompterKit` | Functional core. Script parsing, prompter layout, the scroll engine, panel placement, the take state machine, the effects model, the video format crop, file naming. No SwiftUI, AppKit, or AVFoundation. |
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
2. Check the camera, microphone, and effects in the right column, and pick
   Horizontal or Vertical under the preview.
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

The right column keeps the camera preview, the video format, the camera and
microphone pickers, the effects state, and a link to the last take.

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
- Edge Light (macOS 26.2 and later) is read-only too. The class properties
  `isEdgeLightEnabled` (switched on in Control Center) and
  `isEdgeLightActive` (the light is showing on a screen now) are key-value
  observable, and `AVCaptureDeviceFormat.isEdgeLightSupported` says whether
  the camera's format supports it. No API turns it on or changes its
  Automatic mode. The system draws it on a display (the built-in display for
  the built-in camera, the primary display for other cameras), so it lights
  your face but is not part of the camera image.
- `showSystemUserInterface(.videoEffects)` opens the system Video Effects
  panel. Video Effects in the toolbar calls it.

The window shows each effect's live state from key-value observation of the
device (`isPortraitEffectActive`, `isStudioLightActive`,
`isBackgroundReplacementActive`, `isCenterStageActive`,
`canPerformReactionEffects`, `activeFormat`) and of the class switches,
including `edgeLightEnabled` and `edgeLightActive`. An effect reads "On, not
active" when its switch is on but the camera is not applying it, and "Not
available" when the camera's format does not support it.

Edge Light reads its state from the system, not from the camera:

| Edge Light state | The row shows |
| --- | --- |
| Format does not support it, or macOS is earlier than 26.2 | Not available |
| Off in Control Center | Off |
| On in Control Center, not showing | On, not active, with a note: in Automatic mode it comes on only in low light, and Video Effects can set it to On |
| Showing on a screen | On |

Each take's log records the Edge Light state at the start of the take
(enabled, active, format supported), in the `recording` category of the
`com.mojility.notch-prompter` subsystem.

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
`2026-10-12-143205-product-launch.mov`. Vertical takes end in `-vertical`.
A second take in the same second gets `-2`. Device changes are held back
while a take records.

## Video format

The Format control under the camera preview records each take as
Horizontal (16:9) or Vertical (9:16). The choice is remembered, and it is
locked while a take counts down, records, or saves. The camera is never
turned: a take is cut from the centre of the camera's frame. On a 1920x1080
laptop camera, a vertical take keeps the full height and is 608x1080. A
camera that already has the format's shape, such as a 16:9 camera for
Horizontal or an upright iPhone for Vertical, records as it always did.

The preview shows the whole camera frame. For a cut format, it dims what
the take will not keep and outlines what it will, so you can frame
yourself before you record.

How the cut is made:

1. At the start of each take, `VideoCrop` in the Kit works out the kept
   region from the camera's current format: centred, even pixel sizes, and
   never larger than the camera's frame.
2. The movie output's encoder is asked for that size with aspect-fill
   scaling, so it writes the cut frame while it records. Clean-aperture
   metadata is not used, because many players and upload services ignore
   it.
3. When the take's file closes, the app reads the movie's displayed size.
   If it does not have the format's shape, the app cuts it from the centre
   with an export and replaces the file. The take shows "Saving…" until
   this is done.

The log says which path gave the take its shape:

```bash
log show --last 1h --predicate 'subsystem == "com.mojility.notch-prompter"'
```

Two limits to know:

- Vertical has low resolution on a 1080p laptop camera: 608x1080, about a
  third of the frame. A 4K camera or an iPhone gives a sharper vertical
  take.
- Center Stage frames for the whole camera image. macOS does not let an app
  give Center Stage a region of interest (`centerStageRectOfInterest` is
  not available on macOS), so in a vertical take Center Stage can move you
  toward the dimmed sides. Turn Center Stage off for vertical takes if it
  does.

## Signing

The app is not sandboxed. It uses the hardened runtime with the camera and
audio-input entitlements, so a notarized build can use both.

## License

MIT. See `LICENSE`.
