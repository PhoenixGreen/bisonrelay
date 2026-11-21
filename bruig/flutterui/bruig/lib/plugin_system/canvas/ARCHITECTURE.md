# The Canvas: how it is built

The Canvas is Bison Relay's section for composing pictures, charts,
animations, video, music, books and games, and for turning one into something
to publish or send. This is the map: what the parts are, the rules between
them, and where to look first when changing something.

`canvas.dart` is the entry point. Code elsewhere in the app imports it and
nothing beneath it. The whole section sits behind a switch in Settings
(`canvas_preferences.dart`): it is app code that can be turned off, not a
plugin in the sense of `lib/plugin_system`'s capabilities.

## Layers

| Folder | Holds | May import |
|---|---|---|
| `model/` | The document: its scenes, elements, motion, sheets, settings. Data and the rules on it, read and written as JSON. | Dart, `dart:ui`, `flutter/foundation` and `flutter/painting`. Nothing else here. |
| `render/` | A document and a frame number, drawn into a `ui.Canvas`. | `model/`; `storage/` for the stores it reads pictures from. No widgets. |
| `media/` | Sound, speech, MIDI, video and code runs, live. `media/mix/` is the mix engine the editor and an export share. | `model/`, `storage/`. |
| `storage/` | Documents, pictures, media and presets on disk; the network. | `model/`. |
| `export/` | A document into files (PNG, GIF, video, audio, PDF, SVG, EPUB) and bundles to send. | `model/`, `render/`, `media/`, `storage/`. No widgets. |
| `presets/` | Built-in canvases, element presets, background looks. | `model/`. |
| `ui/` | The page: screen, controller, stage, timeline, panels. | Everything. |

The rule that matters most: `render/` and `export/` know nothing of widgets,
a `BuildContext` or the app's theme. The stage on screen and the exported
file are drawn by the same code (`paintCanvasDocument`, in
`render/scene_renderer.dart`), so what is exported is what was seen, whatever
the reader's theme.

`test/canvas_layers_test.dart` holds the code to this table, and to the rule
that the app outside imports `canvas.dart` and nothing beneath it. The
imports that break the table today are listed in that test, each with its
reason, as debts to pay off; nothing may be added to the list without one.

### `ui/`

| Folder | What |
|---|---|
| (top) | `canvas_controller.dart` and what every part uses: `controls.dart`, `canvas_dialogs.dart`, `element_factory.dart`, `element_settings.dart`, presets, studio colours. |
| `controller/` | The controller's own parts, as `extension` files (see below). |
| `stage/` | The canvas being edited. `canvas_stage.dart` holds its state, lifecycle, keys and build; what it does is in parts by concern: `stage_coordinates`, `stage_hit_testing`, `stage_press`, `stage_drag`, `stage_release`, `stage_vector_tools`, `stage_picture_tools`, `stage_framing`, `stage_3d_view`. Drawing is `stage_painter.dart` and its parts. |
| `screen/` | The editor around the stage: settings bar, dock, play bar, publishing, the file player. |
| `timeline/` | Rows, channels, scenes, markers, keys, automation. |
| `mixer/` | The mixer, its strips and devices, the clip slots. |
| `sound/` | Clip editor, piano roll, instruments, pitch, speech. |
| `motion/` | Motion clips, the Chain, curves, the animation panel. |
| `data/` | The Data Studio: sheets, tables, charts. |
| `code/` | The Code element's editor, studio and live preview. |
| `character/` | Character Studio's panels. |
| `drawing/` | Pictures, vectors, sprites, tiles, backgrounds. |
| `picking/` | Bringing files, assets and stock in. |
| `score/`, `game/` | The score studio; games while they are played. |
| `settings/` | Each element's settings panel, built from `panel_kit.dart`. |
| `sidebar/` | The sidebars: files, assets, presets, layers and the rest. |

## The document

`CanvasDocument` (`model/canvas_document.dart`) is immutable. Beside it are
its scene (`canvas_scene.dart`, with `scene_transition.dart` and
`scene_camera.dart`), its background (`canvas_background.dart`) and what
every element shares (`canvas_element.dart`). It holds:

- its **scenes** (`CanvasScene`), each with elements, a background, a length
  and a transition, and an optional **master** scene whose elements show
  over every scene;
- the **elements** (`model/elements/`), one class for each `ElementKind`,
  each with an `ElementBase` (place, size, turn, name, motion) and its own
  fields;
- **sheets** (`DataSheet`) that tables and charts are views of;
- the **session** (clip slots), cast, cues, scores and audio settings.

Every change makes a new document. The controller applies it and keeps the
old one for undo.

### Saved form

A document is JSON (`toJson`, `CanvasDocument.fromJson`, `elementFromJson`).
Reading never refuses a document. Every field has a fallback for a missing
or mistyped value (`jsonString`, `jsonInt`, `jsonSpec`...), so an older
build reads a newer file as well as it can and a newer build reads an older
one. `canvasFormatVersion` is written but is never used to refuse a file.

A document can come from somebody else, so reading also bounds it: numbers
must be finite (`finiteJson`); sizes, counts and lengths are clamped; a scene
holds at most `maxSceneElements` elements, a document `maxScenes` scenes, an
element's words `maxTextLength` characters, and a sheet `DataSheet.maxCells`
cells. Strings are cut as they are read: any to `maxTextLength`, an id
(`jsonId`) to 200 characters, a name, label, title or font (`jsonLabel`) to
1,000; lists to a count of their own (a chart's points, a tile map's
layers). Add a limit like these to any new field a received file could make
huge, and read it through these helpers, never with a cast that throws.

The readers and the limits on one field are in `model/json_read.dart`
(`jsonString`, `jsonList`, `maxTextLength`...); the limits on a whole canvas
(scenes, elements, frames) are in `model/canvas_limits.dart`.

Three things about the saved form that are easy to get wrong:

- **A default is also what a file means by leaving the field out.** `toJson`
  leaves out a field that holds its default, and `fromJson` puts the default
  back. So changing a default changes every canvas already saved with it.
- **A document of one scene is saved without a scene list.** Its elements,
  length and actions go at the top level and its name, hold and transition
  under `"scene"`. With a scene list, nothing of a scene is at the top. Which settings that form can carry is worked out from
  what the scene writes (`CanvasDocument._plain`), so a setting added to
  `CanvasScene` makes a scene list by itself; `test/canvas_document_test.dart`
  holds every scene setting to coming back.
- **An element is read by kind in one place**, `elementFromJson`
  (`model/element_reading.dart`). A new kind is added to its switch.

`test/canvas_element_reading_test.dart` holds every kind to this, from the
samples in `test/support/element_samples.dart` (every kind, each synth
module, each chart type): read back as written, a wrong type at any key
never throws, a 2 MB string or 400,000-entry list at any key comes back
bounded. A new kind, or a new sort of one, belongs in those samples.

### Motion

An element moves by **motion clips** (`MotionClip`, `model/motion.dart`).
They are placed on its timeline and can be layered, looped and shared
between copies. Keyframes made on the Chain's Keyframes card live in the
element's own track and are kept as keyframes. `render/motion_document.dart`
works out where everything is at a frame (`motionTimesOf`). An element's
arrival and exit are its own clips (`model/own_motion.dart`).

## The editor

`CanvasController` (`ui/canvas_controller.dart`) is the editing session. One
lives for the app's lifetime (`main.dart` provides it), so leaving the page
must stop anything it set running. It is a `ChangeNotifier`. Its behaviour is
in `extension` parts under `ui/controller/` (scenes, keyframes, mixer,
session, game, code runs and so on). A feature's own state sits at the end of
its part, in a small class the controller holds one of (`_VectorState` in
`vectors.dart`, `_PlaybackState` in `playback.dart`...); the class itself
keeps what several parts share, its statics and its overrides. A change goes
through `apply` or one of the helpers built on it (`replaceElement`,
`addElement`...), which records undo and notifies.

**Big widgets in parts.** A `State` class that outgrew one file keeps its
fields, lifecycle and `build` in its own file and puts its behaviour in
`part` files beside it, each an `extension` on the class: the stage, the
charts and table designers (`data/charts_*`, `data/table_*`), the mixer's
desk and device chain, the piano roll, the clip editor, the channels, the
Speech device (whose sections take one `_SpeechView` worked out per build). The
class overrides `setState` so its parts may call it, and keeps any method
used as a listener: an extension's tear-off is a new closure each time, so
`removeListener` would not find it.

**Collections by topic.** A file of many small widgets or functions keeps
what the rest is built round, and its topics are parts beside it, named
after it: `controls.dart` (controls_layout, _groups, _fields, _buttons,
_pickers), `settings/panel_kit.dart`, `settings/text_settings.dart`,
`sound/instrument_editor.dart`, the mixer (`canvas_mixer_*`,
`mixer_plugins_*`, `mixer_devices_*`), `render/scene_renderer.dart`,
`render/paint_util.dart`, `render/procedural/pitch.dart` and
`export/epub_layers.dart`. Code that imports the file still sees all of it.

**Listening.** Most widgets listen to the controller. Two things notify it
many times a second: the steps of a gesture (a drag, typing on the canvas:
`apply(transient: true)` between `beginInteraction` and `endInteraction`) and
frames of play. A widget that shows neither listens to `controller.chrome`
instead, which passes over both and hears the notification at the gesture's
end or when play stops: the settings band, the page, the dock. A widget that
shows only the playhead follows `playheadMoved` (the play bar's readout, the
timeline's ruler and line).

An element's settings panel goes one step further while a pointer is held
in a gesture (a drag on the canvas, a number scrubbed): the section the
pointer went down in is built as usual, and so, for a drag on the canvas,
is any section that `followsStage` (Layout); the rest keep what they built
(`PanelHold`, `ui/settings/panel_kit_hold.dart`). When the pointer lifts,
or anything happens that is not a gesture's step, the whole panel is built
again, so no control is left holding the element as it was.
`test/canvas_panel_hold_test.dart` holds this to a budget.
`test/canvas_rebuild_budget_test.dart` counts
what the whole editor builds for each, and fails when something goes back to
being rebuilt by them.

Widgets read the controller and call it; they do not change the document
themselves. Settings panels are built from `ui/settings/panel_kit.dart` and
`element_panel.dart` (`CanvasSection`, `elementPanel`, rows and steppers), so
every element's panel looks and behaves alike; `ui/settings/README.md` says
how a panel is laid out.

Drawing is cached where it is expensive: procedural backgrounds
(`ProceduralCache`), rasterised elements during a gesture (`RasterCache`) and
pictures (`CanvasImageStore`).

## Preferences

`CanvasPreferences` (`canvas_preferences.dart`) is what is remembered about
the app on this machine, as against what is saved in a canvas: whether the
feature is on, the canvas last open, how the panels were left. To add one,
declare a `_Saved` value there, give it a getter and a setter, and add it to
`_saved`. `test/canvas_preferences_test.dart` holds each key and the form it
is stored in, since changing either loses what somebody had set.

## On disk

Everything lives under the library root (`CanvasStorage`), the user's Canvas
folder:

- **Documents**: `CanvasStorage`, one level of folders. Names go through
  `sanitizeName`.
- **Pictures**: `CanvasAssets`, stored under ids made from their contents
  (`idMatches` checks a received one).
- **Media**: `CanvasMedia`, for sound, video, vectors and 3D models, each kind
  in its own folder with a size limit.
- **The Assets library**: `CanvasLibrary`, `assets.json` beside the canvases.
  What is added there stays until removed there. `CanvasLibrary.tidy`, run
  after saves, deletes stored files that no saved canvas, open canvas or
  library asset uses, and never one newer than `sweepGrace`.
- **Presets**: the preset stores under `storage/`.

Writes are made whole or not at all (a `.part` file renamed into place, or
`writeWhole`), so a crash leaves the old file as it was.

## Sound and code

- **Sound.** `AudioEngine` (`media/audio_engine.dart`) is the output stream,
  SoLoud underneath. Mixing, effects and automation are Dart (`media/mix/`),
  and the same graph renders an export. Speech engines (Kokoro, Qwen,
  ElevenLabs, espeak) are under `media/`.
- **Code runs** (`media/code_run_host.dart`, `media/code_dart_runner.dart`):
  - web pages run in a hidden browser;
  - Python (Pyodide) and Go (Yaegi, built by `tools/yaegi_wasm`) run from a
    loopback server;
  - Dart runs on an isolate;
  - Flutter apps are built with flutter_eval (a patched copy in
    `third_party/`, see `PATCHES.md`).

## Sharing

A canvas is sent as a **bundle** (`export/canvas_bundle.dart`): a zip of
`canvas.json` and the pictures and media it uses, stored, not compressed.
`packCanvas` writes one; `unpackCanvasFile` reads one on an isolate it kills
after `unpackLimit`. A plain `.bcanvas` of JSON is read too.

## Security

Treat every received canvas, and every file a canvas names, as written by
somebody hostile. The rules below and where they are kept:

- **Reading a document is bounded.** See "Saved form" above.
- **Bundles.** Each entry is inflated against a byte budget (`_contentOf`),
  never trusting the sizes the zip claims. Only the last segment of an
  entry's name is used, and ids are checked before they become paths.
  `_received` drops what a received canvas must not bring: links to the
  reader's own text documents, and its Run panels' DartPad switch.
- **The network.**
  - Every fetch goes through `canvasGet` and `readCapped`
    (`storage/canvas_network.dart`): https only, headers only to the host
    they are for, size and time limits.
  - Nothing is fetched while the fetching switch is off, and nothing while a
    proxy is set, since the fetch would not go through it.
  - A data source's host is asked about before the first fetch from it
    (`DataHosts`).
- **Local files.**
  - A data source reads only a file picked here or agreed to when asked
    (`DataFiles`, checked in `loadJson` itself).
  - A map's, tileset's or sprite sheet's notes name only files near them
    (`nearFile`, `storage/tiled_maps.dart`).
  - Store ids match strict patterns before becoming paths.
- **Other programs.** ffmpeg reads stored media through `ffmpegInput`
  (`-protocol_whitelist file`). No shell is used anywhere, and no argument
  comes from a document unchecked.
- **Links.** Opened only through `webLink` (http, https and mailto), after
  asking.
- **Code.**
  - Nothing runs that was not asked for with Run on this machine: a received
    Run panel's live preview opens only once it has been run here.
  - Pages are `sealed` (`model/code_runners.dart`): a Content-Security-Policy
    first, with no network but the loopback run server. Browsers use
    `sealedSettings` and `stayOnPage`.
  - A Flutter app's calls stop after `flutterOpLimit` steps (the patched
    dart_eval's `Runtime.opLimit`).
  - A Dart run stops after `runLimit`, or past `dartMemoryLimit` more memory.
  - Output is capped (`maxCodeLogs`, `maxCodeLogLength`).
  - A task card's own patterns are counted on a killable isolate
    (`PatternCounts`), never in a painter.

## Tests

- **Where they are.** `test/*_test.dart`. Shared helpers are in
  `test/support/`.
- **A widget under test** goes inside `canvasApp` / `pumpCanvasApp`
  (`test/support/canvas_app.dart`): the theme, snack bar and Canvas
  preferences every screen has, a MaterialApp and a Scaffold.
  - Set the screen with `setTestScreen` and the text size with
    `setTestTextScale`.
  - Wait for real I/O with `pumpUntil`, not a fixed count of pumps.
- **Disk.** A test that touches disk points `CanvasStorage.rootOverride` at a
  temporary folder, and deletes it with `deleteTempDir`.
- **Sound.** Audio uses `FakeEngine` (`test/support/canvas_audio_fake.dart`).
- **The whole suite** runs as bundles: `sh test_bundles/run.sh`.
  - `test_bundles/generate.dart` shares the files into 16 bundles by how long
    each took (`timings.json`). Run it after adding or removing a test file;
    `test_bundles_cover_test.dart` fails until you do.
  - Files that change the process for good (fonts registered, a decoder
    loaded) are listed in `generate.dart` to run alone.
  - Each file in a bundle starts from `betweenFiles` (`test_bundles/reset.dart`).
    Anything a file can leave behind for the next belongs there.
- **While working**, `sh test_bundles/quick.sh` runs the model tests alone
  (every file with no widget test, one compile) in about half a minute.
  The whole suite is still the check before committing.
- **Text sizes.** Panels are checked across text sizes (0.65× to 1.5×; the
  author runs a larger one than the default), so a layout that only fits at
  one size fails a test. `sweepSizes` (`test/support/canvas_app.dart`) lays
  one pumped tree out at each size in turn, far cheaper than a test for
  each.

## Writing the code

- **Never hand a torn-off extension method to something that compares it.**
  A method of an `extension` torn off (`_gameKey` passed without calling
  it) is a new closure every time, never equal to the last. So
  `removeListener(_x)`, `removeHandler(_x)` and `if (hook == _x)` silently
  fail when `_x` lives in one of the controller's or a widget's parts. Make
  the closure once, in a field of the class (`late final _gameKeyHook =
  _gameKey;`), and hand that out and compare against it. Listeners on a
  `State` stay methods of the class itself.

- **Comments say what and why**, never who asked or when: that is in the
  commit history, and in a comment it goes stale. Keep the comments that say
  why something must be so (the security notes, "off the UI isolate because...").
  They are the most valuable lines in the plugin.
- **New code belongs in its layer.** A widget in `render/` or `export/`, or a
  widget import in `model/`, is a wrong turn.
- **Run the analyser** (`flutter analyze lib/plugin_system/canvas test`) and
  the whole suite before committing.
