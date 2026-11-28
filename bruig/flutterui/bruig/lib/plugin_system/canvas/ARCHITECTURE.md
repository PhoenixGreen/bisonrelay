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
| (top) | `canvas_controller.dart` and what every part uses: `controls.dart`, `canvas_dialogs.dart`, `element_factory.dart`, `element_settings.dart`, `canvas_align.dart` (lining chosen elements or a picture's layers up with each other), presets, studio colours. |
| `controller/` | The controller's own parts, as `extension` files (see below). |
| `stage/` | The canvas being edited. `canvas_stage.dart` holds its state, lifecycle and build; its keys are a line each of the page's table in `stage_keys.dart` (see Keys, below); what it does is in parts by concern: `stage_coordinates` (the view made from the controller and layout, and the selection's box), `stage_hit_testing` (what is under the pointer), `stage_press` (every press, editing or playing, as a list of steps), `stage_synth_controls` (a synth module's keys, knobs, screens, jacks and cables, and the gestures on them), `stage_code_controls` (a Code or Run panel's controls, the gestures on them, and the editor and live preview over them), `stage_element_controls` (the other elements' controls: counter and its loose pieces, chart key, a chart's placed labels and a table's column rules as drawn and taken, video, speaker, metronome, a play task's steps, a flow link dropped), `stage_gesture` (what the pointer is doing, as one value from press to release: see Gestures on the stage, below), `stage_pending_click` (the clicks that ride on a press, made if it is let go where it began), `stage_drag` (a move, resize, slant or turn, from its start; a chart's label, a table's column rule, an anchor and the held marker's note dragged), `stage_release`, `stage_vector_tools`, `stage_path_points` (a selected path's points and handles: which is under the pointer, and one dragged), `stage_picture_tools`, `stage_framing` (a picture reframed inside its frame), `stage_guides` (guides taken, pulled from a ruler, moved and dropped), `stage_retouch` (the retouching stroke's preview and commit), `stage_team_players` (a team's players pressed and dragged), `stage_3d_view`, `stage_text_pieces`, `stage_layouts`. Like `stage_keys.dart`, fourteen libraries beside it do not import it (`test/canvas_layers_test.dart` holds all fifteen to that): `stage_hit_test.dart`, what is at a point of the document now; `picked_parts.dart`, the parts picked inside one element, which the keys act on too; `stage_transform.dart`, where the page sits in the window and how a stage point becomes a document point; `stage_scroll.dart`, the scroll views kept in step with the controller's pan; `in_place_edit.dart`, the one thing open for typing on the page (a text, a cell or a counter's Set field); `stage_rulers.dart`, the rulers: their strips, the gap between their numbers, and their drawing, in the painter or in a layer of their own over a page that scrolls; `stage_painter_inputs.dart`, what the painter draws from (see Adding a mark to the stage, below); and the seven libraries the painter draws with, one for each subject of the stage, each function given the values it reads: `stage_paint_page.dart`, the page (its shadow, the document with its facing leaf, a transition being watched or a game's change of scene, a held marker's label, a game's level, and the shade, border and hint round the page); `stage_paint_selection.dart`, the selection (its box, handles and turn knob, each element of several, a reused element's copies, the motion trail, the whole chain under a join, its anchors, and the move through the scene's camera they are drawn with); `stage_paint_elements.dart`, the marks on elements (every element's box, cameras, touch areas, text flow links and grips, a chart's labels, a table's column rules, a Layout's lines, knobs and numbers, a path's points); `stage_paint_tools.dart`, the tool in hand (a drawing's points, shape box and mirror lines, a picture's layers and warp grid, a picture being reframed, the knife, the caret, the marquee); `stage_paint_retouch.dart`, the retouching brush; `stage_paint_guides.dart`, the grid, guides and snap lines; and `stage_paint_kit.dart`, the pieces they are all drawn from (the handle blue `stageBlue`, a square handle, a round knob, a dashed line, a line dark under light, a rectangle or line put on screen). `stage_painter.dart` is the painter itself: the order these are drawn in. `stage_geometry.dart` is the sizes and places of what is grabbed, which the painter and the hit-testing share, and the steps a turn takes with Shift. |
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

### Colours

Each thing in the document that holds colours says which they are, in its
`mapColours` (an element's own in `mapOwnColours`): every colour it holds
is put through one function (`ColourMap`, `model/colour_map.dart`), told
whether it shows as things stand (an outline's colour while the outline has
no width does not). Where nothing comes back changed the very same object is
answered, all the way up to the document, so the controller's identity
checks see no edit. Three features use it (`model/canvas_palette.dart`):

- **Replace everywhere** (`CanvasController.replaceColour`) is
  `apply(document.mapColours(replacing(from, to)))`: every colour with
  `from`'s red, green and blue, shown or not, fully clear or not, becomes
  `to`'s, keeping its own opacity. It reaches Design-keyed colours, a copy's
  own Design value and a 3D character's colours. A colour that is nowhere
  leaves the document identical, and no undo step is made.
- **The colours in use** (`canvasColoursOf`, for a table matched to the
  canvas) counts only colours that show, against the backdrop drawn behind
  the current scene (its own, where it has one).
- **The colours counted** (`colourUsesOf`, offered outside as
  `CanvasScripting.colourUses`) are how often each colour that shows is
  used, the elements' apart from the backdrops', for Creative AI's style
  profile. The Canvas says which numbers are colours; the profile decides
  what to make of them, so it keeps no list of colour keys of its own.

Left alone on purpose, each with its reason at the field: a video's chroma
key and a picture's removal key (they must match the footage), a drawing's
handle colour, an element's row colour and a terrain's swatch (the
editor's), an eraser's paint (a mask). `test/canvas_colour_map_test.dart`
holds the visitor to reaching every colour of a fixture with one of each
(`test/support/colour_rich.dart`); `test/canvas_colour_coverage_test.dart`
maps every colour of every sample, built-in canvas and look (and, with
`CANVAS_LIBRARY` naming a folder, every canvas in it) to a sentinel and
fails on any colour-shaped number left as it was that is not on its short
list of known non-colours.

### Adding an element kind

Eight places, in this order. Four are asked for by the compiler (a `switch`
with no default), as is one method of the class (it is abstract); the rest
are not, and are marked.

1. **Its name**: a value of `ElementKind` (`model/canvas_element.dart`).
   The name is saved, so it is never changed afterwards.
2. **Its class**: `model/elements/<kind>_element.dart`, a `CanvasElement`
   with `kind`, `rebase`, `props` (its own fields as saved), `fromJson` and
   `copyWith`. If it keeps pictures or media, it lists them in `assetIds`
   and `mediaIds`, or the stores' tidy-up deletes them. *Not asked for.*
   Its colours, in `mapOwnColours` (`model/colour_map.dart`): every colour
   of its own fields, and of the specs it holds, put through the function
   and told whether it shows, the element itself coming back where none
   changed; one with no colour answers itself. A number that looks like a
   colour and is not (a packed word, a hash), or a colour that is the
   editor's or must match footage, is left out, with the reason at the
   field. *Asked for: the method is abstract;
   `test/canvas_colour_coverage_test.dart` says if a field is missed.*
3. **Reading it**: a case in `elementFromJson`
   (`model/element_reading.dart`).
4. **Making one**: its starting size in `defaultSizeFor` and a new one in
   `newElement` (`ui/element_factory.dart`).
5. **Drawing it**: a painter in `render/`, and a case in `paintElement`
   (`render/scene_renderer.dart`). *Not asked for: without the case it is
   simply not drawn.*
6. **Its settings**: a case in `elementSettings`
   (`ui/element_settings.dart`) and its panel in
   `ui/settings/<kind>_settings.dart`, built from the panel kit
   (`ui/settings/README.md`).
7. **Its icon**, in `iconForKind` (`ui/element_factory.dart`), and what
   the Add panel offers for it, in `addOffersFor` (`ui/element_offers.dart`):
   usually the kind itself, or nothing, with a comment saying how it is made
   instead. Where it stands in the grid is `_gridOrder` in the same file,
   the one list kept by hand; the Add panel's tests in
   `test/canvas_editor_layers_test.dart` fail if a kind that offers
   something is missing from it.
8. **Tests.** `elementSamples` (`test/support/element_samples.dart`) makes
   one of every kind through the factory, so the round trip, the hostile
   reading and the panel sweep cover it without being told. Add tests for
   what is its own.

As it needs them: what a press on it does, editing or playing
(`ui/stage/stage_press.dart`), the colours it offers the Chain
(`model/design_device.dart`), and anything it keeps while the canvas is open
(a part of the controller, forgotten in `_forgetDocument`).

### Motion

An element moves by **motion clips** (`MotionClip`, `model/motion.dart`).
They are placed on its timeline and can be layered, looped and shared
between copies. Keyframes made on the Chain's Keyframes card live in the
element's own track and are kept as keyframes. `render/motion_document.dart`
works out where everything is at a frame (`motionTimesOf`). An element's
arrival and exit are its own clips (`model/own_motion.dart`).

**Arrivals** are three types over one: an element's (`ElementAnimation`) and
a text's (`TextAnimation`) are both an `Arrival` (`model/elements/arrival.dart`),
which holds what they share (the preset in and out, direction and strength,
size, cut, curve, length, loop) and turns a preset's motion by them
(`specFor`, which everything that moves the thing reads). A part of a text's
words (`TextPartAnimation`) holds a whole `TextAnimation` beside its own
timing. So a setting both kinds have goes in `Arrival`, a text's alone in
`TextAnimation`, and parts get either with nothing more written, except a
key in the part's `toJson` if a part should keep it.

### Text: how a paragraph is laid out

A text's words are laid out in one place: `layOutWords`
(`render/paint_util_words.dart`) makes a `LaidOutWords` from everything
that decides where a glyph goes: the words (it applies the case), the type
(`TextSpec`), the width to wrap in, the parts, the scale, the pass (letters,
outline, or shadow and glow) and, for a fade, the box. It answers its size,
its lines, the boxes of a range of characters, the character at a point, how
many characters fit in a height, and draws itself. Laid-out paragraphs are
kept in one cache keyed by those inputs.

**The rule:** whatever draws or measures a text's words asks
`layOutWords`, and the parts are a required argument (an empty list where
there are none), so a site that leaves them out does not compile. Labels
with no parts (a chart's title, a cell, a button) use `layoutText` and
`paintTextInBox`, which are `layOutWords` with none.

**Which way a text's words are set** is decided in one place,
`TextElement.wordsSetIn` (`model/elements/text_element.dart`), which answers a
`WordsSet`: on a line, wrapped, in columns, in a box, in that order of
precedence (a line counts only while the line it names is on the page). A
text keeps the fields of every arrangement it has been given, so one taken off
its line gets its columns back; only the answer changes. Beside it, the
questions that cut across say what rules them out: `fittedIn`, `flowsOnIn`,
`showsPiecesIn`, `bodySlotIn`, `wordsFromDocument`. The painter, the flow, the
stage's clicks and handles, the editor, the panel and the EPUB maker ask these
rather than the fields, and `switch` over the answer with no default. A new
way of setting words is a case in `WordsSet` and its place in `wordsSetIn`;
the compiler then names every reader that must say what it does.

**The four ways words are set** share the styled words (`partRuns`, then
`partStyle` for each run) and the measure; each owns only how lines are
placed:

- *In a box* (`paintWordsInBox`): one layout at the box's width, placed by
  its vertical alignment.
- *In columns* (`paintTextInColumns`): one layout at a column's width, its
  whole lines packed into the columns (`columnRuns`).
- *Round something in the way* (`layoutWrapped`, `text_wrap.dart`): its
  own line breaking, since each line has runs of different widths between
  the obstacles; each candidate line is a layout of its words with their
  parts, and a line is as tall as the tallest thing on it, its runs on one
  baseline.
- *On a line* (`placeTextOnPath`): a letter at a time along the curve, each
  laid out by `layOutGlyph` in the part over it, cut from words already in
  their case (a letter alone cannot be title-cased).

A fade runs across the element's box in all four: the shader is drawn where
the canvas is, so one laid out over the box gives the columns, or the
wrapped lines, one fade between them; on a line it is laid over the letters
once drawn, across their box.

**The measuring sites** ask the same layout: Fit to box (`fitFontSize`),
what a chained box passes on (`_consumed`, `text_flow.dart`), a slotted
block's size (`_sizeOfText`, `text_items.dart`), the selection box of words
on a line (`visualBoundsOf`), the animator's pieces and the scramble
(`text_animator.dart`), and the parts' marks. The editor over the stage
styles its words with `partRuns` and `partStyle`, so its caret is where the
glyph is drawn.

**Adding something a part can change**: the field on `TextPart`, and one
line in `partStyle` (and in `_sizingOf` beside it, if it changes the words'
size). Every way of setting words, the measures and the editor then have
it.

### A shape's outline

A shape's outline is worked out in one place, `shapeOutline`
(`render/paint_util_shapes.dart`): its kind's path in its box, a square or a
circle drawn in the square in the middle of the box (`shapeBox`). The
painter fills and strokes it, a loop runs round it, wrapped words go round
it (`text_wrap.dart`) and the stage presses it (`StageHitTest.contains`).
Wrapped words lay it on the page through the element's turn and slant
(`BoxFrame.placePath`); the press takes the point back into the box through
where `paintElement` lays the shape out on the frame (`ElementPlace.unplace`)
and asks the outline as it rests. A press counts inside the
outline, filled or not, or within a line's slack of its edge (a distance on
the page, so shorter in the box by as much as the place stretches it:
`ElementPlace.stretch`), and on the
half of a thick outline that lies outside the box; the selection box and
its handles stay the box, and a selected shape is moved from anywhere in
that box, as a bowed line is.

What a kind of shape is (drawn square, has points, has corners given a
bubble's body, how far in its label is set, which way its front end points)
is asked of `ShapeKind`, each a switch with no default, so a new kind has to
answer them all. A speech bubble is drawn inside its box whatever its tail
does: the body gives up room on the tail's side for the tail or a thought's
whole trail, and a cloud's lumps reach the body's edge and no further.

A kind is chosen through `ShapeElement.withKind`, wherever it is chosen (the
tiles, the quick strip, a game's stand-ins): a square or a circle makes its
box square on its shorter side, about its middle, so what is drawn is the
whole box. Its kind then keeps it square (`keepsAspectByKind`, part of
`CanvasElement.keepsAspect`, which the stage's handles and the size fields
ask), and nothing saved says so: whether the person holds the proportions
(`lockAspect`) stays theirs through any change of kind. A resize held only
by the kind leaves the outline, corners, padding and words their size; one
the person holds (`lockAspect`, or Shift on a shape not held) scales them,
as on any element. So on a square or a circle the panel's lock always shows
it held, and is that choice instead: "Inside stays" or "Inside scales",
said in its icon, tooltip and the words beside it, and pressed to set or
clear `lockAspect`. Shift cannot let a square or a circle go, so on one it
turns that scaling over instead. A canvas saved with an oblong square or
circle reads and draws as it was: only choosing squares a box. A colour or a fade given to an outline
with no width gives it one (`withOutline`), from the panel and the Colour
panel alike. On another page shape a shape's words, outline, corners and
padding are sized with the page (`scaledBy`), as a text's type is; what its
kind draws is a share of its box.

### A stroke

A line and a path are one stroke along their curve, and say so by
extending `StrokedElement` (`model/elements/stroke.dart`): its colour or
fade, width, cap, what is drawn on each end (`LineEnd`), the ends' size and
the dash. The parts are held one by one, so a line or a path can still be
written `const` with them named; `stroke` gathers them as a `StrokeSpec`
and `withStroke` lays one down. Each element keeps its own defaults (a line
white, 4 wide, flat, with no ends; a path yellow, 3 wide, round, with an
arrow at its end), and saves its stroke under the same keys
(`StrokeSpec.toJson`, read back by `StrokeSpec.fromJson` with those
defaults; `test/canvas_stroke_saved_form_test.dart` holds both to the
saved form key by key). What reads a stroke (the Design table, the Colour
panel, the selection box, the press) asks a `StrokedElement`, never which
of the two it is.

One painter draws it, `paintStroke` (`render/paint_util_stroke.dart`): the
body with its cap, dash and fade, cut back under each end, and the ends at
their size in the body's own paint, so a faded stroke's ends are the colour
it has there. `drawnStroke` is the stroke as drawn: a closed path has no
ends, so its selection box makes no room for them. The size of every end
is in `EndShape`, which the drawing and the cut-back both read: an end's
`LineEnd.cover` is how far back its own ink reaches along the stroke's
middle (a hollow end's back edge, a solid end's a hair inside it), and
`StrokeSpec.cutBack` stops the stroke there, less what a round or square
cap reaches past the cut. `test/canvas_stroke_ends_test.dart` draws every
end at several widths, sizes and caps and holds the stroke to meeting it
with no gap and showing through no hollow one, and a path's ends to a
line's.

A stroke's fade is laid over the stroke as drawn, the curve's bounds grown
by half its width, so it runs across the thickness of a level or upright
stroke as well as along it.

How far each of its numbers can be set is said once, in `StrokeRange`: the
range its panel offers, what the Chain's Design table writes within, and
what a received stroke is read within. Its controls are built once too
(`ui/settings/stroke_controls.dart`), each by one function that a line's
and a path's panels use in the quick strip and in Look alike, writing
through `withStroke`; a stroke that draws no ends (`drawsEnds`, false on a
closed path) is offered only its cap. On another page shape its width and
dash are sized with the page (`scaledBy`); the ends follow the width.

### A line's and a path's curve

Where a stroke's curve is has one answer. `StrokedElement.curve` is the
line the stroke runs along in its box, before it is laid on the page: what
`paintStroke` strokes once `paintElement` has laid the canvas out.
`curvePoints` is that walked into points. `bowedBy` gives a line the bow a
pose keys.

Where `paintElement` lays any element out on a frame is an `ElementPlace`
(`model/canvas_element.dart`, made by `CanvasElement.placedBy` from a pose):
the pose's move, a squash along its travel, the element's own turn and slant
about its middle (`BoxFrame`), the pose's turn and size about its anchor,
and a moving loop's turn and size. The painter lays the canvas out by its
`applyTo`; `place` takes a point of the box to the page by the same steps
in the same order and `unplace` brings one back, so nothing can ask where a
part of the element is drawn and get anything but where the painter put it
(`test/canvas_stroke_on_page_test.dart` holds `applyTo` and `place` to each
other). `placeOnPage` (`render/motion_document.dart`) is an element as the
painter lays it out on a frame: the pose it is drawn in (keys, clips,
devices, loop and Design), the element with its Design's settings on it,
and the place that pose lays its box on the page (a page number mirrored
onto a left-hand page in the box it is drawn in), for the element or one of
its copies. `paintElement` lays its canvas out by it, so it is the one
statement of where an element is drawn; `drawnPoseAt` and `placeAt` are its
pose and its place. The stage asks at every pointer move and paint, so the
answer is kept for the element, the document, the frame and the copy (not
while slots play, nor for an element following a sound). `curvePlaced` is
a stroke's points laid on the page by a place, and `curveOnPage` by its
place at rest.

Something asked about from inside a pose (a Look at's or a Spring's target,
the camera a Look at faces, the path Follow path rides) is one round deeper
(`_asking`, one count for every such question, since one can ask another:
a Look at's target riding a path that looks back at it). Past a few rounds
the answer is cut short (a target's resting middle, a path's keys alone),
and an answer any part of which was cut short is kept, by `placeOnPage` and
by a device chain's poses (`_pulled`), only where it was asked from outside
any pose and handed back only there: asked from inside one, the same
question is cut a round sooner. An answer worked out whole is the same
however deep it is asked, and is kept wherever.

`strokeOnPage` (`render/scene_renderer_shapes.dart`) is a stroke as drawn on
a frame of a document: bowed and placed by its `placeOnPage`, with its curve
on the page; `curveOfElement` is that curve. What asks where a stroke is
asks it: the selection box (`visualBoundsOf`, its room for the stroke as
wide as the pose draws it), the press (`StageHitTest.contains`), text set on
a line, the Follow path device and words wrapped beside it. Its curve is
kept beside the answer `placeOnPage` keeps, while that hands back the same
one. A loop runs round `curvePoints` bowed by the painter's pose, inside the
frame the painter has already laid out.

`test/canvas_element_on_page_test.dart` holds every other kind to the same:
a filled shape, a picture and a text drawn part-way through each motion,
pressed on their ink and boxed round it, copies pressed each, and a drag at
a moved frame moving what is drawn as far as the pointer. The press
(`StageHitTest.contains`) takes the point back through the place
`placeOnPage` lays the element out by and asks the element as it rests:
inside the box it is drawn in, a shape inside its outline. An element
moved by nothing but its own keys (`movesAtAll`) is placed by its keys'
pose, which is what `placeOnPage` would find, with no whole pose worked out
at every move of the pointer (`StageHitTest.placed`). An element reused is
pressed copy by copy, each by its own place, never by a box round them all;
`StageHitTest.copyAt` is that press, and also says which copy a press picks.
A stroke, text on a line, a camera's frame, a team on a pitch and something
standing on a 3D stage (its quad through the stage's view) keep presses of
their own. A played canvas's click (`canvas_file_player.dart`) is the same
press, a camera there taken anywhere in what it frames.

An element's own parts are laid out in its box and drawn there before the
box is laid on the page, so a press on one (a counter's buttons and loose
words, a chart's key and placed labels, a table's cells and column rules,
a Code panel's tabs, dividers and playbar, a Run panel's button, a
speaker's and a video's controls, a sheet's playbar, an instrument's keys,
a metronome's buttons, a play, code or synth task's steps, a text's
pieces) takes the point into that box first: `StageHitTest.inBox` is the
point through the place `placed` lays the element out by, with that
layout, and the part's rectangle is laid out in `on.box` as the painter
lays it out. A drag on a part (a column rule, a label, a loose word, a
volume or a seek) measures its travel there too, so a rule on a turned
table goes as far along the table as the pointer goes, and under a size
the parts are not laid out in a sized box but sized with the drawing. The
marks over parts (a chart's label boxes, a table's rule grips: `partsPlace`
in the painter's inputs; a text's flow links) are laid on the page by the
same place, and a picked picture piece's box is its square laid on the page
by it (`_pieceBox`, by `ElementPlace.boxOnPage`), its own turn added. The
text editor, a table's cell editor and a counter's Set field are laid out
at the rectangle they edit in the box and laid over the page by the place
as one matrix (`ElementPlace.matrix`, made a matrix of the stage's points
by `_onStage`), so the field sits on the words or the cell as drawn,
turned, slanted, sized and moved with them (text on a line keeps its own
box, turned about its middle). A Code panel's open editor and a Run
panel's live preview are still laid upright where the panel's box is moved
and sized to (`StageHitTest.posed`). `test/canvas_parts_on_page_test.dart`
holds each part to it under each motion.

A lone element's selection box, or one picked copy's, is its own box laid on
the page by that place (`_placedBox`, by `ElementPlace.boxOnPage`): a box
and a turn and slant about its middle, which is what any place makes of a
rectangle, squashed or turned after a slant as well. So its handles, its
turn knob, the middle a press leaves to a move (`_insideCore`), a text's
flow grips and the press inside a shape's box that takes hold of it are on
the element as drawn, turned about any anchor, swung or spun by its loop;
the box's painter and the press on a handle both read `_selectionBounds` and
`_frameOfSelection`. A line's or a path's, text on a line's, a camera's and
a staged element's keep their own boxes.

Every other outline, box and edge the stage draws, snaps to or selects by
is the same box laid on the page by the same place: its four corners there
(`ElementPlace.corners`), or the upright box round them where an upright
one is needed (`ElementPlace.reach`), each copy of an element reused by its
own. `placesItsBox` (`render/scene_renderer_shapes.dart`) says which
elements are drawn so: not a line or a path, text on a line, something on
a 3D stage, a camera or a team on a pitch, which keep the answers they had.
`StageHitTest.outlines` is an element's outline as drawn, `reaches` and
`reach` the upright boxes round it, and `meets` whether it overlaps a box.
Each of several selected and every element with all bounds shown is
outlined by it (`outlinesOnPage`, `paintChosenBoxes`, `paintKeptBoxes`),
each copy is ringed turned as it is drawn (`paintCopies`), several selected
are boxed round their reaches (`_drawnReach`), a marquee takes what its
outline overlaps (`_selectWithin`), and a move snaps to the others'
reaches by the dragged elements' (`_otherBounds`, `_seenBounds`). Align and
spread line up the reaches too (`reachOnPage`, the same box for the
controller, `_drawnBox`), so what is drawn on the frame lines up, and
write through `_moved`: a pose where a drag would pose, else the rest. A
depth-blurred element's layer under the Camera's lens is bounded by its
reach grown by the blur (`_Lens.on`), so a turned one's ends are softened,
not cut off.

A move drag writes each element's value at the press plus the travel
(`CanvasController.moveOrigin`, then `movedTo`): its rest, its keys' move
where the drag poses it, or where it stands on a 3D stage. Never where it
is drawn, which holds whatever else moves it on the frame (a clip, a
device, a loop, a size about its anchor) and written back would add it
twice; so what is drawn follows the pointer exactly.

A resize, slant or turn of a lone element works from it as the painter laid
it out at the press (`_BoxStart.placed`, from `_lonePlaced`), on a frame
where more than its own turn and slant place it (its keys, a clip, a
device or its loop move, turn, size or squash it): the handle and the
pointer are taken back into its box through that place (`unplace`), its
resting box is changed there, and it is moved so what is held is drawn
where it was, since a place moves with its box. A resize
(`_resizeAsDrawn`) keeps the corner or side opposite where it is drawn and
draws the one pulled under the pointer; squashed, or stretched unevenly by
a loop, the box still grows along its own sides, so the side pulled moves
further on the page than the box grows. A slant (`_skewAsDrawn`) keeps the
side opposite and takes the side held along the one line a slant can: of
the element's two slants, the one that carries it further, so a side its
loop has spun upright leans along itself. A turn (`_turnAsDrawn`) sweeps
the element about its anchor as drawn, which stays there; under a squash
the angle is swept as it was before the squash. Each writes the resting
box, size, slant or turn, never a pose. An element as it rests, turned or
slanted or neither, is resized, slanted and turned by the arithmetic it
always was (`turnedTo` keeps its anchor where its turn and slant draw it).
One copy of several is sized and turned by its own values about its
anchor as that copy is drawn (`_beginCopyBox`).

The anchor's mark is drawn, and pressed, where the place draws the anchor
(`_anchorDrawn`), and a drag puts it under the pointer through the place
(`CanvasElement.anchorDrawnAt`). What is drawn on that frame does not
move: where a pose's or a loop's turn or size is about the anchor, the
resting box moves to make up for it, so on every other frame the element
rests, and is turned and sized by its keys from, somewhere else by as
much.

A lone line's or path's selection box is the box round its curve as drawn on
the frame, so the stage lays it out upright (`_boxIsDrawn`), not turned and
slanted a second time. A straight line's ends are at two of that box's
corners, and its corner handles move them (`_applyLineEnd`): the end goes
under the pointer and the other stays where it is drawn, the line's resting
ends laid so through the place it is drawn by (`LineElement.withEndsDrawnAt`).
A line's panel reads and sets it the same way, as it is drawn at rest:
`length` and `angle` are between where its ends are drawn (not its box's
`start` and `end`), and
`withLength`, `withAngle`, `level` and `plumb` keep where its start is drawn,
so Level makes a turned line level on the page.
A bowed line's or a path's corner handles resize its box. A handle drawn on
the box's edge is pressed before the inside of the box, whose press takes
hold of a stroke to move it. A path shows its points, not its box.

A path's point or handle on the page is `PathElement.gripOnPage`, and
`fractionAt` the way back from the page to the fraction of the box a point
keeps, both by the place the path is drawn by on the frame: the stage's
marks (`paintPathControls`, given `StageElementMarks.pathPlace`), the press
and the drag (`stage_path_points.dart`) use the two, so a path's points are
drawn, taken and moved where the curve is, turned, slanted or moved by its
motion. An end or a point dragged on a frame where the stroke moves is moved,
not posed: it lands under the pointer on that frame and the motion is left
as it is, while the whole stroke dragged is posed or moved as any element is
(`CanvasController.movedTo`). A follower's baked place (`positionAtFrame`)
is on the page, on the path as it rests. The press takes what is drawn on
the ends where it is drawn: `strokeEndMarks` (`render/paint_util_stroke.dart`)
is the outline of each end, which `paintStroke` draws by.

Words wrapped beside a line or a path go round its stroke as drawn on the
frame (`inkOfStroke`, `text_wrap.dart`): its curve with half its width either
side, and the marks on its ends, as runs of points with a reach that
`WrapShape.spanIn` measures each band of words against, as a square brush,
never less than the ink.

A path is made of `CubicSegment`s (`model/cubic_segment.dart`): a piece is
evaluated, split (`insertAfter`) and walked there, and distance along any
run of points is `PointsAlong`, which the path's follower and the Follow
path device share. Whether a handle is pulled out of its point is
`PathNode.hasIn` and `hasOut`. The vector drawing (`vector_editing.dart`,
`vector_cut.dart`) still does the same arithmetic in copies of its own;
`CubicSegment` is there for it to take up.

A path's follower is baked into its keys (`CanvasController.applyPathFollow`).
`followTrack` writes the follower's place on every frame of the run, and on
every frame it has a key of its own, and keeps what else it has keyed as it
plays: a key of its own keeps its turn, size, fade, channels and easing, and
a key added between takes them as its keys give them there. Unlinking
(`clearPathFollow`) is `ownTrack`: the fewest keys that play as all of them
do on every frame in everything but place, with no place. So a key of the
follower's own that lies on the way between two others but eases to the
next its own way stays, as the frames after it show; one the bake added
eases straight to a key a frame on and has no frames between. A key that
held nothing but a place goes, whoever keyed it, since a place keyed by hand
and a place baked over it are one value on one key.

The run is timed by the nodes' frames, from the first to the last. Round a
closed path it goes on over the closing piece, back to the first node, in as
many frames as the piece before it took (`closingFrames`; the run ends on
`endFrame`), so nothing more is saved for it; it is baked no further than
the scene's last frame. A node added half-way round the closing piece
(`insertAfter` on the last node) is timed half-way through it, and leaves
the run ending where it did, to a frame where that piece's frames are odd.
The run's Start and End fields and "Space the points evenly" share the run
out with the closing piece as one of its pieces (`spreadRun`).

### A layout's frame

Where a Layout's cells fall in its own box has one answer,
`layoutGeometry` (`model/layout_geometry.dart`): its cells, and the Panels
cuts or Grid lines the stage grabs, from one walk of the tree, kept for the
layout and the box (an `Expando`, so the painter, each docked element and
the stage ask it every frame for nothing). The pieces of it others need are
public there and asked, never copied: a cut's gutter (`cutGutter`), the
point it turns about (`cutPivot`), a Free cell's rectangle
(`freeCellRect`). A Free cell's triangle, diamond, hexagon and star are the
shape element's corners (`model/outline_points.dart`, which `shapePath`
draws by too), a cell keeping its own numbers where they differ: its
hexagon has a corner at each side, and its star is cut less deep.

Where that is on the page on a frame is a `LayoutFrame`: the geometry laid
out by the `ElementPlace` the painter draws the layout by there
(`layoutFrameAt`, `render/layout_painter.dart`), so a cell is wherever the
layout is drawn, turned, slanted, and moved, turned or sized by its keys,
clips and devices. `toPage` and `pathOnPage` take a point or an outline
there and `fromPage` brings a point back (`ElementPlace.placePath`, held to
`applyTo` by `test/canvas_stroke_on_page_test.dart`). A docked element is
clipped to its cell through it (`dockClip`, given the layout's place on the
frame it is drawn on); Panel mode's outlines are the cells on the frame the
page is read at, everything arrived (`settledFrameOf`); and the stage's
marks, presses and drags are on and taken back through the layout's frame
on the playhead (`stage_layouts.dart`), a picked Free cell's selection box
included (`LayoutFrame.freeCellBox`, by `ElementPlace.boxOnPage`: its box
at the size it is drawn, with the turn and slant it is drawn with). A
docked element itself is placed by its own box, not its layout's motion:
`layoutsSynced` moves it when the layout's resting box moves, so under a
keyed or clipped move the cell is drawn moved and the element stays.

How far a Layout's numbers go is said once, in `LayoutRange`
(`model/elements/layout_element.dart`): its gutters, margin and a cut's own
gutter, and where a cut crosses its box and how far it tilts; the panel and
the stage's drags offer that range, and what is read or kept is held to ten
times it, as a stroke's is. A cell is drawn with one border width all round
(the widest of its sides, where a saved one holds them apart), one radius,
its fill, picture and fade, cut to its outline; its panel offers no more
(`BoxParts.outline`). The edits that make a layout's cells afresh in
another mode or on other tracks are the model's (`layoutInMode`,
`LayoutElement.withTracks`), so the panel writes them as any panel writes.

A dock is a `LayoutDock` (layout id, cell id), saved as it always was, one
string `"layout:cell"` in `ElementBase.dock`, read on demand by
`ElementBase.docked` so a base stays `const`. The edits that change which
cells there are live on `LayoutElement` (`split`, `removeCell`,
`addCell`), each keeping every other cell with its id; removing a Panels
cell puts its neighbour's subtree in its parent's place and docks what was
in it in the cell that met it. Whatever makes a layout's cells afresh (a
preset, a cell removed) lets go of what was docked in a cell that is gone,
where it is: `layoutsSynced` does it on every change, and moves only what
is docked in a cell the layout has.

### A counter's mode

A counter is one of five things, `CounterMode`
(`model/elements/counter_element.dart`): a count set by keyframes, a run
(counting once started), the time of day, one of a game's counts, or the
number of its page. It is not saved: `CounterElement.mode` answers it from
the fields that are (`keyed`, saved as `"live"` the other way round, and
`source`; a page number and a game's count are so whatever `keyed` says),
so a file reads and writes as it always has. The table over `CounterMode`
says which field means anything in which mode, and the mode answers the
small questions: `buttonsAct` (only a run's Start, Reset and Set do
anything, so only a run's are offered, drawn and pressed; a counter saved
with buttons in another mode keeps them), `countsEnds` (From and To are a
keyed count's or a run's ends). The number shown is `shownValue`, which
the renderer, the stage and the panel ask. The painter, the clock
(`CounterClock`), the controller's `counterValue`, the stage and the panel
switch over the mode with no default, so a sixth mode is a case there and
the compiler names every reader.

From and To are set through `withEnds`: a keyed count's first and last
count keys move with them while they still hold the old ends (a new
counter's count is laid out from From to To by `withCountLaidOut`), and a
key changed by hand to another number stays. A clock is kept going while
its canvas is shown (`CounterClock.keepClocks`), whatever `running` says.
A run set to start running starts as the canvas opens, for the scene
shown, and for any other scene once it is turned to (`CounterClock.turned`,
from the controller's one way of turning the scene); one started, stopped
or set before is left as it was.

Where a counter's pieces are is worked out once, by `counterLaidOut`
(`render/counter_painter.dart`): the room its number has, the fit, its
buttons, and where the letters of its loose words are. The painter draws
from it and the stage presses by it, so the two cannot differ; a piece is a
`CounterPiece` (`CounterWords`, `CounterButtonPiece`), placed by
`withPieceAt`. Its number and words are one line of runs, measured for the
fit by the same call that draws them (`layOutRuns`, beside
`paintRunsInBox`), so a case or a gap cannot be measured one way and drawn
another. A mirrored page number on a left-hand page is drawn across the
page (`CounterElement.drawnBox`); the renderer (`placeOnPage`, the box it
lays the element out in), the selection box and the press all ask it, and a
move drag takes it the way the pointer goes.

### A camera, a metronome and a button

A scene is framed by one of two things. A Camera element shown on it
(`cameraOf`, or `cameraAmong` for a scene's elements: the first shown in the
scene's order; a second is drawn on the canvas but frames nothing) takes
over. The stage draws the one that frames as a viewfinder with its name on
a filled tab, and any other shown thin, without its corners, its tab dark
and saying it is not in use (`paintCameras`; `cameraTab` makes room for the
words, and the press uses the same tab). The panel of one not in use names
the one that is, with a button that moves it just ahead of that one in the
order: a Camera is never drawn in the picture, so nothing on the page
changes but which frames; else the scene's own slow move
(`SceneCamera`, named by `CameraMove`, both in `model/scene_camera.dart`),
set on the scene's Camera card. `sceneFraming` (`render/motion_document.dart`)
is that rule, and the scene's chain asks the same question: while a Camera
frames the scene its card says so in place of the slow move's controls,
which come back, as they were set, when the Camera is hidden or taken away.
On a 3D stage the Camera is the stage's camera instead: `isStageScene` says
whether a scene is one, and `sceneStageOf`, `stageCameraOf` beside it are
the stage and where its camera stands, which a new Camera starts from. What
a Camera keys of its lens (focus, blur, vignette and how far it turns to its
aim) are `KeyframeChannel`s, keyed through `ElementTrack.withValueKey`, the
one way every panel's ◆ keys a value: a new key there pins nothing else.
How soft a Camera's blur goes is `CameraElement.maxBlur`, which its panel
offers; `readBlur`, a little over three times it, is the most one is kept,
keyed or drawn with, since a blur costs more the wider it is.

Whether a metronome is going is the editor's, not the document's
(`controller/metronomes.dart`). How it swings is handed to the renderer as
a live counter's value is (`paintCanvasDocument`'s `metronomeShow`, from the
stage's `StageLive`), so an export, and anything drawn without the editor,
draws it at rest. The swing is taken from where its click has been heard to
(`AudioRuntime.metronomeHeard`), held on its first beat while the sound gets
ready, and timed by the clock alone where there is no sound. A change of its
tempo or of its beats in a bar goes on from the beat it is on
(`setMetronome`); its colours are written as any element's are and leave it
going as it was. Its beats in a bar are one list, `metronomeBeats`, which
the panel offers and its beats button steps through.

A button's painter is `render/scene_renderer_button.dart`. What it does is
`controller/button_actions.dart`, whose head is the table of each action in
the editor and in a book, and where the two differ; its controls
(`ui/settings/button_action_controls.dart`) are shared with a game
element's press.

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

A part holds one subject, and is named for it: `playback.dart` is the
player and nothing else; the zoom is with the rest of the view
(`view_settings.dart`), the mixer's layout has a part of its own
(`mixer_layout.dart`), the timeline's row folds and following the playhead
are with its lanes (`lanes.dart`), and what a button element does is
`button_actions.dart`, whose head is the one table of what each action does
in the editor and in a published book, and where the two differ. What needs
nothing of the controller is a library beside the parts rather than a part,
handed what it reads and what to tell: `view_types.dart`;
`counter_clock.dart`, the counters' clock (a run's count, and a clock
kept going while shown), which the controller holds one of (`counters.dart`
is the controller's side of it: a game's counts);
and `playhead_on.dart`, what the playhead is on (below).
`test/canvas_layers_test.dart` holds those three to not importing the
controller.

**Playing.** Whether anything plays is the timer's (`playing`: `_playback`
is running). What plays is one value, `_playheadOn`, a sealed `PlayheadOn`
(`controller/playhead_on.dart`) whose cases each hold what that activity
needs: `OnTimeline`, the scene's own timeline, playing or stopped (a canvas
opens on one); `OnRun`, a frame of the run of every scene, which plays to
the run's end as the document has it then; `OnJoin`, a frame of a join's
transition watched, to its end, with the scene to go back to (a playhead
put by hand off the transition ends the watching where it was put);
`OnElement`, one element's animation previewed; and `OnSlots`, the clip
slots alone on their own clock. The first three are `Showing`, what the
canvas shows; the last two play only while the timer runs, always over the
scene, as each starts by ending a join watched or a frame of the run held,
and the scene shows on `pause`. A range a play stops at (a button's Play to
frame, a lesson, a sheet's bars) is the timer's, beside it in
`_PlaybackState.rangeEnd`, and `pause` lets go of it. A change, an undo or
a redo that shortens the run lets go of a frame of the run held past its
end. The questions asked of it are named once, on the value (`isPreview`:
an element or a join, when the metronome is quiet) or in `playback.dart`:
`timelinePlaying` (the timer runs for anything but the slots alone: Play
shows as pressed), `canvasLive` (playing, or a game on its own timer: what
a slot's launch asks), `showingScene` (no frame of the run, no element
previewed) and `_runHeld` (a frame of the run that stopping, or moving the
playhead by hand, lets go of). The scene is turned in one place,
`_turnScene` (`scenes.dart`), for a turn by hand, by every scene playing
and by a join going back; the sounds on the page follow it there, and each
caller holds the frame to the scene before it tells the timeline's media
and the mix where the playhead is. A new kind of playing is a new case: the
compiler then lists every `switch` over the value that has to say what it
does.

Two rules for whatever is added to it:

- **State about the open canvas is forgotten in `_forgetDocument`**
  (`controller/saving.dart`). The session outlives the canvas, so a field
  that names one of its elements, scenes, sheets or devices is met by the
  next canvas unless it is cleared there. `test/canvas_forget_document_test.dart`
  holds this: it reads the controller and its parts, collects every field
  that can change (each one not final, and each final collection,
  `ValueNotifier` or holder class, with the fields of each holder), and
  fails for any that `load`, `_forgetDocument`, a holder's own
  `forgetDocument` or one of the methods it names in `_lettingGo` does not
  assign, clear or make anew. A new field is therefore one of two things:
  the canvas's, and let go of there (a holder that is wholly the canvas's,
  such as `_InstrumentState`, is made anew, which covers any field added to
  it later); or the person's or the run's, a view setting, a tool, an
  engine or a cache keyed by what it holds, and named in the test's
  `_outlivesACanvas` with why. What is held live (keys, metronomes, a voice
  heard alone) is let go of in `_letGoOfLive`, which leaving the page calls
  too.
- **A job that waits writes only to the canvas it began on.** One that
  awaits something slow (a voice, a file, a render, a disk write) and then
  changes the document or the controller takes `_loads` as it starts and
  asks `_stillOn` before it writes; if another canvas has opened, it drops
  what it brought and leaves any busy mark alone (`_forgetDocument` has
  already cleared it). `runCode` (`controller/code_runs.dart`) is the
  pattern. A render written only onto something that still sounds the same
  (`renderParts`, a clip's warp) is keyed by what it holds and needs no
  guard.
- **Working out a new document is the model's job.** A function of the
  document (`castAdded`, `layoutsSynced`) lives in `model/`, where the quick
  model tests reach it, and the controller's part calls it and `apply`.
  `controller/cast.dart` is the pattern.

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

**Listening.** Most widgets listen to the controller. Some things notify it
many times a second: the steps of a gesture (a drag, typing on the canvas:
`apply(transient: true)` between `beginInteraction` and `endInteraction`),
frames of play, and what moves by itself (a game's steps, a video's frames,
a live counter's ticks: `_notifyStep`). A widget that shows none of them
listens to `controller.chrome` instead, which passes over them all and hears
the notification at the gesture's end or when play stops: the settings band,
the page, the dock, the play bar. A widget that
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

### Keys

Every key the Canvas page answers is a line of `canvasShortcuts` in
`ui/stage/stage_keys.dart`: its keys and modifiers, when it applies, what it
does in words, and the doing of it. Three handlers hand their keys to
`canvasKey`, each saying where the keyboard is: the canvas
(`canvas_stage.dart`), the play bar and timeline (`transportKey`,
`screen/play_bar.dart`), and a scope round the whole page
(`CanvasPageKeys`, `screen/page_keys.dart`), which hears what the others
leave and brings the keyboard back to the page when it is pressed.

- **`reach`** is how far out a line is heard: `canvas` only while the canvas
  has the keyboard, `transport` only while the play bar or timeline has it,
  `page` anywhere on the page. The canvas's and transport's lines come
  before the page's, so they have the first say. A key that does the same
  wherever the keyboard is (copy, cut, paste, undo, redo) is one `page`
  line, not one per handler, so that it is held and modified the same
  everywhere. Space, which plays or pauses, is two lines: a `transport`
  line that takes it with any modifier, as the play bar and timeline take
  the arrows (so Flutter does not spend them moving the focus between the
  bar's buttons), and a `page` line without Command for everywhere else.
- **`when`** is whether the line applies now, read from the controller. The
  first line that fits the key, the modifiers held, the reach and `when` is
  the one done; the rest are not tried. A key with several meanings
  (Escape, Delete, the arrows) is several lines, the most particular first,
  and a line whose `when` is `always` ends its key's run.
- **`held`** is what holding the key down does: `again` on each repeat (the
  arrows), `taken` once with the repeats swallowed (Space, so no focused
  button gets them), or `once` with the repeats left to whatever is further
  out.

To add a key, add a line where it belongs in that order;
`test/canvas_stage_keys_test.dart` fails if it can never be reached behind
an earlier line, or if a tool's letter is missing. A tool's letter is not
written in the table: it is the tool's own `key` (`ImageTool`, `StageTool`,
`VectorTool`), and the table makes a line for each.

Two things take the keyboard for themselves before the table: a field being
typed in, the text editor on the canvas among them
(`ui/stage/canvas_text_editor.dart`; see `isTypingInAField` in
`ui/controls.dart`), and a running game, which has every key
(`CanvasController.gameKey` in `ui/controller/game.dart`). Panels with
focus of their own (the piano roll, the curves, the Data Studio, the keys
strip and others) answer their own keys before the page's.

### Gestures on the stage

What the pointer is doing on the stage, from the press that begins it to
its release or cancel, is a `StageGesture` (`ui/stage/stage_gesture.dart`):
a sealed type, one case per kind of gesture, each holding what it needs
while it runs. The State holds one, `_gesture`; `_onPointerMove` hands each
move to it and `_onPointerUp` hands it the release or the cancel. Ending it
clears it and, when its `opensUndoStep` says it began an undo step, closes
that step after the gesture has done what it does on finishing, so nothing
is left set and no undo step is left open.

To add one, write a case in `stage_gesture.dart` holding the gesture's
state, and set `_gesture` to it in the press step that begins it (in
`stage_press.dart` or a tool's part), calling `beginInteraction` there if
it is a change. The compiler then asks for the rest: `opensUndoStep`,
`waitsToTravel` (whether it waits for the press to go the drag threshold,
so a click does not move what it lands on), `move`, `release` (told
whether the press travelled, and whether it ended as a click: it never
travelled and was let go within the click slop of where it began, so a
press that travels and comes back is not a click) and `cancel` (the
system took the pointer: nothing it does on finishing is done). A
case's methods are short: they call the State's methods that do the work,
with what the gesture holds. What only a gesture shows (the box's snap
mark, a retouching stroke) is held on the case and read from `_gesture` by
`_stagePainter`, so nothing is left to tidy away. Ending a gesture rebuilds
the stage, so its cursor and those marks go with it. `endsRelease`, false unless a case says
otherwise, skips the rest of `_onPointerUp`, which is all for the kinds
still on `_DragMode`. `cursor`, null
unless a case says otherwise, is the pointer's look while it runs, shown
over the tools' own. `takesAll`, false unless a
case says otherwise, hands it every move and the release at the very top
of the two handlers, before anything of the stage's own (the hover, the
brush ring, the resets): for a press that is not on the page as it is
drawn, the held marker's note over it or a live preview. A press that
turns out partway to be something else hands its gesture over with
`_handOver`, which keeps the undo step open for the one that takes over: a
chart key's entry held long enough becomes a drag of the key.

The selection's box moved, resized, slanted or turned is four cases of one
sealed `_BoxDrag`, sharing where the selection was when it was pressed
(`_BoxStart`, from `_beginTransform`). A press on a selected element's
controls (a button, a video's or speaker's controls, a sheet, a counter's
button, a chart's key, an instrument's key, a Code panel's code, a copy)
begins a move that carries a `PendingClick` (`stage_pending_click.dart`),
made on release if the press ends as a click and dropped otherwise; a case
says what makes it, what it does, and what it lets go of when the press
travels or ends without it. To add a control that clicks on release and
moves on a drag, write a case there and hand it to the `_BoxMove` its press
step begins. A gesture that carries clicks (the box moved, a chart's placed
label, a counter's loose piece) takes `_CarriesClicks`, which settles them
in turn as it ends. Within one press, a click armed by an earlier step for
the move a later one begins rides on the press's own value (`_Press.click`),
as a Code panel's code does on its copies dragged (`_CopiesDrag`).

An element's own controls are cases beside their subject: a synth module's
key held, knob turned, screen dragged and cable carried in
`stage_synth_controls.dart`; a Code panel's playbar scrubbed, divider
dragged and tab carried, and a press left to a live preview, in
`stage_code_controls.dart`; a counter's loose piece in
`stage_element_controls.dart`; a text's picture piece moved, sized or
turned by its own box in `stage_text_pieces.dart` (three cases of one sealed
`_PieceDrag`, sharing the piece and its middle as the press found them); a
Layout's cut moved, tilted or widened, a Grid line moved, and a picked Free
cell moved, sized or turned in `stage_layouts.dart` (seven cases of one
sealed `_LayoutDrag`, sharing the layout and the press as it found them,
each step changing the layout as the document has it then, so a cell taken
out with Delete partway stays out); a
team's player in `stage_team_players.dart`; the retouching stroke in
`stage_retouch.dart`; a 3D stage's camera orbited
or panned, parallax scenery panned and the gizmo dragged in
`stage_3d_view.dart`. A chart's label, a table's column rule, the held
marker's note, a reused element's copies moved, sized or turned, and a
sprite or tile map painted are in `stage_gesture.dart`.

Not every kind is a case yet. The rest still run through the State's
`_DragMode _mode` and the fields read under it: begun in their press steps,
stepped in the `switch` in `stage_drag.dart`, and ended by the branches
and the hand-kept lists of modes in `stage_release.dart`, which close
their undo steps. These are the vector tools, and the picture tools and
warp, in their own parts. So both
exist for now: a press sets one or the other, never both. A press that
opens a Run panel's preview live is neither: `_liveTapPending` replays its
tap into the app on release.

### Snapping

One `Snapper` (`model/canvas_snap.dart`) is what a drag lands on: the
page's edges and middle, the grid while it is shown (its lines from
`gridLines`, which the painter draws, so a grid too fine to draw is not
snapped to), the shown guides, and, with Other elements on, the sides and
middles of what is not dragged. Which parts of the dragged thing may land
are `SnapTo`'s switches in `CanvasGuides` (`model/canvas_guides.dart`):
edges (and so corners), centres, and whether other elements count. A
gesture that snaps makes its `Snapper` once, at the press: the box drags
hold it on `_BoxStart` (`_beginTransform`, with the other elements' boxes
from `_otherBounds`), and `_GuideDrag` holds one that leaves the dragged
guide out. Each step asks it with the reach from `_snapReach`
(`stage_drag.dart`), the one place the screen-pixel `snapWithin` is turned
into document units and Alt is read: null while Alt is held, which frees
the drag. It answers with the nudge to add and the lines caught
(`SnapLines`), which `_BoxDrag` holds as the mark `_stagePainter` draws.

What snaps: a move of the selection's box, by the box it is seen in
(each element by the upright box round it as drawn on the frame, and the
others' the same: see `StageHitTest.reaches`); a
resize, by the dragged edge alone, upright boxes only; a guide dragged; a
single line's end, to level, upright and diagonal (`snapLineAngle`); and on
a 3D stage, with Snap on a 3D stage, an element moved across the floor
(`movedTo`, told `free` while Alt is held) and the gizmo's moves and
turns. Alt frees every one of them. Nothing else snaps: slanting, turning
(Shift steps it, see `steppedTurn`), copies, path points, chart labels,
table columns, anchors, Layout cells and cuts, picture layers, text
pieces, the marker's note and keyboard nudges land where they are put. A
drawing's handles turn in steps under a switch of their own
(`vectorHandleSnap`), apart from all this.

To add something to snap to: its lines go in `Snapper._allLines` (or
`_addTheirs`, for something read from the other elements' boxes), from
what the constructor is given; anything the stage must hand it is a new
argument to `Snapper(...)` at its two calls, `_beginTransform` and
`_guideSnapper`. A switch for it is a field on `SnapTo` with its
`copyWith`, `toJson` (written only when it differs from the default) and
`fromJson`, and a value in `SnapTarget`, which the guides panel and the
settings bar's snap menu both list, so neither needs touching.
`test/canvas_snapping_test.dart` drags on a real stage; the arithmetic is
tested in `test/canvas_guides_test.dart` and `test/canvas_align_test.dart`.

### Adding a mark to the stage

`StagePainter` (`ui/stage/stage_painter.dart`) draws from one record,
`StageInputs`, of nine values, each a record of its own in
`stage_painter_inputs.dart`: the transform (`StageTransform`), the page
shown and how it plays (`StageShown`), what is live (`StageLive`), the
selection's marks, the marks on elements, the tool's marks, the retouching
brush, the guides with the snap lines and rulers, and the text being typed
into. `_stagePainter` in `canvas_stage.dart` makes it from one short
builder per value, written after it (`_shownOnStage`, `_liveOnStage`,
`_selectionMarks`, `_elementMarks`, `_toolMarks`, `_retouchMarks`,
`_guideMarks`). `shouldRepaint` compares the whole record, so nothing in it
can be left out of the comparison.

To add a mark:

1. Give it a field, with its doc comment, in the value whose subject it is:
   set by the same part of the stage and read by the same part of the
   paint. A record compares field by field, so it is compared with nothing
   more written. A list or set goes in as an `EqualList` or `EqualSet`,
   compared by what it holds. What cannot be compared (a closure, a list
   grown in place) goes in as a `NotCompared`, beside a tick, revision or
   length that changes whenever its answers do, said in the doc. A class
   without equality of its own is compared by identity, which repaints at
   every build that makes it afresh: say so in its doc, as
   `StageToolMarks.layers` does, or make it a record.
2. Set it in that value's builder. The compiler asks for it there and in
   `make` in `test/canvas_stage_painter_inputs_test.dart`, which gives every
   field through `pick`: give the new one through `pick` too, so the test
   changes it alone and expects the stage to repaint.
3. Draw it in a function of its subject's library, given the canvas and
   the values it reads, as the functions there are (`paintGuideMarks(canvas,
   guides, docSize, scale, origin)`): `stage_paint_page.dart` for the page
   and what is drawn with it, `stage_paint_selection.dart` for the
   selection, `stage_paint_elements.dart` for a mark on elements,
   `stage_paint_tools.dart` for a tool's marks, `stage_paint_retouch.dart`
   for the retouching brush, `stage_paint_guides.dart` for the grid, guides
   and snap lines. Draw its handles, knobs, dashes and outlines with the
   pieces in `stage_paint_kit.dart`. Call it from the painter
   (`stage_painter.dart`) where it should stack: `_paint` for the page,
   `_paintMarks` for what goes over it, `_paintHelpers` for what shows only
   with helpers on. `test/canvas_stage_pictures_test.dart` keeps a picture
   of the stage in each state that reaches the paint; give it a state for
   the new mark, and run it before and after moving any painting code.
4. If it can be pressed, its hit test uses the geometry it is drawn with:
   the sizes and places go in `stage_geometry.dart`, called by both the
   painter and the press, as `stageHandleAt` is for the selection's
   handles, `tableColumnGrips` for a table's column rules and
   `shapeTurnKnob` for a shape's turn knob.

## Preferences

`CanvasPreferences` (`canvas_preferences.dart`) is what is remembered about
the app on this machine, as against what is saved in a canvas: whether the
feature is on, the canvas last open, how the panels were left, and the
rulers along the stage (`CanvasRulers`, in `model/canvas_rulers.dart`: which
edges, and whether they show), and how the mixer and the Slots panel are laid
out (`MixerLayout`, in `model/mixer_layout.dart`: the bands, the returns, the
cue columns, the slots' size, the rail, each limit on them held by the value
itself). The rulers and the mixer's layout are the person's, so a canvas sent
to somebody does not change them for them, while which mixer strips are
narrow is the canvas's own view; the grid, the guides and the
snap switches are the canvas's, saved in its `CanvasGuides`. What the
controller holds of these (the frame, the rulers, the cues, the mixer, the
play bar's snapping, scrubbing and place, the panels) is handed to it as
the page opens and written back as it changes, in one list in
`ui/screen/kept_view.dart`. To add one,
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

**The Writing library is not the Canvas's.** A text or a Speech device reads
its words from a Writing document, and a canvas can be published into the
library as a picture to embed; both go through `WritingLibrary`
(`storage/writing_library.dart`): list the documents, read one, publish a
picture, remove one. The app hands the Canvas one at start
(`WritingLibrary.use` in `main.dart`, with `PostStorageLibrary` in
`lib/models/canvas_writing_library.dart`, which knows the library's storage);
with none handed, as in a test that hands none, nothing is read and the
picker says there is no library. `test/plugin_system_layering_test.dart`
fails on a Canvas file that reaches into the library's storage itself.

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
