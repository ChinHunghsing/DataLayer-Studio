# DataLayer Studio Features & User Guide

Last updated: 2026-07-16

Applies to: macOS 0.3.3

DataLayer Studio is a data-overlay production tool for running, cycling, and outdoor sports videos. It puts video footage and `.fit` / `.gpx` activity recordings on one multitrack timeline, lets you arrange speed, pace, heart rate, route, distance, and weather components in a live preview, and exports either a transparent overlay or a fully composited video.

This guide has three parts:

1. Features: what the app can and cannot do.
2. User manual: the complete workflow from a new project to export.
3. Case studies: how to organize and align complex timelines in common shooting scenarios.

## Contents

- [1. What the app is for](#1-what-the-app-is-for)
- [2. Feature overview](#2-feature-overview)
- [3. Before you start](#3-before-you-start)
- [4. Interface layout](#4-interface-layout)
- [5. Your first project](#5-your-first-project)
- [6. Timeline editing in detail](#6-timeline-editing-in-detail)
- [7. Data components and the canvas](#7-data-components-and-the-canvas)
- [8. The weather component](#8-the-weather-component)
- [9. The Export Center](#9-the-export-center)
- [10. Saving, opening, and recovering projects](#10-saving-opening-and-recovering-projects)
- [11. Case studies](#11-case-studies)
- [12. Keyboard shortcuts](#12-keyboard-shortcuts)
- [13. FAQ](#13-faq)
- [14. Command line](#14-command-line)
- [15. Pre-export checklist](#15-pre-export-checklist)

---

## 1. What the app is for

Typical uses:

- Overlay route, distance, pace, and heart rate on a race recap video.
- Show cadence, power, running dynamics, and elevation in a training review.
- Put multiple clips filmed at scattered moments of one activity back at their true activity time.
- Export a transparent Alpha overlay and finish the edit in DaVinci Resolve, Final Cut Pro, or Premiere.
- Export a finished video with the original footage, original audio, and the data overlay composited.
- Save projects, layout templates, and export presets to reuse on your next video.

DataLayer Studio follows the principle of "standard editing logic, lightweight interaction". The timeline supports multiple video tracks, multiple activity tracks, clip moving, trimming, splitting, copy/paste, multi-select, snapping, track locking, and undo — but it is not a full NLE:

- No transitions, speed ramps, picture-in-picture, keyframes, or multicam tools yet.
- When video tracks overlap, the upper video covers the lower one full-frame.
- Activity tracks are for data overlays, not for blending two video images.

## 2. Feature overview

### 2.1 Media and projects

- Import one or more video files, and one or more `.fit` / `.gpx` activity files.
- Multi-select imports from Finder join the timeline in order; when the timeline already has content, new media is appended at the end of the project.
- Files can be dragged straight from Finder into the media library or onto a timeline track: dropping on the library only imports; dropping on the timeline imports and places the clip at the drop point.
- When both video and activity files carry reliable recording times, they are aligned automatically by absolute time; import order does not matter.
- The media library marks which assets are in use; offline assets can be relinked.
- Projects use the dedicated `.dlsproj` format, storing media references, tracks, clips, layouts, export settings, the playhead position, and fetched weather data. Legacy `.json` projects still open.

### 2.2 A standard multitrack timeline

- Any number of video tracks and activity tracks; clips move freely, and gaps are allowed at the start, between clips, and at the end.
- Clips trim at both ends; trimming changes the source in or out point.
- Clips can be copied, cut, pasted, and paste-inserted — including right-click paste on empty timeline space.
- Clip edges snap to the timeline start, the red playhead, and other clip edges; snapping toggles with one click in the timeline toolbar.
- Command multi-select, split at playhead, delete, ripple delete, and undo/redo.
- `,` / `.` nudge the selected clips one frame left or right; holding Shift locks the horizontal position while dragging across tracks.
- Clips can be disabled temporarily instead of deleted; disabled clips are excluded from preview, export, and edit-point navigation.
- Video clips show audio waveforms; sections without video stay silent in composited output.
- Pauses recorded in FIT files are preserved on the activity time axis; values hold at the pause boundary during the pause.

### 2.3 Data overlays

Available components:

- Basics: speed, pace, heart rate, cadence, calories, total ascent, stride length, power.
- Running dynamics: vertical oscillation, ground contact time, ground contact ratio, ground contact balance, vertical ratio, respiration rate.
- Extended metrics: pace loss, form power, air power, leg spring stiffness.
- Visualizations: GPS route, distance value, distance progress, time and date, weather.

What can actually display depends on the fields in your activity file. GPX usually carries only time, position, distance, and speed; a full FIT file usually has much more.

### 2.4 Preview and canvas

- Video, black gaps, and data overlays preview on the same single timeline; with no video, the preview is the data layer on a black canvas.
- Components drag directly, with multi-select, part sub-selection, and smart-guide snapping.
- The Arrange menu and the context menu provide layering, alignment, distribution, and copy/paste style.
- Each activity clip can inherit the project's default layout or keep its own layout and distance unit.

### 2.5 Export

The Export Center (`⌘E`) keeps presets, settings, progress, and results in one window:

- **Transparent overlay**: always keeps a transparent background; encode as HEVC Alpha or ProRes 4444.
- **Composited video**: shows video where it exists, the data layer on black where only data exists, and pure black where neither exists. Encode as HEVC or H.264.
- Render scope is either **Full Timeline** (one file) or **Individual Clips** (one file per clip).
- Five built-in export presets; save your own settings as My Presets.

---

## 3. Before you start

### 3.1 System requirements

- Apple Silicon Mac.
- macOS 13 Ventura or later.
- The App Store build needs a valid purchase; use Restore Purchases if the status looks wrong.

### 3.2 Media recommendations

Video:

- Keep original files and original creation times; auto-alignment relies on recording-time metadata.
- Landscape, portrait, mixed resolutions, and mixed frame rates can live in one project.
- Don't move or delete files a project references in Finder; if you must, use Relink afterwards.

Activity data:

- Prefer the original FIT exported by your device.
- GPX works for route, distance, speed, and pace, but usually lacks heart rate, power, and running dynamics.
- The activity file and the video should come from the same session.
- If you paused during the activity, the timeline keeps the real wall-clock time the pause occupied; it is not compressed away.

### 3.3 Understand the two clocks first

Every clip has two time systems:

- **Timeline time**: where the clip sits in the project.
- **Source time**: which second of the source file the clip starts reading from.

The clip inspector on the right shows:

- **Timeline start**: editable; use it to move the whole clip precisely.
- **Source in point**: read-only; determined by the left trim handle.
- **Duration**: read-only; determined by the trims at both ends.

Normal alignment only requires moving clips — never modifying the source itself.

---

## 4. Interface layout

The main window has five areas:

1. **The Library panel** on the left: import media, browse components, and manage templates in the Media / Components / Templates tabs.
2. **The preview canvas** in the center: see the final frame at the current time; select and drag data components.
3. **The preview control bar**: play, pause, frame stepping, timecode, preview zoom, and fullscreen.
4. **The timeline** at the bottom: arrange video and activity clips, manage tracks, trim, split, copy and paste.
5. **The inspector** on the right: edit component styles when a data component is selected; edit clip timing and layout when a timeline clip is selected.

The toolbar shows or collapses the Library, timeline, and inspector (`⌥⌘1` / `⌥⌘2` / `⌥⌘3`); panel widths are draggable. The Output button in the top-right corner or `⌘E` opens the Export Center. Alignment, trimming, and splitting all happen directly on the timeline — there is no separate "Sync" or "Trim" page.

Transient messages (saved, export failure reasons, and so on) appear as toasts in the bottom-right corner — at most three at a time, disappearing after a few seconds. The full runtime log lives in Debug > Show Debug Console (`⇧⌘D`).

On launch, only the welcome window appears: create a project, open an existing one, browse recent projects and My Templates, or drop a project, video, FIT, or GPX file anywhere in the window. Once an activity file loads, the window title prefers "activity date + sport", e.g. "2026-07-05 Running".

---

## 5. Your first project

### Step 1: Import media

In Library > Media:

1. Use the drop zone or the "Import Video…" / "Import Activity File…" buttons, or drag files straight from Finder into the library or timeline.
2. Wait for each row to show a duration; videos also show their resolution.
3. Confirm the clips appear on the timeline.

If both the video metadata and the FIT/GPX carry reliable recording times, the app arranges and aligns the clips automatically by real time. Still verify at one clear event; when recording times are missing, far apart, or the track is locked, align manually as described below.

Shortcuts: open video `⌘O`, open activity file `⌘F`.

### Step 2: Organize the timeline

New media appends at the end by default; tracks are not created per asset. You can:

- Drag clips horizontally to reposition, or vertically onto a same-type track to change tracks (hold Shift to lock the horizontal position).
- Drag assets from the media library straight onto a target track at a target time.
- Click "Add to Timeline" on an asset row to append a new instance at the end of the project.

For more tracks, click "Add Track" at the top right of the timeline and choose a video track or an activity track.

### Step 3: Align video with activity data

Alignment means making the same real-world event land at the same timeline position in both media types.

The common method:

1. Find a clear event in the video — the start gun, a road sign, an aid station, a turn.
2. Note when that event happens in the video source.
3. Note when the same event happens in the activity recording.
4. Drag the video or activity clip until both events sit under the red playhead.
5. Play a few seconds around the event and watch distance, route, and pace.

For precise input: select the clip and type hours, minutes, seconds, and milliseconds into "Timeline start" in the clip inspector — or nudge frame by frame with `,` / `.`.

For untrimmed clips the quick formula is:

```text
activity clip timeline start
= video clip timeline start + event time in video - event time in activity
```

If the result is negative, don't place a clip at negative time. Move the other clip later instead, leaving a gap at the start of the timeline.

For already-trimmed clips, correct with the "Source in point" shown in the inspector:

```text
activity clip start
= video clip start
 + (video event time - video source in point)
 - (activity event time - activity source in point)
```

### Step 4: Trim and split

Trimming:

- Drag the left handle: changes the source in point and the clip start.
- Drag the right handle: changes the clip end.
- Handles snap to the red playhead, other clip edges, and the timeline start, showing a guide line; turn snapping off in the timeline toolbar when you don't want it.

Splitting:

1. Move the red playhead to the cut position.
2. With one or more clips selected, `⌘B` splits only the selected clips under the playhead.
3. With nothing selected, `⌘B` splits clips on every editable track under the playhead.

This matches the common DaVinci Resolve behavior.

### Step 5: Arrange data components

1. Move the playhead somewhere with activity data.
2. In Library > Components, double-click a component to add it, or drag it to a specific spot on the canvas.
3. Drag components on the canvas; smart guides align them to other components, the canvas center lines, and the safe frame.
4. Fine-tune layout, style, and data settings in the inspector.

For a first pass, keep just route, distance, pace, and heart rate. Make the information legible first; add running dynamics or weather later.

### Step 6: Export

1. Click Output in the top-right corner or press `⌘E` to open the Export Center.
2. Pick a built-in preset on the left, or adjust render mode, size, frame rate, codec, and bitrate on the right.
3. Choose the destination (a folder when using Individual Clips).
4. Click export; progress shows in place, and the result can be revealed in Finder when done.

---

## 6. Timeline editing in detail

### 6.1 Selection and multi-select

- Click a clip: selects just that clip and shows the clip inspector.
- Command-click: adds a clip to, or removes it from, the selection.
- Click empty timeline space: clears the selection.

A multi-selection can be moved, split, deleted, ripple-deleted, or copied in one action.

### 6.2 Moving and changing tracks

- Drag horizontally to change the timeline start; hold Shift to keep the horizontal position while changing tracks.
- Drag vertically onto a same-type track to move and switch tracks in one gesture.
- Video clips only go on video tracks, activity clips only on activity tracks; locked tracks accept nothing.
- When the target track has clips, the app finds the nearest gap that fits — it never overwrites or pushes existing clips.

### 6.3 Copy, cut, and paste

- `⌘C` copies, `⌘X` cuts the selected clips.
- `⌘V` pastes at the playhead.
- `⇧⌘V` paste-inserts: pastes and shifts subsequent clips on the track later to make room.
- Right-click empty timeline space and choose Paste to paste at the clicked position.

### 6.4 Snapping

Moving and trimming snaps to: the timeline start, the red playhead, and other clips' heads and tails. A guide line with the snap source appears on a hit. To align to an exact moment, park the playhead there first, then drag the clip edge onto the red line. The magnet toggle in the timeline toolbar disables snapping temporarily.

### 6.5 Delete and ripple delete

- `⌫`: deletes the selected clips, keeping the gap.
- `⇧⌫`: ripple-deletes the selected clips and closes the gap.
- `⌘Z` undo, `⇧⌘Z` redo.

Ordinary edits never ask for confirmation; destructive operations — like deleting a library asset the timeline still uses — do.

### 6.6 Multiple video tracks

When several video tracks have clips at the same moment:

- The upper enabled video track covers the lower ones.
- When the covering clip ends, the lower video resumes from its own continuous source time.
- Exported audio follows whichever video clip is visible.

This is full-frame covering — not picture-in-picture or video blending.

### 6.7 Multiple activity tracks

- Every enabled activity track participates in compositing.
- Different tracks can use different activity files, layouts, and distance units.
- Upper activity tracks draw last — put components you want emphasized on upper tracks.
- Avoid overlapping clips within one track; if they overlap, the last matching clip in the track wins.

### 6.8 Track management

Track headers support renaming, enabling/disabling, locking/unlocking, and deleting empty tracks. Disabled tracks are excluded from preview and export; locked tracks block moving, trimming, splitting, deleting, and drops. With many tracks, the track area scrolls vertically.

### 6.9 Temporarily disabling clips

- Select one or more clips and press `D` to toggle enabled/disabled.
- Disabled clips dim but keep their track and position — handy for comparing alternatives.
- Disabled clips are excluded from preview, export, edit-point navigation, and export preflight.
- Disabling a clip and disabling a whole track are independent switches.

### 6.10 Zoom and navigation

- Zoom horizontally with the control at the top right of the timeline or by pinching on the trackpad; zoom anchors on the red playhead.
- `↑` / `↓` jump to the previous / next edit point and bring the playhead back into view.
- The playhead can be clicked or dragged on the ruler and snaps near clip edges.

### 6.11 What gaps look like

| Timeline state | Preview / composited video | Transparent overlay |
| --- | --- | --- |
| Video + data | Data over video | Data layer only, transparent |
| Video, no data | Original video | Fully transparent |
| No video, data | Data on a black canvas | Data layer on transparency |
| Neither | Pure black canvas | Fully transparent |

Activity clips can therefore be much longer than video clips — the recommended structure when one recording covers the whole activity and footage exists only for parts of it.

---

## 7. Data components and the canvas

### 7.1 Adding and selecting components

Browse or search all components in Library > Components; double-click to add at the default position, or drag onto the canvas. The Add menu at the top of the inspector also works. Components whose source data is missing stay visible but cannot be added — no GPS means no route, no heart-rate field means no heart rate.

On the canvas:

- Click to select a component; Command-click to multi-select.
- Click a part inside a component — its label, value, or unit — to edit that part directly; the inspector switches to the matching style settings.

### 7.2 Inspector and quick controls

With a component selected, the inspector splits into layout, style, and data sections, with a quick-controls row always showing X/Y position, scale, length (for components that support it), and a visibility toggle. Adjustable properties include:

- Position, size, and length.
- Label, unit, icon, and custom text.
- Panel, border, opacity, and line width.
- Font, font size, and color (settable per part).
- Decimal places, gauge range, tick marks, and weather icons.

The meter/kilometer unit for distance components (distance value, distance progress) is set in their own inspectors.

### 7.3 Arrange, align, and reuse styles

The Arrange menu and the canvas context menu provide:

- Layering: Bring to Front, Bring Forward, Send Backward, Send to Back (`⌘⌥↑` / `⌘⌥↓` for forward/backward).
- Alignment: left, horizontal center, right, top, vertical center, bottom.
- Distribution: horizontal and vertical (needs three or more components).
- Copy Style / Paste Style: apply one component's look to others quickly.
- Delete: acts on the whole selection.

### 7.4 Smart guides, grid, and safe frame

- While dragging, smart guides snap to other components' edges and centers, the canvas center lines and thirds, and the safe frame.
- Preview > Show Grid displays a purely visual reference grid; there are no row/column settings to configure.
- The safe-frame inset lives in Settings (0–20%, default 5%) and keeps components away from the frame edges.

### 7.5 Per-clip layouts

With an activity clip selected, the inspector offers:

- The meter/kilometer unit for that clip.
- "Use current layout": stores the current canvas layout on that clip.
- "Use default layout": makes the clip inherit the project default.

### 7.6 Layout templates

Library > Templates saves, applies, sets default, imports, and exports user layout templates:

- Exports use the dedicated `.dlspreset` extension; imports also accept legacy `.json` presets.
- Useful for reusing one visual style across races, keeping separate landscape and portrait templates, or migrating to another Mac.

Applying a template replaces the current canvas layout — check whether current changes need saving first. The app ships no built-in templates; the welcome window shows only templates you saved or imported.

---

## 8. The weather component

The weather component needs:

- An activity file with time and GPS.
- A valid OpenWeather API key.
- Network access for the first fetch.

The first time you add a weather component without a key, the app shows a setup guide. Click "Get API Key" to register an OpenWeather account, enable One Call 4.0 for the key (it has a free daily quota), then paste the key into the inspector and refresh. New keys can take a while to activate. The key is stored only on this Mac.

Once fetched, weather data is cached into the project. Loaded weather is never lost if the network drops mid-render, and reopening the project does not require another fetch.

If the project contains a weather component whose data hasn't loaded yet, starting an export raises a confirmation. Wait for the weather to display properly before exporting; continue only if you're sure you don't need it.

---

## 9. The Export Center

Press `⌘E` or click Output in the top-right corner. Settings, progress, and results all live in this one window.

### 9.1 Presets

The preset list on the left:

- **Built-in presets**: Transparent Overlay · ProRes 4444, Transparent Overlay · HEVC, Composited Video · 4K HEVC, Composited Video · 1080p H.264, Vertical Video · 4K HEVC.
- **My Presets**: save the current settings under a name for reuse; deletable. User presets store concrete resolution/frame-rate values.

After picking a preset you can still override any option on the right.

### 9.2 Transparent overlay vs. composited video

Choose the transparent overlay if:

- You still need grading, captions, transitions, or speed changes.
- You want to hide or replace the data layer at will in your editor.
- You need the same data layer over different cuts of the video.

Choose the composited video if:

- The timeline is final and you don't want another editor.
- You need a shareable file fast, with the original audio preserved.

### 9.3 Render scope

- **Full Timeline**: the whole timeline as one continuous file.
- **Individual Clips**: composited video exports one file per video clip; transparent overlay exports one per activity clip. Requires choosing an output folder; files are numbered.

To export only part of the timeline, first shape the timeline with trims, splits, and deletions.

### 9.4 Codec advice

Transparent overlay:

- HEVC/H.265 Alpha: smaller files, fine for regular post work.
- ProRes 4444: much larger, for high-quality intermediates and wider professional pipelines.

Composited video:

- HEVC/H.265: efficient compression, the recommended default.
- H.264: broadest compatibility for older playback devices.

### 9.5 Size and frame rate

- Presets cover landscape and portrait sizes from 3840×2160 down to 720×1280, at 23.976–60 fps.
- Custom sizes support Lock Aspect Ratio — changing width updates height.
- With video present, prefer the source resolution and frame rate. Mixed landscape/portrait clips each scale proportionally and center, with black bars filling the rest.

### 9.6 Bitrate

The default is 12000 kbps. As a guide:

- 1080p: 8000–16000 kbps.
- 4K: 30000–80000 kbps.
- ProRes 4444 doesn't follow delivery-bitrate logic; files are simply much larger.

### 9.7 Export preflight

Before exporting, the app checks:

- Whether the timeline has usable video or activity clips.
- Whether any media is offline.
- Whether any clip reads beyond its source.
- Whether the codec matches the overlay/composited mode.
- Whether weather components are ready.
- Whether the output path is writable.

If the export button is disabled, read the reason shown next to it instead of clicking repeatedly.

---

## 10. Saving, opening, and recovering projects

### 10.1 Saving

- Save: `⌘S`; Save As: `⇧⌘S`; Open project: `⇧⌘O`.
- Projects default to the `.dlsproj` extension; legacy `.json` projects still open.
- Saved projects appear in File > Open Recent; the welcome window can also open or locate recent projects.

A project file stores:

- The media library and asset references.
- Track names, enabled and locked states.
- Clip positions, source in points, durations, layouts, and distance units.
- Export size, frame rate, codec, bitrate, and render scope.
- The playhead position and fetched weather data.

The output destination path is not stored in the project.

### 10.2 Moving projects

If the project file sits in the same folder as (or a parent of) its media, the app records relative paths as a recovery aid. When moving across machines, put the project and all media in one folder and copy it whole.

### 10.3 Relinking offline media

When a file is moved, renamed, or loses permissions:

1. The media library shows Offline with the reason.
2. Click the link button or "Relink…".
3. Pick the correct replacement file.
4. The app validates the video metadata or parses the activity file first.
5. On success, clip positions, trims, and layouts are preserved.

Relinking supports undo/redo. A wrong file never silently replaces the original.

---

## 11. Case studies

### Case 1: Camera starts first; the watch starts 49 seconds in

Scene: the video starts during warm-up; the watch starts at `00:49.000` of the video.

Goal: keep the first 49 seconds of video with no data; the overlay starts changing after 49 s.

Steps:

1. Put the video clip at timeline `00:00.000`.
2. Put the full activity clip at `00:49.000`.
3. Park the playhead at 49 s and drag the activity clip's head onto the red line — or type `00:00:49.000` in the inspector.
4. Play from 45 s and confirm the data appears at the right moment.
5. A composited export shows plain video for 49 s; a transparent overlay is fully transparent for 49 s.

Lesson: don't trim the start of the activity file just to "align". The natural expression is simply an activity clip that starts 49 seconds late.

### Case 2: Recording starts 5:30 after the activity

Scene: the watch starts first; video `00:00` corresponds to activity `05:30`.

Recommended structure:

1. Put the full activity clip at timeline `00:00`.
2. Put the video clip at `05:30`.
3. If you don't want the leading data-on-black section, trim the first 5:30 off the activity clip with its left handle, then move both clips back to the timeline start together.
4. If you want 5:30 of route/data animation before cutting to footage, keep it as is.

Result:

- The composited video shows a data layer on black for 0–5:30, then the footage.
- The transparent overlay stays transparent throughout, drawing only data.

Lesson: the timeline may start with a gap, so negative offsets are never needed. Place later media at the relative time it really appeared.

### Case 3: A long activity with three scattered clips

Scene: one ~110-minute FIT and three videos sorted by name, with large gaps between them and two pauses in the FIT.

Recommended steps:

1. Multi-select and import the three videos, then the FIT; with reliable recording times the app places them automatically.
2. Keep the activity clip covering the full wall-clock duration.
3. Play the start of each video clip and verify alignment against junctions, landmarks, or the watch readout; nudge with `,` / `.` if needed.
4. Keep videos on V1; use V2 for comparing or temporary covering.
5. Don't split around FIT pauses; distance and speed hold during a pause and continue after.
6. A full composited export shows data-on-black where there is no video; an overlay export stays transparent where there is no data.

Lesson: the activity clip is usually the longest clip on the timeline, and the videos are scattered visual evidence inside it. That reflects real activity time far better than splicing three clips into fake continuous footage.

### Case 4: A transparent data layer for DaVinci Resolve

Goal: keep editing, grading, and audio in DaVinci; DataLayer Studio only produces the data layer.

Steps:

1. Arrange video and activity clips at the same relative positions as the DaVinci timeline.
2. In the Export Center pick "Transparent Overlay · HEVC" — or "Transparent Overlay · ProRes 4444" for a high-quality intermediate.
3. Match the size and frame rate to the DaVinci project.
4. Export the full timeline.
5. In DaVinci, place the overlay on the track above the footage, aligned to the same start.

Verification:

- A black background in a normal player does not mean Alpha failed.
- Check transparency on DaVinci's upper track.
- Never time-stretch the overlay afterwards, or the data desyncs.

### Case 5: Batch-exporting social clips from a long timeline

Goal: several independent short videos from one activity.

Steps:

1. Shape multiple video clips with splits and trims.
2. Make sure the data track covers each short clip correctly.
3. Choose render scope Individual Clips in the Export Center.
4. Pick an output folder.
5. Composited export writes one file per video clip; overlay export writes one per activity clip.

Lesson: if the clips need different layouts, give each activity clip its own "current layout"; if the style is uniform, let them inherit the default.

### Case 6: Media offline after copying the project to another Mac

Steps:

1. Open the `.dlsproj` project.
2. Click Relink on every asset marked offline.
3. Pick the matching video or FIT on the new machine.
4. Confirm clip positions, source in points, and layouts are intact.
5. Save the project once to refresh access permissions on the new machine.

Lesson: put the project file and all media in one folder before copying — recovery is then trivial.

---

## 12. Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Open video | `⌘O` |
| Open activity file | `⌘F` |
| Open timeline project | `⇧⌘O` |
| Save timeline project | `⌘S` |
| Save timeline project as | `⇧⌘S` |
| Open Export Center | `⌘E` |
| Cancel export | `⌘.` |
| Play / pause | `Space` |
| Refresh preview | `⌘R` |
| Previous / next edit point | `↑` / `↓` |
| Split at playhead | `⌘B` |
| Enable or disable selected clips | `D` |
| Copy / cut selected clips | `⌘C` / `⌘X` |
| Paste / paste insert | `⌘V` / `⇧⌘V` |
| Nudge selected clips one frame | `,` / `.` |
| Delete, keeping the gap | `⌫` |
| Ripple delete | `⇧⌫` |
| Multi-select clips or components | `Command` + click |
| Undo / redo | `⌘Z` / `⇧⌘Z` |
| Zoom preview in / out | `⌘+` / `⌘-` |
| Reset preview zoom | `⌘0` |
| Fullscreen preview | `⇧⌘F` |
| Show or hide Library / timeline / inspector | `⌥⌘1` / `⌥⌘2` / `⌥⌘3` |
| Bring component forward / send backward | `⌘⌥↑` / `⌘⌥↓` |
| Open debug console | `⇧⌘D` |

---

## 13. FAQ

### 13.1 Data and video don't line up

Check in this order:

1. Use one clear matching event — never "looks about right".
2. Check the timeline starts of both the activity and video clips.
3. Check whether clips are trimmed; trimmed clips need the "Source in point" taken into account.
4. Check whether the FIT contains pauses — activity time and wall-clock time can differ.
5. Play 5–10 seconds on both sides of the match point.

### 13.2 Auto-alignment didn't happen

Auto-alignment relies on the video's recording-time metadata and the activity file's start time. Transcodes, editor re-exports, and files downloaded from chat apps often lose the original recording time. Align manually in that case; editor-exported videos won't trigger false auto-alignment.

### 13.3 A component shows `--`

Possible reasons:

- The activity file lacks the field.
- The current time is outside the activity clip.
- The activity clip uses a different layout.
- Weather hasn't loaded or the cache is unavailable.

### 13.4 The exported overlay looks black

Many players don't display Alpha. Check on an upper track in DaVinci Resolve, Final Cut Pro, or Premiere. Cross-check with ProRes 4444 if in doubt.

### 13.5 The export button is disabled

Read the hint in the Export Center. Common causes:

- No clips of the required type on the timeline.
- Offline media.
- A clip reading beyond its source range.
- A non-Alpha codec in overlay mode, or an Alpha codec in composited mode.
- No output destination or folder chosen yet.

### 13.6 Why are gaps black in the composited video

By design: normal video has no Alpha channel. Gaps use a black canvas; if activity data exists there, it draws on the black canvas. Use the transparent overlay when you need transparency.

### 13.7 Can weather be lost mid-render if the network drops

No. Once fetched, weather is cached with the project and used from there. The only risk window is starting an export before weather ever loaded — the app asks for confirmation then.

### 13.8 Long exports fail

Check:

- Free space on the destination disk.
- Write permission on the output folder.
- Whether resolution, frame rate, or bitrate are too high.
- Whether the system can decode the source video.
- The "export" entries in the debug console.

DataLayer Studio streams frame by frame and never caches whole videos in memory, but 4K, long durations, and ProRes 4444 still need plenty of disk space.

---

## 14. Command line

The GUI is for multitrack editing; the CLI is for automation and reusing existing projects.

### 14.1 Single video + single activity file

```bash
swift run overlay \
  --video /path/to/run.mov \
  --fit /path/to/activity.fit \
  --output /path/to/overlay.mov
```

Common options:

```text
--export-mode overlay|video
--width 1920 --height 1080
--fps 30
--codec hevc-alpha|prores-4444|hevc|h264
--bitrate 12000
--distance-unit km|m
--layout-preset "Race Layout"
--skip-fit-crc
--inspect
```

The single-source CLI still accepts `--fit-start`, `--sync-video` / `--sync-fit`, and the legacy `--offset`; these are CLI compatibility options — the app itself has no separate sync page.

### 14.2 Exporting a timeline project

```bash
swift run overlay \
  --timeline-project /path/to/project.dlsproj \
  --output /path/to/output.mov \
  --export-mode video
```

With `--timeline-project`, don't mix in `--fit`, `--video`, sync options, or layout presets. The project's multitrack structure is read by the same core rendering engine.

---

## 15. Pre-export checklist

- [ ] All videos and activity files in use are online.
- [ ] Video and activity data align at least at one clear event.
- [ ] FIT pause sections behave as expected.
- [ ] Upper video tracks cover exactly what they should.
- [ ] Activity clips use the right layouts and distance units.
- [ ] Weather has loaded, or you're sure you don't need it.
- [ ] Data components don't cover subjects, captions, or safe areas.
- [ ] The timeline contains exactly what should be exported (extra clips deleted or disabled).
- [ ] Size, frame rate, codec, and bitrate suit the target platform.
- [ ] The transparent overlay and your editing timeline start at the same moment.
- [ ] Enough disk space and write permission at the destination.
- [ ] The project is saved with `⌘S`.

Run through this list before long or 4K exports — it prevents most rework.
