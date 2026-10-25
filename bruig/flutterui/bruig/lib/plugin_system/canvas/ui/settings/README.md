# How an element's settings are laid out

Every element's settings are built from the same small set of controls in
`controls.dart`, and they are meant to read as one panel rather than as nine
panels by different hands. This is what that means in practice. An element
added later should follow it rather than be retrofitted, which is what the
chart had to be.

## The shape of a group

The unit is a **line of controls with a button on the end of it**:

```dart
CanvasMoreGroup(
  label: "Grid",
  remember: "chartGridMore",
  tooltip: "How finely it is ruled, and what colour",
  row: [ /* what anybody changes */ ],
  more: [ /* what is set once and left */ ],
)
```

The row holds what the reader came for; the button holds the rest. A panel
where everything is equally visible is a panel where nothing is.

What goes on the row:

- what changes how the element reads at a glance — its colour, its weight, the
  one control that decides its shape;
- anything that can be keyframed, because the diamond beside it is the only
  thing saying that it can be.

What goes behind the button: ends, caps, dashes, padding, gaps, second
colours, and the toggles somebody sets once a document.

`remember` is required in practice — the settings panel is rebuilt on every
change to the element, and without it an area shuts itself the moment anybody
uses what is inside it. Name it after the element and the group, not after the
label alone, so a chart's Grid and a table's Grid do not share one answer.

An opened area is drawn on a ground of its own automatically -- a tinted
rectangle under the row, so what the button revealed can be told from what was
always there. Do not draw one by hand, and do not put a rule at the foot of
it: that is what this replaced.

## Sections, groups and rules

Three levels, and only three:

| | |
|---|---|
| `boxed(context, CanvasExpander(...))` | a section that holds a panel of its own — a data grid, a list of columns, the animation controls. It has a border because what is inside it is not a row of controls. |
| `CanvasControlGroup` / `CanvasMoreGroup` | a captioned run of controls. The ordinary case. |
| `rule: false` | this group and the one under it are one subject. **This is the usual case.** Most elements are one run of lines answering one question — what is this path, what is this button, what does this picture look like — and a rule between each pair turns it into five answers. The rule under the position row stays, because where an element sits really is a different subject from what it is. |

A group whose name is already said by the panel header takes
`hideCaption: true` — "Line" under a header reading "Line settings" is the
word twice. A control that is the only one under its caption usually wants the
caption on the control instead, or a placeholder inside it: `X label` inside
an empty field says more than `X label` above a full one.

Do not box a group. The border is for a section holding a panel, and a rule
round a single row reads as a section somebody left open.

## Spacing

Five numbers, in `controls.dart`, and everything reads from them:

| | | |
|---|---|---|
| `canvasControlGap` | 5 | between two controls on a line |
| `canvasCaptionedGap` | 8 | after a control with a caption over it, so neighbouring captions do not touch |
| `canvasRowGap` | 8 | between one line of a group and the next |
| `canvasCaptionGap` | 7 | under a group's name |
| `canvasGroupGap` | 24 | under every group |

A rule between two groups sits in the middle of a doubled group gap — the same
above as below, which is the one people notice.

The group gap is three times the row gap, and it has to be: most panels have no
rules left in them, so the gap is the only thing saying where one group ends.

Never write a pixel gap into an element's settings. The reason these are
constants is that they were not: captions sat seven pixels over their controls
in one group and fourteen in another, and rules had twelve pixels above and
sixteen below, none of it far enough out to notice on its own and all of it
together a panel that read as assembled.

## Width

Controls declare the width they will not go below, not the width they will be.
`CanvasTextField`, `CanvasNumberField` and `CanvasDropdown` grow into whatever
room the line has left; `grow: false` opts out.

The extra is shared as a per-control amount rather than by making everything
the same width, and the amount is the smallest any line of the group can
afford. So a line of four fields and a line of two below it come out in the
same columns — which is why Angle sits under X — and a title field beside a
number field stays the wider of the two. Give two controls that should line up
the same minimum width.

Settings fill their row. A line started on purpose — the first, or one after a
`CanvasLineBreak` or a control as wide as the line (a switch row in a card) —
with one growable control on it takes the whole line and is left out of the
sharing: a dropdown alone on its line held to what a line of four could afford
cut its own name to "Noth…" beside empty space. A line that only exists
because the one above it ran out of room still shares, where that line has
columns to keep, so a wrapped row of numbers stays in columns.

In a card a dropdown is never narrower than its longest name between its
arrows, so a line too short for it wraps instead of cutting the name. Text
fields grow like the rest; do not give one `grow: false` to keep a row on one
line — a field too narrow for what is typed in it is the same fault.

`CanvasLineBreak` ends a line deliberately. It costs one row gap, not two.

`CanvasWrap` puts a row gap between its lines by default. Do not pass
`runSpacing: 0` to a wrap holding captioned controls: each line's captions
end up on the underline of the line above.

## Order

Down the panel, in the order the work happens. For the chart that is: where
the numbers come from, the numbers, what each series is, how it is measured,
what is written on it, and last how it arrives. For anything else, ask what
somebody does first and put that first. Animation goes last everywhere,
because it is a handful of choices made once.

## What comes for free

Do not re-implement any of this per element:

- **Position** — `positionGroup` is the same six numbers for a picture as for
  a pitch.
- **Presets** — `presetsSection` is one uncaptioned row: the list, a save
  button, and rename and remove for a design of the reader's own.
- **Type and box** — `typeGroups` and `boxGroup` wherever words are drawn.
- **Animation** — `elementAnimationSection`, boxed, last.
- **Keyframe easing** — `keyframeEasingGroup`.

## Testing a layout

Model tests do not see a dead control or a row that wraps. `canvas_control_wrap_test.dart`
is the pattern: pump the real panel at a known width and measure. Check that a
test bites by reverting the change it covers — a layout test that passes
either way is worse than none, because it reads as cover.

## Sectioned panels

Every element's panel is sections now -- a picture's first, then the rest
and the canvas's own background (2026-10-18). The earlier parts of this file
describe the flat layout, which is still what a group outside a section --
several elements picked, a dialog -- is drawn as.

Every panel has the same frame, from `element_sections.dart`:
**Position** first (`positionSection`), the element's own sections, then
**Animation** (`animationPanelSection`, with the cue card) and **Presets**
(`presetsPanelSection`) last. Each section is remembered per kind of element
-- `shape.fill`, not `fill` -- through `section(e, name, ...)`. An expander
that was a subject of its own becomes a section with `expanderSection`; one
left inside a section draws itself as a card that folds, and `boxed` adds no
border there. A `CanvasMoreGroup` in a card shows everything, row and more:
the section is the fold. A loose `CanvasHint` among a section's own children
goes to the "?" on its heading row, and `CanvasSection.action` puts a button
there. A grid with buttons over its columns -- a table's cells, a squad --
keeps the ordinary size inside a card with `CanvasCards.none`.

`ProceduralSettings(sections: true)` lays a background out as Pattern
layers, Pattern, Colour and amount, Movement, Effects and Lights.

The parts:

- `CanvasSection` for each subject -- an icon, a title, and a one-line
  `summary` of how it is set, so the panel reads shut. `changes` puts a dot
  on it and `onReset` a reset beside its chevron; `forceOpen` opens it when
  a tool it holds is picked from the keyboard. Remember it per kind of thing
  edited: `image.picture.mask`, not `mask`.
- Inside a section everything is in **cards** (`CanvasCards`): each
  `CanvasControlGroup` is drawn as one, its name and a "?" over its
  controls. Give the group a `help` -- the "?" holds it, and any
  `CanvasHint` among its children joins it there rather than floating in
  the row. The controls are a size up (`cardControlHeight`) and further
  apart (`cardGap`), a `CanvasToggle` is a line with a switch at its end,
  and every `CanvasNumberField` is drawn as a `CanvasStepper` -- an arrow
  either side of a number dragged sideways or double-clicked to type. None
  of this changes a panel that is not in sections.
- `CanvasSidesField` for four numbers that are usually one -- a border's
  sides, a box's corners, its padding: one stepper and a link that splits
  it into one each. `roomFields` and `cornerFields` build it; there is no
  separate line of sides behind a More button any more.
- `CanvasTiles` for a choice that can be shown -- a filter, a blend, a
  texture, a shape, an animation's kind -- clicked, never tried on a hover
  in a card (a hover try made the panel treat the hovered tile as chosen);
  `CanvasToolTiles` for a section's tools, with the one in hand's settings
  under them; `CanvasSegmented` for two to four short choices side by side;
  `CanvasTextButton` for an action said in words.

Tests open a section with `openSection` and type into a stepper with
`typeNumber` / `typeInto`, in `test/canvas_panel_helpers.dart`.
