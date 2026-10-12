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
  background replacement, Edge Light, Center Stage, and reactions. Edge
  Light is read-only.
- Direct control of the effects that Apple lets an app control: Center Stage
  and reactions. For the other effects, a button opens the system Video
  Effects panel.
- Local recording of video and audio to a movie file. The system applies its
  video effects before the app gets the frames, so recordings include them.
- Horizontal (16:9) or vertical (9:16) takes.
- The state of the system microphone mode (Standard, Voice Isolation, Wide
  Spectrum), with a button that opens the system Microphone Modes panel.
- Voice clean-up applied to each take: a chain of the Audio Unit plug-ins
  installed on the Mac, run over the take's audio after it is recorded. The
  unprocessed take is kept beside the processed one.

## Out of scope

- Background or lighting effects that the app makes itself (Vision and Core
  Image).
- Editing recorded video. Voice clean-up of a whole take is the one
  exception; cutting, trimming, and mixing are still out.
- Live audio processing while recording, and audio effects that the app makes
  itself. The chain uses installed plug-ins only.
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
- Edge Light (macOS 26.2 and later) is read-only. The class property
  `isEdgeLightEnabled` is on when Control Center has it on.
  `isEdgeLightActive`, also a class property, is on when the light is
  showing on a screen. `AVCaptureDeviceFormat.isEdgeLightSupported` says
  whether a format supports it. No API turns it on or changes Automatic
  mode. The system draws it on a display, not in the camera image.
- `showSystemUserInterface(.videoEffects)` opens the system Video Effects
  panel.
- The microphone mode is read-only. `preferredMicrophoneMode` is the user's
  choice in Control Center, and `activeMicrophoneMode` is the mode in use,
  which can differ when the audio route does not support the choice.
  `showSystemUserInterface(.microphoneModes)` opens the system panel.

From AVFAudio and AudioToolbox:

- `AVAudioUnitComponentManager` lists the installed Audio Unit effects, and
  `AVAudioUnit.instantiate(with:options:)` loads one.
  `kAudioComponentInstantiation_LoadOutOfProcess` loads it in a separate
  process, so a plug-in crash does not stop the app.
- `AVAudioEngine` manual rendering mode runs audio through a chain of
  plug-ins faster than real time. This is why the chain runs after the take:
  plug-ins with look-ahead latency would put a live recording out of sync.
