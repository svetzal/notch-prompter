# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Added

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
