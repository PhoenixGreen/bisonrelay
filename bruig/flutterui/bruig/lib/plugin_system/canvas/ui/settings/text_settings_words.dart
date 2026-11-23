part of 'text_settings.dart';

// Where a text's words come from and how they sit in the box, the document's
// named text styles, and how each markdown piece is drawn. Part of
// text_settings.dart.

/// _textWordsCard is where the words come from and how they sit in the box
/// (fitted, a field the page fills in, from a document, round overlaps),
/// in Content under the words typed there.
Widget _textWordsCard(
    BuildContext context,
    CanvasController controller,
    TextElement e,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit) {
  var w = _TextWrites(e, write, begin, commit);

  // Each switch with what it needs below it.
  return CanvasControlGroup(
      key: const ValueKey("textWords"),
      label: "Words",
      help: "Where the words come from and how they sit in the box: sized "
          "to fill it, read from a document in the library, or set around "
          "whatever overlaps it. Field adds something each page fills in: "
          "its number, the number of pages, the words of a text on the page "
          "with the name you give, or a value set on the page. On the "
          "master canvas each shows as #.",
      rule: false,
      children: [
        CanvasToggle(
          label: "Fit to box",
          value: e.autoSize,
          onChanged: (v) => w.now(e.copyWith(autoSize: v)),
        ),
        // A field the page fills in (text_fields.dart), put at the end of
        // the words of the layer picked: its Name typed over on the canvas.
        // Not where the words are a document's, which each read puts back.
        if (!e.wordsFromDocument)
          CanvasDropdown<TextFieldKind?>(
            key: const ValueKey("textAddField"),
            label: "Field",
            value: null,
            options: [
              (null, "Add a field"),
              for (var k in TextFieldKind.values) (k, k.label),
            ],
            onChanged: (kind) {
              if (kind == null) return;
              String joined(String words) =>
                  words.isEmpty || words.endsWith(" ")
                      ? "$words${kind.written}"
                      : "$words ${kind.written}";
              var piece = controller.textLayer(e);
              w.now(piece == null || piece.isIcon
                  ? e.copyWith(text: joined(e.text))
                  : e.copyWith(items: [
                      for (var it in e.items)
                        it.id == piece.id
                            ? it.copyWith(text: joined(it.text))
                            : it,
                    ]));
            },
          ),
        // Words of this shape's own, for several page shapes: a two-line
        // banner headline is four in a feed, so it needs fewer words. Off,
        // one text everywhere, a typo fixed once.
        if (controller.document.targets.length > 1)
          CanvasToggle(
            key: const ValueKey("textOwnWordsHere"),
            label: "Own words here",
            value: e.base.ownText,
            onChanged: (v) => w.now(e.withBase(ownText: v) as TextElement),
          ),
        // Words from the Writing library, not typed. Not on a box being
        // flowed into, whose words belong to the box before it.
        if (flowSourceOf(e, controller.document) == null)
          CanvasToggle(
            key: const ValueKey("textFromDocument"),
            label: "From document",
            value: e.wordsFromDocument,
            onChanged: (v) async {
              if (!v) {
                // Back to what was typed before the document took over, or the
                // switch would be off with the document's words still showing.
                w.now(e.copyWith(
                    text: e.document.wasText.isEmpty
                        ? e.text
                        : e.document.wasText,
                    document: const TextDocumentRef(),
                    documentParts: const []));
                return;
              }
              var picked = await pickTextDocument(context);
              var fresh = freshOf(controller, e);
              if (picked == null || fresh == null) return;
              w.now(fresh.copyWith(
                  document: picked.copyWith(wasText: fresh.text),
                  documentParts: const []));
              await refreshTextDocuments(controller);
            },
          ),
        if (e.wordsFromDocument) ...[
          CanvasIconButton(
            key: const ValueKey("textDocumentPick"),
            icon: Icons.description_outlined,
            tooltip: "Choose another document",
            onPressed: () async {
              var picked = await pickTextDocument(context);
              var fresh = freshOf(controller, e);
              if (picked == null || fresh == null) return;
              // The remembered words are the element's own, not the last
              // document's, so changing the document leaves them alone.
              w.now(fresh.copyWith(
                  document: fresh.document
                      .copyWith(folder: picked.folder, name: picked.name),
                  documentParts: const []));
              await refreshTextDocuments(controller);
            },
          ),
          CanvasReadout(label: "Document", value: e.document.says),
          CanvasToggle(
            key: const ValueKey("textDocumentMarkdown"),
            label: "Markdown",
            value: e.document.markdown,
            onChanged: (v) async {
              w.now(e.copyWith(document: e.document.copyWith(markdown: v)));
              await refreshTextDocuments(controller);
            },
          ),
          const CanvasHint(
              "The words come from the library and are read again every "
              "few seconds, so editing the document changes the canvas. "
              "With Markdown off they arrive as plain text — every mark "
              "stripped, all of the styling from the settings here. With "
              "it on, only the pieces switched on are honoured; the rest "
              "are still stripped, because a headline reading \"## Title\" "
              "is not markdown being ignored, it is markdown showing."),
        ],
        // Words set around whatever overlaps the box: the same kind of
        // question as the other two.
        CanvasToggle(
          key: const ValueKey("textWrap"),
          label: "Wrap text",
          value: e.wrap.on,
          onChanged: (v) => w.now(e.copyWith(wrap: e.wrap.copyWith(on: v))),
        ),
        if (e.wrap.on) ...[
          const CanvasLineBreak(),
          CanvasNumberField(
            label: "Space",
            value: e.wrap.gap,
            min: 0,
            max: 400,
            decimals: 0,
            width: 62,
            onChanged: (v) {
              begin();
              write(e.copyWith(wrap: e.wrap.copyWith(gap: v)));
            },
            onCommit: commit,
          ),
          CanvasDropdown<WrapSide>(
            key: const ValueKey("textWrapSide"),
            label: "Words go",
            value: e.wrap.side,
            width: 132,
            options: [for (var s in WrapSide.values) (s, s.label)],
            onChanged: (v) => w.now(e.copyWith(wrap: e.wrap.copyWith(side: v))),
          ),
          const CanvasHint(
              "The words are set line by line around every visible "
              "element that overlaps this box, leaving Space between "
              "them. Both sides fills the room either side of something "
              "narrow; Left or Right keeps the words in one block beside "
              "it. Anything that covers the box from top to bottom is "
              "left out — that is a background, and a paragraph cannot go "
              "around it."),
        ],
      ]);
}

/// _textStyleCard is the document's named text styles for [e]: apply, make
/// or change one. Under Presets, the other reuse of a look.
Widget _textStyleCard(CanvasController controller, TextElement e) {
  var styles = controller.textStyles;
  var styled = styles.any((t) => t.name == e.style);
  return CanvasControlGroup(
    key: const ValueKey("textStyle"),
    label: "Text style",
    help: "The document's named styles. Set this text in one, make "
        "its type a new one, or change the one it is in -- which "
        "changes every text set in it whose type was not changed by hand.",
    rule: false,
    children: [
      if (styles.isNotEmpty)
        CanvasDropdown<String>(
          key: const ValueKey("textStylePick"),
          label: "Style",
          value: styled ? e.style : "",
          width: 120,
          options: [
            ("", "Its own"),
            for (var t in styles) (t.name, t.name),
          ],
          onChanged: (v) => controller.useTextStyle(e.id, v),
        ),
      // In words: under the presets, an icon alone reads as another save.
      CanvasTextButton(
        key: const ValueKey("textStyleSave"),
        icon: Icons.bookmark_add_outlined,
        label: "Make this text's type a style",
        onPressed: () => controller.saveTextStyle(e),
      ),
      if (styled) ...[
        CanvasIconButton(
          key: const ValueKey("textStyleUpdate"),
          icon: Icons.sync,
          tooltip: "Change the style to this text's type -- every text in "
              "\"${e.style}\" not changed by hand changes with it",
          onPressed: () => controller.updateTextStyle(e.style, e.textSpec),
        ),
        CanvasTextField(
          key: const ValueKey("textStyleName"),
          label: "Name",
          value: e.style,
          width: 96,
          onChanged: (v) {
            controller.beginInteraction();
            controller.renameTextStyle(e.style, v, transient: true);
          },
          onCommit: controller.endInteraction,
        ),
        CanvasIconButton(
          key: const ValueKey("textStyleRemove"),
          icon: Icons.bookmark_remove_outlined,
          tooltip: "Forget the style; its texts keep their type",
          onPressed: () => controller.removeTextStyle(e.style),
        ),
      ],
    ],
  );
}

/// _markdownSection is how each markdown piece is drawn: a look each, as
/// headings differ; all overrides of the element's type settings.
Widget _markdownSection(CanvasController controller, TextElement e,
    SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  var allow = e.document.allow;

  Future<void> set(MarkdownKind kind, MarkdownLook look) async {
    begin();
    write(e.copyWith(
        document: e.document.copyWith(allow: allow.withLook(kind, look))));
    commit();
    // The document is reread, as what the marks mean has changed.
    await refreshTextDocuments(controller);
  }

  var on = [
    for (var k in MarkdownKind.values)
      if (allow.allows(k)) k.label
  ];

  return CanvasExpander(
    label: "Markdown",
    remember: "textMarkdown",
    trailing: on.isEmpty ? "None" : "${on.length}",
    children: [
      const CanvasHint(
          "Each piece of markdown the document uses, and how it is drawn "
          "here. Switched on and left alone, a piece follows the type "
          "settings above — so changing the face or the colour of the "
          "element changes its headings with it. Anything switched off is "
          "stripped rather than shown: a headline reading \"## Title\" is not "
          "markdown being ignored, it is markdown showing."),
      for (var kind in MarkdownKind.values)
        CanvasControlGroup(label: kind.label, children: [
          CanvasToggle(
            key: ValueKey("markdown${kind.name}"),
            label: "Honour it",
            value: allow.allows(kind),
            onChanged: (v) => set(kind, allow.lookFor(kind).copyWith(on: v)),
          ),
          if (allow.allows(kind)) ...[
            CanvasNumberField(
              label: "Size",
              value: allow.lookFor(kind).scale ?? kind.scale,
              min: 0.1,
              max: 8,
              decimals: 2,
              width: 62,
              onChanged: (v) {
                begin();
                write(e.copyWith(
                    document: e.document.copyWith(
                        allow: allow.withLook(
                            kind, allow.lookFor(kind).copyWith(scale: v)))));
              },
              onCommit: () {
                commit();
                refreshTextDocuments(controller);
              },
            ),
            CanvasColorButton(
              label: "Colour",
              color:
                  allow.lookFor(kind).color ?? kind.color ?? e.textSpec.color,
              onChanged: (c) =>
                  set(kind, allow.lookFor(kind).copyWith(color: c)),
            ),
            CanvasNumberField(
              label: "Weight",
              value: (allow.lookFor(kind).weight ??
                      kind.weight ??
                      e.textSpec.weight)
                  .toDouble(),
              min: 100,
              max: 900,
              decimals: 0,
              width: 62,
              onChanged: (v) {
                begin();
                write(e.copyWith(
                    document: e.document.copyWith(
                        allow: allow.withLook(
                            kind,
                            allow
                                .lookFor(kind)
                                .copyWith(weight: (v / 100).round() * 100)))));
              },
              onCommit: () {
                commit();
                refreshTextDocuments(controller);
              },
            ),
            CanvasToggle(
              label: "Italic",
              value: allow.lookFor(kind).italic ?? kind.slanted,
              onChanged: (v) =>
                  set(kind, allow.lookFor(kind).copyWith(italic: v)),
            ),
            CanvasToggle(
              label: "Underline",
              value: allow.lookFor(kind).underline ?? kind.underlined,
              onChanged: (v) =>
                  set(kind, allow.lookFor(kind).copyWith(underline: v)),
            ),
            CanvasDropdown<String>(
              label: "Face",
              value: allow.lookFor(kind).family ?? "",
              width: 132,
              options: [
                ("", "Same as the text"),
                ...fontOptions(allow.lookFor(kind).family ?? ""),
              ],
              onChanged: (v) => set(
                  kind,
                  v.isEmpty
                      ? allow.lookFor(kind).copyWith(clearFamily: true)
                      : allow.lookFor(kind).copyWith(family: v)),
            ),
          ],
        ]),
    ],
  );
}
