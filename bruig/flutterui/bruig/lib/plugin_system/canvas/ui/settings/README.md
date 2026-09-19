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

An opened area closes with a `CanvasMoreEnd` rule automatically. Do not add
one by hand.

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

Four numbers, in `controls.dart`, and everything reads from them:

| | | |
|---|---|---|
| `canvasControlGap` | 5 | between two controls on a line |
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

`CanvasLineBreak` ends a line deliberately. It costs one row gap, not two.

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
