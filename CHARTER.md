# notch-prompter charter

## Problem

When you talk to a webcam, you need notes to stay on track. Notes on a
second monitor or on paper pull your eyes away from the lens, and the
recording shows it. A teleprompter fixes this, but a separate prompter app,
camera app, and recorder do not know about each other.

## What notch-prompter does

notch-prompter is a native macOS app for talking to camera. You write a
script, then you record yourself as you read it from a teleprompter. The
prompter sits directly below the camera: in the notch area on a MacBook, or
at the top center of the screen on other displays. Your eyes stay near the
lens.

The app owns the full session: the script, the camera and its effects, the
scroll, and the recording.

## In scope

- Script authoring. Scripts are Markdown files on disk.
- A prompter overlay near the camera, with adjustable speed, pause, and
  rewind.
- Camera and microphone selection, including an iPhone as a Continuity
  Camera.
- The live state of the system video effects: Portrait, Studio Light,
  background replacement, Center Stage, and reactions.
- Direct control of the effects that Apple lets an app control: Center Stage
  and reactions. For the other effects, a button opens the system Video
  Effects panel.
- Local recording of video and audio to a movie file. The system applies its
  video effects before the app gets the frames, so recordings include them.

## Out of scope

- Background or lighting effects that the app makes itself (Vision and Core
  Image).
- Editing recorded video.
- Uploading or publishing.
- Scrolling that follows your voice.
- iOS and iPadOS targets.

## Platform facts that set the scope

From the macOS 27 SDK (`AVCaptureDevice.h`):

- `centerStageControlMode` can be `.app` or `.cooperative`. Then the app can
  set `centerStageEnabled`.
- `performEffect(for:)` triggers a reaction when `canPerformReactionEffects`
  is true. Gesture detection stays under user control.
- `portraitEffectEnabled`, `studioLightEnabled`, and
  `backgroundReplacementEnabled` are read-only class properties. Only the
  user can change them, in Control Center.
- `showSystemUserInterface(.videoEffects)` opens the system Video Effects
  panel.
