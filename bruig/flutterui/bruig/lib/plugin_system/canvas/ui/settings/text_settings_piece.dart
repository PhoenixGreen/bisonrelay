part of 'text_settings.dart';

// The settings of a picked piece of a text element: its type, quick strip and
// sections, and the place and room controls behind each piece's button, words
// or picture. Part of text_settings.dart.

/// _pieceEdit is how piece [at]'s type is changed.
TypeEdit _pieceEdit(TextElement e, int at, TextItem item, SettingsWrite write,
        VoidCallback begin, VoidCallback commit) =>
    TypeEdit(
        item.spec,
        (spec) => write(e.copyWith(items: [
              for (var (i, it) in e.items.indexed)
                i == at ? item.copyWith(spec: spec) : it,
            ])),
        begin,
        commit);

/// _pieceQuick is a piece's face, size, colour, and slot in the box, which
/// decides its alignment, so there is no Align.
Widget _pieceQuick(
    BuildContext context,
    CanvasController controller,
    TextElement e,
    int at,
    TextItem item,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit) {
  var w = _TextWrites(e, write, begin, commit);
  var t = _pieceEdit(e, at, item, write, begin, commit);
  var slot = CanvasSlotPicker(
      key: const ValueKey("quickSlot"),
      value: item.slot,
      onChanged: (s) => w.piece(at, item.copyWith(slot: s)));
  return CanvasQuickStrip(key: const ValueKey("quickStrip"), children: [
    if (!item.isIcon) ...[
      panelRow([
        cell(typeFont(t), flex: 3, min: 120),
        cell(typeSize(t), width: 132),
      ]),
      const SizedBox(height: 8),
    ],
    panelRow([
      if (!item.isIcon) cell(typeColour(t), width: 104),
      cell(slot, width: 86),
      // A named style's type laid on the piece and kept as its own, not
      // linked: a piece has no style of its own to follow.
      if (!item.isIcon)
        cell(CanvasDropdown<String>(
          key: const ValueKey("quickPieceStyle"),
          label: "Style",
          value: "",
          width: 80,
          options: [
            ("", "Its own"),
            for (var s in controller.textStyles) (s.name, s.name),
          ],
          onChanged: (v) {
            var style =
                controller.textStyles.where((s) => s.name == v).firstOrNull;
            if (style == null) return;
            w.piece(at, item.copyWith(spec: style.spec));
          },
        ))
      else
        cell(const SizedBox.shrink()),
    ]),
    const SizedBox(height: 8),
    const CanvasStateNote("Its place in the box decides how it lines up."),
  ]);
}

List<Widget> _pieceSections(
    BuildContext context,
    CanvasController controller,
    TextElement e,
    int at,
    TextItem item,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit) {
  var t = _pieceEdit(e, at, item, write, begin, commit);
  var whole = _looksSaid(e, {""});
  var w = _TextWrites(e, write, begin, commit);

  return [
    section(e, "content",
        glyph: SectionGlyph.content,
        icon: item.isIcon ? Icons.image_outlined : Icons.notes,
        title: "Content",
        summary: item.isIcon
            ? (item.icon!.on ? item.says : "No picture chosen")
            : "\u201c${item.text}\u201d",
        initiallyOpen: item.isIcon,
        children: [
          CanvasControlGroup(
              key: const ValueKey("pieceWords"),
              label: "Words",
              hideCaption: true,
              rule: false,
              children: [
                // Its name in the layers; otherwise what it says, which names
                // every picture "Picture".
                CanvasTextField(
                  key: ValueKey("textItemName$at"),
                  label: "Called",
                  value: item.name,
                  hint: item.isIcon ? "Picture" : "the words",
                  width: 200,
                  onChanged: (v) =>
                      w.piece(at, item.copyWith(name: v), live: true),
                  onCommit: commit,
                ),
                if (!item.isIcon) ...[
                  CanvasTextField(
                    key: ValueKey("textItemWords$at"),
                    label: "Words",
                    value: item.text,
                    maxLines: 3,
                    width: 200,
                    onChanged: (v) =>
                        w.piece(at, item.copyWith(text: v), live: true),
                    onCommit: commit,
                  ),
                  typeCaseButtons(t, key: const ValueKey("pieceCase")),
                ],
              ]),
          if (item.isIcon)
            _pictureRow(context, e, at, item, write, begin, commit),
        ]),
    section(e, "look",
        glyph: SectionGlyph.look,
        icon: Icons.palette_outlined,
        title: "Look",
        summary: [
          if (!item.isIcon) typeSummary(item.spec),
          if (_looksSaid(e, {item.id}) case var l when l.isNotEmpty) l,
        ].join(" · "),
        initiallyOpen: true,
        children: [
          if (!item.isIcon)
            CanvasControlGroup(
                key: const ValueKey("pieceLetters"),
                label: "Letters",
                rule: false,
                children: typeLetters(t,
                    vertical: false, justify: false, textCase: false)),
          CanvasControlGroup(
              key: const ValueKey("pieceBox"),
              label: "Box behind it",
              rule: false,
              children: _pieceBoxBits(e, at, item, write, begin, commit)),
          LooksGroup(
              key: const ValueKey("textLooksPiece"),
              controller: controller,
              element: e,
              layer: item.id,
              title: "Looks on this piece"),
          if (whole.isNotEmpty)
            CanvasStateNote(
                "The whole text also has $whole, over this piece "
                "too.",
                action: "On its words",
                onAction: () => controller.pickTextLayer(e.id, null)),
        ]),
    section(e, "layout",
        glyph: SectionGlyph.layout,
        icon: Icons.open_with,
        title: "Layout",
        summary: "${item.slot.label} · gap ${item.gap.round()}",
        children: [
          CanvasControlGroup(
              key: const ValueKey("piecePlace"),
              label: "Where",
              hideCaption: true,
              rule: false,
              children: [
                panelRow([
                  cell(
                      CanvasSlotPicker(
                          key: ValueKey("textItemSlot$at"),
                          value: item.slot,
                          onChanged: (s) =>
                              w.piece(at, item.copyWith(slot: s))),
                      width: 86),
                  cell(Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(item.slot.label,
                        style: const TextStyle(fontSize: 12)),
                  )),
                ]),
                panelRow([
                  cell(CanvasNumberField(
                    key: ValueKey("textItemGap$at"),
                    label: "Gap",
                    value: item.gap,
                    min: -400,
                    max: 400,
                    width: 56,
                    onChanged: (v) =>
                        w.piece(at, item.copyWith(gap: v), live: true),
                    onCommit: commit,
                  )),
                  cell(CanvasNumberField(
                    key: ValueKey("textItemSide$at"),
                    // Both ways from one number: away from the edge its place
                    // holds it to, or back past it.
                    label: "Left/right",
                    value: item.side,
                    min: -2000,
                    max: 2000,
                    width: 56,
                    onChanged: (v) =>
                        w.piece(at, item.copyWith(side: v), live: true),
                    onCommit: commit,
                  )),
                ]),
                const CanvasHint("Gap is the room from the box edge its place "
                    "holds it to, or from the piece before it there. Below "
                    "nought it sits outside the box."),
                if (!item.isIcon && item.slot.down == VerticalAlignSpec.middle)
                  _middleSlotHint,
              ]),
        ]),
    section(e, "motion",
        glyph: SectionGlyph.motion,
        icon: Icons.animation,
        title: "Motion",
        summary: "With the whole text",
        children: [
          MotionSummary(
              controller: controller,
              element: e,
              note: "A piece comes and goes with the whole text. To move it "
                  "on its own, animate its looks in the Chain, or make it an "
                  "element of its own."),
        ]),
    section(e, "more",
        glyph: SectionGlyph.more,
        icon: Icons.more_horiz,
        title: "More",
        summary: "Remove",
        children: [
          CanvasControlGroup(
              key: const ValueKey("pieceMore"),
              label: "More",
              hideCaption: true,
              rule: false,
              children: [
                CanvasTextButton(
                  key: const ValueKey("pieceRemove"),
                  label: "Remove this piece",
                  grow: false,
                  onPressed: item.locked
                      ? null
                      : () {
                          w.now(withPieceLooks(
                              e.copyWith(items: [
                                for (var (i, it) in e.items.indexed)
                                  if (i != at) it,
                              ]),
                              item.id));
                          controller.pickTextLayer(e.id, null);
                        },
                ),
              ]),
        ]),
  ];
}

/// _middleSlotHint explains a middle-slot block moving as words change: the
/// slot centres the stack. Sharing the words' slot holds it under them.
const _middleSlotHint = CanvasHint(
    "A middle slot keeps this block centred, and the gap moves the whole "
    "stack from there — so taking words out lets it settle back down, which "
    "reads as the gap growing. For a fixed distance under the words above "
    "it, give it the same slot as them: blocks in one slot stack, each held "
    "its own gap below the one before.");

/// _pieceBoxBits is what is behind piece [at].
List<Widget> _pieceBoxBits(TextElement e, int at, TextItem item,
    SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  var w = _TextWrites(e, write, begin, commit);

  return [
    // What is behind the piece. The colour is the switch: with nothing
    // painted there is no shape to round and no room to keep.
    CanvasColorButton(
      key: ValueKey("textItemFill$at"),
      label: "Background",
      color: item.box.fill,
      gradient: item.box.fillFade,
      onChanged: (c) =>
          w.piece(at, item.copyWith(box: item.box.copyWith(fill: c))),
      onGradientChanged: (g) => w.piece(
          at,
          item.copyWith(
              box: g == null
                  ? item.box.copyWith(flatFill: true)
                  : item.box.copyWith(fillFade: g))),
    ),
    if (item.box.fill.a > 0) ...[
      // The corner and room fields every box gets (see cornerFields): two
      // numbers beside the colour, each split into four by its link.
      ...cornerFields(
          item.box.corners,
          (c) => w.piece(at, item.copyWith(box: item.box.withCorners(c)),
              live: true),
          commit,
          label: "Round",
          prefix: "textItem$at"),
      ...roomFields(
          item.box.pad,
          (r) =>
              w.piece(at, item.copyWith(box: item.box.withRoom(r)), live: true),
          commit,
          label: "Inside",
          prefix: "textItem$at"),
      const CanvasLineBreak(),
      const CanvasLineBreak(),
    ],
  ];
}

/// _pictureRow is a picture piece's row, shaped as a words piece's: what
/// it is on the line, the rest behind the button.
Widget _pictureRow(BuildContext context, TextElement e, int at, TextItem item,
    SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  var icon = item.icon ?? const TextIcon();

  var w = _TextWrites(e, write, begin, commit);
  void live(TextIcon next) =>
      w.piece(at, item.copyWith(icon: next), live: true);
  void now(TextIcon next) => w.piece(at, item.copyWith(icon: next));

  return CanvasMoreGroup(
    label: item.says,
    onRename: (v) => w.piece(at, item.copyWith(name: v)),
    rule: false,
    remember: "textItem${item.id}",
    tooltip: "Where it sits, its colour, its box and its line",
    row: [
      CanvasIconButton(
        key: ValueKey("textItemPicture$at"),
        icon: icon.on ? Icons.image_outlined : Icons.add_photo_alternate,
        tooltip: icon.on ? "Replace this picture" : "Choose a picture",
        onPressed: () async {
          var id = await pickCanvasImage(context);
          if (id != null) now(icon.copyWith(assetId: id));
        },
      ),
      // The store's pictures, to reuse one without finding the file again.
      CanvasIconButton(
        key: ValueKey("textItemLibrary$at"),
        icon: Icons.photo_library_outlined,
        tooltip: "Use a picture you have already added",
        onPressed: () async {
          var id = await showRecentPictures(context);
          if (id != null) now(icon.copyWith(assetId: id));
        },
      ),
      CanvasNumberField(
        key: ValueKey("textItemSize$at"),
        label: "Size",
        value: icon.size,
        min: 1,
        max: 2000,
        width: 56,
        onChanged: (v) => live(icon.copyWith(size: v)),
        onCommit: commit,
      ),
      // Also turned by its box on the canvas (double-click the picture).
      CanvasNumberField(
        key: ValueKey("textItemTurn$at"),
        label: "Turn",
        value: icon.turn,
        min: -180,
        max: 180,
        width: 56,
        onChanged: (v) => live(icon.copyWith(turn: v)),
        onCommit: commit,
      ),
      CanvasColorButton(
        label: "Tint",
        color: icon.color ?? e.textSpec.color,
        onChanged: (c) => now(icon.copyWith(color: c)),
      ),
      if (icon.color != null)
        CanvasIconButton(
          icon: Icons.format_color_reset_outlined,
          tooltip: "Draw it in its own colours",
          onPressed: () => now(icon.copyWith(clearColor: true)),
        ),
    ],
    // Where it sits and what is behind it are in Layout and Look, as for a
    // piece of writing.
    more: [
      CanvasNumberField(
        label: "Outline",
        value: icon.outlineWidth,
        min: 0,
        max: 60,
        decimals: 1,
        width: 54,
        onChanged: (v) => live(icon.copyWith(outlineWidth: v)),
        onCommit: commit,
      ),
      if (icon.outlineWidth > 0)
        CanvasColorButton(
          label: "Line",
          color: icon.outlineColor,
          onChanged: (c) => now(icon.copyWith(outlineColor: c)),
        ),
      const CanvasLineBreak(),
      CanvasColorButton(
        label: "Fill",
        color: icon.box.fill,
        onChanged: (c) => now(icon.copyWith(box: icon.box.copyWith(fill: c))),
      ),
      CanvasColorButton(
        label: "Border",
        color: icon.box.borderColor,
        onChanged: (c) =>
            now(icon.copyWith(box: icon.box.copyWith(borderColor: c))),
      ),
      CanvasNumberField(
        label: "Width",
        value: icon.box.borderWidth,
        min: 0,
        max: 40,
        decimals: 1,
        width: 54,
        onChanged: (v) =>
            live(icon.copyWith(box: icon.box.copyWith(borderWidth: v))),
        onCommit: commit,
      ),
      CanvasNumberField(
        label: "Round",
        value: icon.box.borderRadius,
        min: 0,
        max: 400,
        width: 54,
        onChanged: (v) =>
            live(icon.copyWith(box: icon.box.copyWith(borderRadius: v))),
        onCommit: commit,
      ),
      CanvasNumberField(
        label: "Inside",
        value: icon.box.padding,
        min: 0,
        max: 400,
        width: 54,
        onChanged: (v) =>
            live(icon.copyWith(box: icon.box.copyWith(padding: v))),
        onCommit: commit,
      ),
      const CanvasLineBreak(),
      CanvasToggle(
        label: "Underline",
        value: icon.underline != null,
        onChanged: (v) => now(v
            ? icon.copyWith(underline: const PartUnderline())
            : icon.copyWith(clearUnderline: true)),
      ),
      if (icon.underline != null) ...[
        CanvasDropdown<PartLineStyle>(
          label: "Line",
          value: icon.underline!.style,
          width: 118,
          options: [for (var v in PartLineStyle.values) (v, v.label)],
          onChanged: (v) =>
              now(icon.copyWith(underline: icon.underline!.copyWith(style: v))),
        ),
        CanvasColorButton(
          label: "Colour",
          color: icon.underline!.color ?? icon.color ?? e.textSpec.color,
          onChanged: (c) =>
              now(icon.copyWith(underline: icon.underline!.copyWith(color: c))),
        ),
        CanvasNumberField(
          label: "Width",
          value: icon.underline!.width,
          min: 0.5,
          max: 60,
          decimals: 1,
          width: 54,
          onChanged: (v) => live(
              icon.copyWith(underline: icon.underline!.copyWith(width: v))),
          onCommit: commit,
        ),
        CanvasNumberField(
          label: "Away",
          value: icon.underline!.away,
          min: -40,
          max: 120,
          width: 54,
          onChanged: (v) =>
              live(icon.copyWith(underline: icon.underline!.copyWith(away: v))),
          onCommit: commit,
        ),
      ],
    ],
  );
}
