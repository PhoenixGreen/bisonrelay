# How an element's settings panel is built

Every element's settings are one panel in the same frame, built from the
same controls, so that they read as one hand's work. This says what the
frame is, how an element puts its settings into it, and what it gets
without asking. `ARCHITECTURE.md` (two folders up) says where a new kind's
panel is wired in.

## The frame

`elementPanel` (`element_panel.dart`) is the frame. Top to bottom:

| Part | What is in it | Who puts it there |
|---|---|---|
| Quick strip | the two or three things changed most (a shape's kind and colour) | the element, as `quick:` |
| **Content** | what the element is: its words, its data, its points | the element |
| **Look** | how it is drawn; then its looks (outline, shadow, glow) | the element; the frame adds the looks |
| **Layout** | where it is and how big | the frame (`positionGroup`); the element may add |
| On a stage | where it stands, when the scene has a 3D stage | the frame |
| **Motion** | how it arrives, loops and leaves; its cue | the frame; the element may add |
| **More** | presets, and what is set once | the frame; the element may add |

A section with nothing in it is left out. Each section's heading carries a
one-line summary of how it is set, so the panel can be read shut.

## Writing a panel

An element says what goes in which section with a list of `PanelBit`s, and
hands them to `elementPanel`:

```dart
Widget shapePanel(BuildContext context, CanvasController controller,
        ShapeElement e, SettingsWrite write, VoidCallback begin,
        VoidCallback commit) =>
    elementPanel(context, controller, e, write, begin, commit,
        quick: CanvasQuickStrip(children: [/* a panelRow */]),
        bits: [
          PanelBit(PanelSection.content,
              summary: e.shape.label,
              children: [
                CanvasControlGroup(
                    label: "Corners",
                    help: "How round the corners are.",
                    children: [
                      panelRow([
                        cell(CanvasNumberField(/* ... */)),
                        cell(CanvasToggle(/* ... */), flex: 2),
                      ]),
                    ]),
              ]),
          PanelBit(PanelSection.look, summary: "Blue", children: [/* ... */]),
        ]);
```

- A **`PanelBit`** names its section, gives a few words for that section's
  heading, and holds groups.
- A **`CanvasControlGroup`** is one subject. Inside a section it is drawn as
  a card: its name, a "?" holding its `help`, and its controls. Give every
  group a `help`.
- A **`panelRow`** lays controls across a line; each `cell` takes a share
  (`flex`) or a fixed `width`, and says the least it can be drawn at
  (`min`). Too narrow for all of them, the row stacks.

`shape_settings.dart` is a complete panel of ordinary size to copy from:
its sections' bits are named pieces (`_kindBit`, `_lookBit`, `_wordsBit`,
`_bubbleBit`), each handed the element and how to write it.

A control in the quick strip is the twin of one in a section. Build the two
with one function that is told which it is (`quick:`), so their range, what
they offer and what they write cannot part: the shape's `_outlineWidth`,
a counter's From, To and Written (`_end`, `_written`), and a stroke's
controls in `stroke_controls.dart`. Take every range from
the model (`StrokeRange`, `SpeechBubbleSpec.maxTailLength`), never a number
written in the panel.

Seven kinds still hand the frame whole sections of their own (a team, a 3D
character, a sprite, a tile map, a camera, a 3D object, a background). Those
are placed by name through `_placed` in `ui/element_settings.dart`. New
panels use `PanelBit`s. Pictures go through `elementPanel`
(`image_sections.dart`), and so does text (`text_settings.dart`), which
uses the two things below that only it needs so far.

- **Looks on layers.** A text's looks are on its layers: all of it, and its
  own words. `looks: PanelLooks(groups:, said:)` puts its own groups of
  looks at the end of Look in place of the frame's one, and names those
  switched on in the heading.
- **After the frame's own.** A `PanelBit` with `last: true` goes after what
  the frame puts in its section, and its word after the frame's in the
  heading: a text's named style comes after the presets in More.

A piece picked in a text's Layers is not the element, so it has no place,
docking, stage, cue or presets: its few sections are drawn in the frame's
shell, `panelFrame`, with the text's Layers over them, rather than by
`elementPanel`.

## Changing the element

Every panel is handed three things:

- **`write(next)`** replaces the element with `next`, live, as a drag or a
  typed number goes. It opens the undo step itself.
- **`commit()`** closes the step. Every control with an `onChanged` that
  calls `write` has an `onCommit` that calls `commit`.
- **`begin()`** opens a step without changing anything. It is needed only
  before a call on the controller that is not `write`. Called before
  `write` it does nothing, and much of the code does call it there.

A choice made in one press (a dropdown, a tile, a switch) is all three at
once: `begin(); write(next); commit();`. Panels name that `now`.

## The controls

All from `ui/controls.dart`, which says what each is for.

- **A number**: `CanvasNumberField`. In a card it is drawn as a stepper, an
  arrow either side of a number that is dragged sideways or double-clicked
  to type. `CanvasStepper` directly, where the number needs a step of its
  own and a value to go back to.
- **One of several**: `CanvasDropdown` for a list; `CanvasSegmented` for two
  to four short choices side by side; `CanvasTiles` where the choice can be
  shown (a shape, a filter, a blend), each tile a small drawing of itself.
- **On or off**: `CanvasToggle`, a line with a switch at its end.
- **A colour**: `CanvasColorButton`.
- **Four numbers that are usually one** (a border's sides, a box's corners):
  `CanvasSidesField`, through `roomFields` and `cornerFields`
  (`box_group.dart`): one stepper and a link that splits it. Give each set
  a `prefix` of its own: it names the keys and what is remembered split.
- **A section's tools**: `CanvasToolTiles`, with the settings of the one in
  hand under them.
- **Something to do**: `CanvasTextButton` for an action said in words;
  `CanvasAddChip` for adding one of several things.
- **A word of explanation**: a group's `help`. A loose `CanvasHint` among a
  group's children joins it under the "?".

## What comes without asking

Do not build any of this again for an element:

- **Place and size**: `positionGroup` (`position_group.dart`), in Layout.
  An element whose place is set by something else hands the frame its own
  group as `position:`: words riding a line show only their opacity
  (`opacityField`), and a picture's tools put theirs there.
- **Looks**: `LooksGroup` (`panel_parts.dart`), in Look, from the model's
  own list of each look's settings.
- **On a stage**: `stageSpotSettings`.
- **Motion**: `MotionSummary`, the Arrival and Leaving pickers, and the cue
  card. How a clip moves is set in the Chain, not here.
- **Presets**: `presetsSection`, in More.
- **Type**: `type_parts.dart` (`TypeEdit`, `typeFont`, `typeSize`,
  `labelType`...), wherever words are drawn. `typeGroups` there is a
  second, whole set, used by a team and a counter's buttons; new panels
  build from the pieces.
- **A box** (fill, border, corners, padding): `boxGroup`
  (`box_group.dart`); **a fill** of a picture or a pattern: `fillBits`
  (`fill_controls.dart`).

## Where the shared pieces are

| File | What it holds | Who uses it |
|---|---|---|
| `element_panel.dart` | the frame, `elementPanel`, its shell `panelFrame`, and `PanelBit` | every panel |
| `panel_kit.dart` | the folding sections, the tiles and tool tiles, and the hold | every panel |
| `panel_parts.dart` | the kit: the quick strip, `panelRow` and `cell`, looks and motion lines, and the small things every panel shares (`SettingsWrite`, `freshOf` for after an await, `valueDot`, `boxed`, `shortNumber`) | every panel |
| `position_group.dart` | `positionGroup`: place, size, turn, slant, anchor, depth, and what the element does on each page shape | the frame; a picture's tools; words on a line (`opacityField`) |
| `box_group.dart` | `boxGroup`, and the side and corner fields it is made of | a text's box, a counter's two, a button, a chart's card, audio, video, a picture's frame, sheet music, a Layout's cells |
| `fill_controls.dart` | `fillBits`: a picture or a pattern as a fill | a text's letters, a box, a shape |
| `type_parts.dart` | how words are set, a control at a time, and `typeGroups` | wherever words are drawn |
| `stroke_controls.dart` | a stroke's colour, width, cap, ends and dash, each built once, writing through `withStroke`; `fadedColour` and `widthField` | a line, a path, a shape's outline |

A control only one panel uses lives with that panel: a text's cutting
pieces and the easing dropdown are in `text_settings_parts.dart`.

## What a panel remembers

Which sections are open is remembered per kind of element, on disk:
`section(e, "look", ...)` is kept as `shape.look`, so a shape's Look and a
chart's Look do not share an answer. A section of your own gets a name of
its own in the same way (`image.picture.mask`, not `mask`). The same goes
for the smaller memories: a box's `remember` name keys its "more" group and
its split sides (`counterButtonBoxBorder`, not `boxBorder`), so two boxes
in one panel open and split apart.

## Standing still during a drag

While something is dragged, the panel does not rebuild every section at
every step: a section keeps what it last built unless the pointer went down
in it (`PanelHold`, `panel_kit_hold.dart`). For a drag on the canvas, the
sections that show where the element is stay live: Layout, On a stage, and
any section inside them. When the pointer lifts, the whole panel is built
from the element as it now is. A section of your own that shows the
element's place needs `followsStage`.

## Spacing

Do not write a pixel gap into a panel. The gaps are named in
`ui/controls.dart`:

| | | |
|---|---|---|
| `canvasControlGap` | 5 | between two controls on a line |
| `canvasCaptionedGap` | 8 | after a control with a caption over it |
| `canvasRowGap` | 8 | between one line of a group and the next |
| `canvasCaptionGap` | 7 | under a group's name |
| `canvasGroupGap` | 24 | under every group |

In a card the controls are a size up (`cardControlHeight`) and further apart
(`cardGap`). Older panels still carry literal gaps; new code does not add
to them.

## Outside a section

A group that is not in a section (several elements picked at once, the
settings band over the canvas, a dialog) is drawn flat: a caption over a
line of controls.

- `CanvasMoreGroup(row:, more:)` is a line with a button on the end of it:
  the row holds what anybody changes, the button what is set once. In a
  card it shows both, since the section is the fold.
- `rule: false` joins a group to the one under it as one subject. It does
  nothing in a card.
- Controls say the width they will not go below, and grow into what room
  the line has; `grow: false` opts out. The extra is shared so that a line
  of four and a line of two under it come out in the same columns.
- `CanvasLineBreak` ends a line on purpose.

## Testing a panel

- `test/canvas_panel_sweep_test.dart` lays out every kind's panel, from the
  samples in `test/support/element_samples.dart`, at several widths and text
  sizes. A new kind is covered without being told.
- `test/support/canvas_panel_helpers.dart` has `openSection`, `typeNumber`
  and `typeInto` for tests of a panel's own.
- `test/canvas_shape_line_path_panels_test.dart` presses or sets every
  control of a shape's, a line's and a path's panels in the real sidebar,
  one row of a table each, and holds each to changing what it says in one
  undo step: the pattern for a panel's every control.
- `test/canvas_panel_keys_test.dart` keeps every key and word each panel
  shows, so a change to how a panel is built can be shown to change nothing
  else.
- A model test does not see a dead control or a row that wraps. Pump the
  real panel at a known width and measure
  (`test/canvas_control_wrap_test.dart` is the pattern), and check that the
  test fails when the change it covers is taken out.
