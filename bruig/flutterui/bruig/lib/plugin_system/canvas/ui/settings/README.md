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

`shape_settings.dart` is a complete panel of ordinary size to copy from.

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
  `CanvasSidesField`, through `roomFields` and `cornerFields`: one stepper
  and a link that splits it.
- **A section's tools**: `CanvasToolTiles`, with the settings of the one in
  hand under them.
- **Something to do**: `CanvasTextButton` for an action said in words;
  `CanvasAddChip` for adding one of several things.
- **A word of explanation**: a group's `help`. A loose `CanvasHint` among a
  group's children joins it under the "?".

## What comes without asking

Do not build any of this again for an element:

- **Place and size**: `positionGroup` (`settings_shared.dart`), in Layout.
- **Looks**: `LooksGroup` (`panel_parts.dart`), in Look, from the model's
  own list of each look's settings.
- **On a stage**: `stageSpotSettings`.
- **Motion**: `MotionSummary`, the Arrival and Leaving pickers, and the cue
  card. How a clip moves is set in the Chain, not here.
- **Presets**: `presetsSection`, in More.
- **Type**: `type_parts.dart` (`TypeEdit`, `typeFont`, `typeSize`...),
  wherever words are drawn.
- **A box** (fill, border, corners, padding): `boxGroup`; **a fill** of a
  picture or a pattern: `fillBits`.

## What a panel remembers

Which sections are open is remembered per kind of element, on disk:
`section(e, "look", ...)` is kept as `shape.look`, so a shape's Look and a
chart's Look do not share an answer. A section of your own gets a name of
its own in the same way (`image.picture.mask`, not `mask`).

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
- A model test does not see a dead control or a row that wraps. Pump the
  real panel at a known width and measure
  (`test/canvas_control_wrap_test.dart` is the pattern), and check that the
  test fails when the change it covers is taken out.
