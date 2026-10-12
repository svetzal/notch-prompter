# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Changed

- The prompter grows out of the notch instead of hanging below it. The panel
  starts at the screen's top edge, is pure black, and has the notch's
  outline, with concave curves into the top edge and rounded bottom
  corners. The text starts just under the camera housing. Without a notch,
  the same shape hangs from the top centre of the display.
- The prompter panel sits one level higher, above the menu bar's status
  items.
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
