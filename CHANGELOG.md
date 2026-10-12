# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Added

- Vertical takes use the camera's native portrait format when it has one.
  On the MacBook Pro camera a vertical take is now the full 1080x1920
  frame instead of a 608x1080 cut, the preview is not dimmed, and Center
  Stage frames for the portrait image. The camera switches when you choose
  the format or change the camera, not at Record. Cameras without a
  portrait format, such as an iPhone, keep the centre cut. The log says
  which format the camera switched to and, at each take start, whether the
  take is native or cut.
- Edge Light in the effects panel (macOS 26.2 and later). The row shows
  whether the camera's format supports it, whether Control Center has it
  on, and whether it is showing. When it is on but not showing, a note
  says that Automatic mode turns it on only in low light and that Video
  Effects can set it to On. It is read-only, like Portrait and Studio
  Light. Each take's log records the Edge Light state at the start.
- Video format: record a take as Horizontal (16:9) or Vertical (9:16). The
  choice is next to the camera preview and is remembered. A vertical take
  is cut from the centre of the camera's frame, at full height, while it
  records; the preview dims what the take will not keep. After each take
  the app checks the movie's shape and, if the encoder did not cut it,
  re-crops it by export. Vertical takes end in `-vertical`, and the toolbar
  shows "Vertical" while one records.

### Changed

- The camera preview shows the camera's whole frame, in the camera's own
  shape, instead of filling a 16:9 box.
- Takes record audio at 48 kHz instead of the session preset's 24 kHz.

- The prompter grows out of the notch instead of hanging below it. The panel
  starts at the screen's top edge, is pure black, and has the notch's
  outline, with concave curves into the top edge and rounded bottom
  corners. The text starts just under the camera housing. Without a notch,
  the same shape hangs from the top centre of the display.
- The prompter panel sits one level higher, above the menu bar's status
  items.
- Prompter text has more room at the sides (28 points instead of 16), so it
  clears the panel's rounded bottom corners. Lines fade in at the bottom
  edge and out at the top edge instead of being cut off.
- The run controls moved from the session column to a customizable toolbar:
  the Prompter toggle and Rehearse on the left, the take status in the
  centre, and speed, Prompter Settings, Video Effects, and Record (Stop
  during a run) on the right. Tooltips name the keyboard shortcuts. The
  session column keeps the camera, the effects state, and the last take.
- The main window is at least 1000 points wide, so the toolbar fits.

### Fixed

- After quick Horizontal and Vertical changes, the preview could show the
  landscape image inside a portrait frame while the log said the camera
  had switched to its native format. On macOS the `.high` session preset
  could take the format back, because the app released the camera's lock
  right after setting it. The app now holds the lock while Vertical uses
  the native format, and sets the preset format back itself for
  Horizontal. The log says when a format does not hold after the change.

### Added

- Script library: Markdown scripts in `~/Documents/Notch Prompter/Scripts`,
  with create, rename, edit, and autosave. A `Welcome.md` sample on first run.
- Script parsing to prompter text, with `[pause]`, `[pause N]`, and
  `[note: …]` cues, headings as notes, and HTML comments hidden.
- Prompter panel under the notch, or at the top centre without one, above
  the menu bar and on every Space.
- Scroll engine in words per minute, with pauses, nudges, paragraph jumps,
  a countdown, and live text-size changes that keep your place.
- Keyboard control while the prompter shows.
- Camera and microphone selection, including Continuity Camera, following
  device connects and disconnects.
- Live state of Portrait, Studio Light, background replacement, Center Stage,
  and reactions. A Center Stage switch (cooperative mode), reaction buttons,
  and a button for the system Video Effects panel.
- Recorded takes: countdown, then prompter and recording together, saved as
  QuickTime movies in `~/Movies/Notch Prompter/` and shown in Finder.
- Permission notices with links to the Camera and Microphone privacy panes.
