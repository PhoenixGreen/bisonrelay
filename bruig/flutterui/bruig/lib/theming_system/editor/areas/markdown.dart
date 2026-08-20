import 'dart:convert';
import 'dart:io';

import 'package:bruig/components/md_elements.dart';
import 'package:bruig/components/snackbars.dart';
import 'package:bruig/components/text.dart';
import 'package:file_picker/file_picker.dart';
import 'package:bruig/theming_system/editor/areas/sample_image.dart';
import 'package:bruig/theming_system/theme_editor.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';

// markdown.dart is the "Markdown" area's settings: which style guide posts
// are read in, and whether a post may ask for a different one.
//
// A style guide is a named set of rules for how a post's headings, quotes,
// code, lists and pictures are set -- see model/markdown_style.dart. It is
// always local. A post carries the name of one and never the guide itself,
// so a name this device has never heard of falls back to Default rather than
// arriving with anything to apply.

/// _sampleFor is the markdown the preview renders for one element.
///
/// Each carries a line of ordinary body text as well, because nearly every
/// setting is expressed relative to the body -- a heading at 190% means
/// nothing without the 100% beside it.
String _sampleFor(_Element element) => switch (element) {
      _Element.text => """
# Heading one
Ordinary body text, which is what every other size is measured against. This
paragraph runs long enough to wrap, so the line height has somewhere to show.

A second paragraph, so the space between them is visible.
## Heading two
### Heading three
#### Heading four
##### Heading five
###### Heading six
""",
      _Element.emphasis => """
Ordinary body text, so the two below have something to be measured against.

Body text with **a bold run** in the middle of it, and _an italic one_
further along, and **_both at once_** to finish.
""",
      _Element.links => """
Body text with [a link](https://decred.org) in the middle of it, and
[another](https://bisonrelay.org) further along.
""",
      // The callout goes in beside the plain quotation because it is one:
      // Markdown has no callout of its own, and a blockquote opening with a
      // bold word is what every renderer shows sensibly. Anything set here
      // is what a callout is set in too, which is only obvious when the two
      // are side by side.
      _Element.quotes => """
Body text before the quotation.

> A quotation, which shows the bar and the background.
> It runs to a second line so the bar's full height can be seen.

> **Note** A callout is a quotation opening with a bold word, so it is set
> in exactly what the rules below say.

Body text after it.
""",
      // One of each shape: a callout with everything filled in, and a pair
      // of cards side by side, because the settings below are about how the
      // box is drawn and that only shows with more than one of them.
      _Element.cards => """
Body text above the callout.

--card--
icon: info
title: A callout
text: A callout and a card are the same thing with a different amount
  filled in. Every field is optional.
--/card--

--cards[2]--
--card--
icon: announce
title: Stay updated
text: A card with a button under it.
button: Subscribe
link: https://decred.org
--/card--
--card--
icon: star
title: Beside it
text: Two across, and up to three rows of them.
--/card--
--/cards--

Body text below them.
""",
      // Real code rather than two lines of prose: the padding needs
      // something to sit around, the numbering needs more than a line or
      // two to be worth looking at, and the highlighting needs a comment, a
      // string, a number and a keyword before any of it shows.
      _Element.code => """
Body text with `inline code` in it.

```
// Count how many of them are still open.
function openChannels(list) {
  const open = list.filter(c => c.state == "open");
  return open.length + 1;
}
```
""",
      _Element.lists => """
Body text before the list.

- The first item
- The second item, long enough to wrap onto another line so the indent shows
- The third item

1. A numbered item
2. Another

- [x] A task that is done
- [ ] A task that is not
""",
      _Element.tables => """
Body text before the table.

| Element | Set in | Notes |
| --- | --- | --- |
| Heading | The heading rules | A share of the body |
| Quote | The quote rules | Bar and background |

Body text after it.
""",
      // Flowed rather than divided by hand, because that is what the
      // buttons in a post's Formatting & Content panel write and so what
      // most runs will be. Enough blocks in it for the balancing to have
      // something to do, and a picture so the divider has a tall column to
      // run beside.
      _Element.columns => """
Body text above the columns.

--columns[2]--
### A flowed run
The writing is shared out between the columns rather than divided by hand,
in the order it was written -- so when the page is too narrow for columns
and they stack, it still reads as the post it was.

- The first point
- The second point, longer than the first so the balance has something to
  weigh

${sampleImageMarkdown ?? ""}

A closing paragraph, which is the last block the run has to place.
--/columns--

Body text below them.
""",
      _Element.header => """
--header[200]--
left: ### My site
right: A line about it
nav: --include[navigation]--
--/header--

--nav[pills]--
[Home](index.md)
[About](about.md)
[Contact](contact.md)
--/nav--

Body text below the header, set the way the rest of a page is.
""",
      _Element.gallery => """
Body text above the gallery.

--grid--
${sampleImageMarkdown ?? ""}
### The first one
A caption, which is the writing after the picture.
${sampleImageMarkdown ?? ""}
### The second one
Captions need not be the same length; the cells hang from a common top.
--/grid--

Body text below it.
""",
      _Element.rule => """
Body text above the rule.

---

Body text below it.
""",
      // A real embed, drawn rather than described: the width is a share of
      // the column and the corners, border and spacing are drawn around it,
      // none of which can be judged from a sentence.
      _Element.images => """
Body text above the picture.

${sampleImageMarkdown ?? ""}

Body text below it, so the spacing has something to push against.
""",
    };

/// _Element is which part of a post is being tuned.
///
/// One at a time, picked from a dropdown, for the same reason the Buttons
/// area does it: ten elements' worth of sliders stacked up reads as one
/// undifferentiated wall, and only one of them is being adjusted anyway.
/// Which one is showing is local to the editor and is not stored on a theme.
enum _Element {
  text("Text and headings"),
  emphasis("Bold and italic"),
  links("Links"),
  quotes("Quotes"),
  cards("Callouts and cards"),
  code("Code"),
  lists("Lists"),
  tables("Tables"),
  columns("Columns"),
  gallery("Gallery"),
  header("Header and navigation"),
  rule("Horizontal rule"),
  images("Images");

  final String label;
  const _Element(this.label);
}

List<Widget> markdownAreaEditor(AreaEditorContext ctx) =>
    [_MarkdownEditor(ctx)];

class _MarkdownEditor extends StatefulWidget {
  final AreaEditorContext ctx;
  const _MarkdownEditor(this.ctx);

  @override
  State<_MarkdownEditor> createState() => _MarkdownEditorState();
}

class _MarkdownEditorState extends State<_MarkdownEditor> {
  /// _lastElement is the element that was last being worked on.
  ///
  /// Static, so it outlives this State. The editor is built fresh every time
  /// the page is come back to -- switching to another theme area and back is
  /// enough, let alone leaving Settings -- and starting again at Text and
  /// headings each time means finding your place before every edit.
  ///
  /// Not stored on the theme: which control you happen to have open is not
  /// part of how the app looks, and a preset carrying it would hand your
  /// place to whoever you sent the theme to. Not written to disk either --
  /// a fresh start opening on the first element is the right place to begin.
  static _Element _lastElement = _Element.text;

  _Element element = _lastElement;

  @override
  void initState() {
    super.initState();
    // Prepared once, not per frame: this page rebuilds on every drag of
    // every slider.
    if (sampleImageMarkdown == null) {
      var seed = ThemeNotifier.of(context, listen: false)
          .surfaceColor(SurfaceColor.primary);
      prepareSampleImage(seed).then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    var ctx = widget.ctx;
    var style = ctx.style;
    var unsaved = style.markdownCustomGuide != null;
    var guide = style.markdownGuide(builtInGuideFor(style.markdownGuideId));

    /// edit changes one rule of the guide.
    ///
    /// A built-in is never changed: the first edit to one forks it into a
    /// guide of the reader's own and every edit after goes to the fork. The
    /// built-ins are what a published post names, so an "Article" quietly
    /// edited here would make a post naming it mean something different on
    /// this machine than on anyone else's.
    void edit(MarkdownStyleGuide Function(MarkdownStyleGuide) change) {
      var next = change(guide.builtIn ? guide.forked("custom") : guide);
      ctx.setStyle((s) => s.copyWith(markdownCustomGuide: next.toJson()));
    }

    // The working copy stands in the picker as itself, so the name above the
    // settings is the name of the guide those settings belong to. Editing a
    // built-in used to leave "Article" showing while every control under it
    // was driving a fork called "Article (edited)" -- the same trap the
    // theme presets avoid by putting the new draft in the dropdown the
    // moment it exists.
    //
    // Only when it isn't already there: editing a guide of the reader's own
    // edits it in place, under the id it is saved as.
    var choices = style.markdownGuideChoices(builtInGuides);
    if (unsaved && !choices.any((g) => g.id == guide.id)) {
      choices = [...choices, guide];
    }
    var chosen =
        choices.any((g) => g.id == guide.id) ? guide.id : defaultGuideId;
    var savedGuide = style.markdownSavedGuides.containsKey(chosen);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: ctx.choice<String>(
            "Style guide",
            value: chosen,
            options: [for (var g in choices) g.id],
            labelOf: (id) {
              var g = choices.firstWhere((g) => g.id == id,
                  orElse: () => choices.first);
              return unsaved && g.id == guide.id
                  ? "${g.name} (unsaved)"
                  : g.name;
            },
            onChanged: (v) => ctx.setStyle((s) =>
                s.copyWith(markdownGuideId: v, clearMarkdownCustomGuide: true)),
          ),
        ),
        // The same actions, in the same order, as the theme presets above:
        // new, save, rename, import, export, delete.
        //
        // Save writes over the guide being edited. It used to be the only
        // way to keep a change and it always minted a fresh id, so editing
        // a guide of your own and saving left you with a second copy of it
        // -- and doing that twice, a third. Making a new guide is what the
        // New button is for, and saving now means what it says.
        IconButton(
          tooltip: "New style guide",
          icon: const Icon(Icons.add, size: 20),
          onPressed: () => _saveAsNew(ctx, guide, title: "New style guide"),
        ),
        IconButton(
          tooltip: savedGuide
              ? "Save changes to \"${guide.name}\""
              // A built-in is the same everywhere by definition -- that is
              // the whole point of naming one in a post -- so there is
              // nothing to write over and saving names a new guide.
              : "Save as a style guide of your own",
          icon: const Icon(Icons.save_outlined, size: 20),
          onPressed: !unsaved
              ? null
              : savedGuide
                  ? () => _saveOver(ctx, guide, chosen)
                  : () => _saveAsNew(ctx, guide, title: "Save style guide"),
        ),
        if (savedGuide)
          IconButton(
            tooltip: "Rename this style guide",
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () => _rename(ctx, guide, chosen),
          ),
        IconButton(
          tooltip: "Import a style guide",
          icon: const Icon(Icons.file_upload_outlined, size: 20),
          onPressed: () => _import(ctx),
        ),
        IconButton(
          tooltip: "Export this style guide",
          icon: const Icon(Icons.file_download_outlined, size: 20),
          onPressed: () => _export(guide),
        ),
        if (savedGuide)
          IconButton(
            tooltip: "Delete this style guide",
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () => _delete(ctx, chosen),
          ),
      ]),
      ctx.note(unsaved
          ? savedGuide
              // Editing one of your own: Save writes back to it.
              ? "Unsaved changes to \"${guide.name}\". They are in use "
                  "already -- Save keeps them, or choose a guide above to "
                  "start again from that one."
              // Editing a built-in: there is nothing to write back to.
              : "Unsaved changes. They are in use already -- Save keeps "
                  "them as a guide of your own, since the built-in ones "
                  "have to stay the same on every device."
          : guide.builtIn
              ? "How posts are set on this device. Changing anything below "
                  "starts a guide of your own; the built-in ones are left "
                  "as they are."
              : "How posts are set on this device. Changing anything below "
                  "edits this guide -- New starts another one from it."),
      const SizedBox(height: 16),
      ctx.choice<_Element>(
        "Element",
        value: element,
        options: _Element.values,
        labelOf: (e) => e.label,
        onChanged: (e) => setState(() => element = _lastElement = e),
      ),
      const SizedBox(height: 12),
      // The preview sits between the picker and the settings, so a change
      // and its effect are next to each other rather than a scroll apart.
      _MarkdownPreview(element: element),
      const SizedBox(height: 16),
      ..._settingsFor(ctx, guide, edit),
    ]);
  }

  /// _textControls are the five every text rule has.
  List<Widget> _textControls(
    AreaEditorContext ctx,
    String name,
    TextRule rule,
    void Function(MarkdownStyleGuide Function(MarkdownStyleGuide)) edit,
    MarkdownStyleGuide Function(MarkdownStyleGuide, TextRule) put, {
    double maxScale = 3.0,
  }) =>
      [
        ctx.slider("md-$name-scale", rule.scale,
            label: (v) => "Size: ${(v * 100).round()}% of body text",
            min: 0.6,
            max: maxScale,
            divisions: ((maxScale - 0.6) * 20).round(),
            onCommit: (v) => edit((g) => put(g, rule.copyWith(scale: v)))),
        // The same palette dropdown every other colour in this editor uses,
        // rather than a private list of eight role names. A role names a
        // colour without showing it, and the eight were not the palette the
        // rest of the theme is built from -- so "Accent" here and Accent
        // anywhere else in Appearance were two unrelated things.
        _inkPick(ctx, "Colour", rule.ink,
            (i) => edit((g) => put(g, rule.copyWith(ink: i)))),
        ctx.choice<MarkdownFont>(
          "Font",
          value: rule.font,
          options: MarkdownFont.values,
          labelOf: (f) => f.label,
          onChanged: (f) => edit((g) => put(g, rule.copyWith(font: f))),
        ),
        ctx.toggle("Bold",
            value: rule.bold ?? false,
            onChanged: (v) => edit((g) => put(g, rule.copyWith(bold: v)))),
        ctx.toggle("Italic",
            value: rule.italic ?? false,
            onChanged: (v) => edit((g) => put(g, rule.copyWith(italic: v)))),
        // Letter spacing was in the guide and saved with it from the start,
        // and was the one thing in a text rule with nowhere to set it.
        ctx.slider("md-$name-tracking", rule.letterSpacing ?? 0,
            label: (v) => v == 0
                ? "Letter spacing: Theme default"
                : "Letter spacing: ${v.toStringAsFixed(2)}px",
            min: -1,
            max: 4,
            divisions: 50,
            onCommit: (v) =>
                edit((g) => put(g, rule.copyWith(letterSpacing: v)))),
      ];

  /// _promptName asks for a name, returning null if the reader backs out or
  /// leaves it blank.
  Future<String?> _promptName(String title, String initial,
      {String action = "Save"}) async {
    var controller = TextEditingController(text: initial);
    var name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: "Name"),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: Text(action)),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return null;
    return name.trim();
  }

  /// _saveAsNew names the working copy and puts it in the library as a guide
  /// of its own.
  ///
  /// What the New button does, and what Save falls back to on a built-in --
  /// there is nothing to write over in that case, since a built-in is the
  /// same on every device by definition.
  void _saveAsNew(AreaEditorContext ctx, MarkdownStyleGuide guide,
      {required String title}) async {
    var name = await _promptName(title, guide.name.replaceAll(" (edited)", ""));
    if (name == null || !mounted) return;

    // A fresh id each time, so making two guides from the same starting
    // point keeps both rather than the second quietly replacing the first.
    var id = "guide-${DateTime.now().microsecondsSinceEpoch}";
    var saved = guide.copyWith(id: id, name: name);
    ctx.setStyle((s) => s.copyWith(
          markdownSavedGuides: {...s.markdownSavedGuides, id: saved.toJson()},
          markdownGuideId: id,
          clearMarkdownCustomGuide: true,
        ));
  }

  /// _saveOver writes the working copy back to the guide it came from.
  ///
  /// No dialog: the guide already has a name, and asking for it again is how
  /// this used to end up making a second copy every time. Renaming is its
  /// own button.
  void _saveOver(AreaEditorContext ctx, MarkdownStyleGuide guide, String id) {
    var saved = guide.copyWith(id: id);
    ctx.setStyle((s) => s.copyWith(
          markdownSavedGuides: {...s.markdownSavedGuides, id: saved.toJson()},
          markdownGuideId: id,
          clearMarkdownCustomGuide: true,
        ));
  }

  /// _rename changes a saved guide's name, keeping its id.
  ///
  /// The id is what a post names and what the picker selects, so renaming
  /// leaves both alone -- this is the label, not the identity. Any unsaved
  /// changes are carried along rather than dropped: the name is on the same
  /// working copy the settings below are editing.
  void _rename(
      AreaEditorContext ctx, MarkdownStyleGuide guide, String id) async {
    var name =
        await _promptName("Rename style guide", guide.name, action: "Rename");
    if (name == null || !mounted) return;
    var renamed = guide.copyWith(id: id, name: name);
    ctx.setStyle((s) => s.copyWith(
          markdownSavedGuides: {...s.markdownSavedGuides, id: renamed.toJson()},
          markdownGuideId: id,
          // The working copy is rewritten rather than cleared, so a rename
          // mid-edit doesn't quietly throw the edits away.
          markdownCustomGuide:
              s.markdownCustomGuide == null ? null : renamed.toJson(),
        ));
  }

  void _delete(AreaEditorContext ctx, String id) {
    ctx.setStyle((s) => s.copyWith(
          markdownSavedGuides: {...s.markdownSavedGuides}..remove(id),
          markdownGuideId: defaultGuideId,
          clearMarkdownCustomGuide: true,
        ));
  }

  /// _export writes the guide to a file.
  ///
  /// Plain JSON rather than the zip a theme preset is exported as: a preset
  /// carries pictures and so needs a container, and a guide is only ever the
  /// rules -- it names colours by palette slot and role, never by value, so
  /// there is nothing else to travel with it. That is also what lets an
  /// exported guide look right in the theme it lands in rather than dragging
  /// the exporter's colours along.
  Future<void> _export(MarkdownStyleGuide guide) async {
    var destPath = await FilePicker.platform.saveFile(
      dialogTitle: "Export style guide",
      fileName: "${guide.name}.json",
      type: FileType.custom,
      allowedExtensions: ["json"],
    );
    if (destPath == null || !mounted) return;
    try {
      // A guide is never written out as a built-in, whatever it was forked
      // from -- toJson carries no such key, and fromJson reads none, so an
      // exported "Article" arrives as an ordinary guide of the reader's own
      // rather than as an undeletable fifth built-in.
      await File(destPath).writeAsString(
          const JsonEncoder.withIndent("  ").convert(guide.toJson()));
      if (mounted) {
        showSuccessSnackbar(context, "Exported style guide to $destPath");
      }
    } catch (exception) {
      if (mounted) {
        showErrorSnackbar(context, "Unable to export style guide: $exception");
      }
    }
  }

  /// _import reads a guide from a file into the library and selects it.
  ///
  /// A fresh id, like an imported theme preset: the id in the file is the
  /// exporting machine's, and reusing it would silently overwrite a guide of
  /// the same id already here.
  Future<void> _import(AreaEditorContext ctx) async {
    var res = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      dialogTitle: "Import style guide",
      type: FileType.custom,
      allowedExtensions: ["json"],
    );
    var srcPath = res?.files.first.path;
    if (srcPath == null || !mounted) return;
    try {
      var json = jsonDecode(await File(srcPath).readAsString());
      if (json is! Map) throw Exception("not a style guide");
      var guide = MarkdownStyleGuide.fromJson(Map<String, Object?>.from(json));
      var id = "guide-${DateTime.now().microsecondsSinceEpoch}";
      // copyWith drops builtIn as soon as the id changes, which is exactly
      // what an import wants.
      var saved = guide.copyWith(id: id);
      if (!mounted) return;
      ctx.setStyle((s) => s.copyWith(
            markdownSavedGuides: {...s.markdownSavedGuides, id: saved.toJson()},
            markdownGuideId: id,
            clearMarkdownCustomGuide: true,
          ));
      if (mounted) {
        showSuccessSnackbar(context, "Imported style guide \"${saved.name}\"");
      }
    } catch (exception) {
      if (mounted) {
        showErrorSnackbar(context, "Unable to import style guide: $exception");
      }
    }
  }

  /// _columnSpacing is one of the column box's four-way settings.
  ///
  /// The same control the rest of the theme editor uses for a padding, a
  /// margin, a border width or a set of corners -- one slider with a button
  /// to split it into four -- pointed at the style guide rather than at the
  /// area's own style, which is where a column's settings live.
  List<Widget> _columnSpacing(
    AreaEditorContext ctx,
    MarkdownStyleGuide guide,
    void Function(MarkdownStyleGuide Function(MarkdownStyleGuide)) edit, {
    required String key,
    required String name,
    required double max,
    required double single,
    required SideValues? sides,
    List<String> slotLabels = sideLabels,
    required ColumnRule Function(ColumnRule) Function(double) onSingle,
    required ColumnRule Function(ColumnRule) Function(SideValues?) onSides,
  }) =>
      ctx.spacing(
        key: key,
        name: name,
        max: max,
        single: single,
        sides: sides,
        slotLabels: slotLabels,
        onSingle: (v) =>
            edit((g) => g.copyWith(columns: onSingle(v)(g.columns))),
        updateSides: (f) => edit((g) {
          var next = f(sides, single);
          return g.copyWith(columns: onSides(next)(g.columns));
        }),
      );

  /// _cardSpacing is _columnSpacing pointed at the card rules instead.
  List<Widget> _cardSpacing(
    AreaEditorContext ctx,
    MarkdownStyleGuide guide,
    void Function(MarkdownStyleGuide Function(MarkdownStyleGuide)) edit, {
    required String key,
    required String name,
    required double max,
    required double single,
    required SideValues? sides,
    List<String> slotLabels = sideLabels,
    required CardRule Function(CardRule) Function(double) onSingle,
    required CardRule Function(CardRule) Function(SideValues?) onSides,
  }) =>
      ctx.spacing(
        key: key,
        name: name,
        max: max,
        single: single,
        sides: sides,
        slotLabels: slotLabels,
        onSingle: (v) => edit((g) => g.copyWith(cards: onSingle(v)(g.cards))),
        updateSides: (f) => edit((g) {
          var next = f(sides, single);
          return g.copyWith(cards: onSides(next)(g.cards));
        }),
      );

  /// _inkPick is the editor's own palette dropdown, bound to a guide colour.
  ///
  /// The same control every other area uses, which shows a swatch beside
  /// each slot. The plain text dropdown this replaces named colours without
  /// showing any of them, and offered a short list of roles rather than the
  /// palette the rest of the theme is built from.
  ///
  /// The built-in guides still use roles, which adapt to whatever theme they
  /// are read in. Picking here replaces that with a slot from this palette:
  /// a specific colour, chosen deliberately, which is what reaching for the
  /// picker means. It follows the palette when that is edited, because the
  /// slot is stored beside the colour.
  Widget _inkPick(AreaEditorContext ctx, String label, MarkdownInk current,
          ValueChanged<MarkdownInk> onChanged) =>
      ctx.colorPick(
        label,
        value: current.resolve(ctx.theme.markdownRoleColor,
            paletteColor: ctx.theme.markdownPaletteColor),
        valueIndex: current.paletteIndex,
        noneLabel: "Theme default",
        onChanged: (color, index) => onChanged(color == null
            ? MarkdownInk.inherit
            : MarkdownInk.literal(color, paletteIndex: index)),
      );

  List<Widget> _settingsFor(
    AreaEditorContext ctx,
    MarkdownStyleGuide guide,
    void Function(MarkdownStyleGuide Function(MarkdownStyleGuide)) edit,
  ) {
    List<Widget> ink(String label, MarkdownInk current,
            MarkdownStyleGuide Function(MarkdownStyleGuide, MarkdownInk) put) =>
        [
          _inkPick(ctx, label, current, (i) => edit((g) => put(g, i))),
        ];

    switch (element) {
      case _Element.text:
        return [
          ctx.note("Body text. Everything else is a share of this size."),
          ..._textControls(
              ctx, "body", guide.body, edit, (g, r) => g.copyWith(body: r),
              maxScale: 2.0),
          ctx.slider("md-body-line", guide.body.lineHeight ?? 1.4,
              label: (v) => "Line height: ${v.toStringAsFixed(2)}",
              min: 0.9,
              max: 3.0,
              divisions: 21,
              onCommit: (v) => edit(
                  (g) => g.copyWith(body: g.body.copyWith(lineHeight: v)))),
          ctx.slider("md-blockgap", guide.blockGap,
              label: (v) => "Space between paragraphs: ${v.round()}px",
              max: 48,
              divisions: 24,
              onCommit: (v) => edit((g) => g.copyWith(blockGap: v))),
          ctx.choice<MarkdownAlign>(
            "Alignment",
            value: guide.bodyAlign,
            options: MarkdownAlign.values,
            labelOf: (a) => switch (a) {
              MarkdownAlign.inherit => "Theme default",
              MarkdownAlign.center => "Center",
              MarkdownAlign.right => "Right",
              MarkdownAlign.left => "Left",
            },
            onChanged: (a) => edit((g) => g.copyWith(bodyAlign: a)),
          ),
          const SizedBox(height: 16),
          const Txt.M("Headings"),
          ctx.note("Each level, as a share of the body text size above."),
          for (var i = 0; i < 6; i++)
            ctx.slider("md-h${i + 1}", guide.headings[i].scale,
                label: (v) => "H${i + 1}: ${(v * 100).round()}%",
                min: 0.6,
                max: 3.0,
                divisions: 48,
                onCommit: (v) => edit((g) => g.copyWith(headings: [
                      for (var j = 0; j < 6; j++)
                        j == i
                            ? g.headings[j].copyWith(scale: v)
                            : g.headings[j]
                    ]))),
          ctx.note("Colour, font and weight apply to every level."),
          ..._textControls(
                  ctx,
                  "head",
                  guide.headings[0],
                  edit,
                  (g, r) => g.copyWith(headings: [
                        for (var h in g.headings)
                          h.copyWith(
                              ink: r.ink,
                              font: r.font,
                              bold: r.bold,
                              italic: r.italic)
                      ]))
              // The per-level sliders above already cover size.
              .skip(1),
        ];

      // Bold and italic were in the guide and saved with it from the start,
      // and were the two elements with nowhere to set them: a guide could
      // only get them by being written by hand.
      //
      // The Bold and Italic toggles inside each set are not the same thing
      // as the element itself. "**a**" is bold because it is written bold;
      // the toggle is whether that run is *also* set in the other, which is
      // how a guide sets bold text in italics as well.
      case _Element.emphasis:
        return [
          ctx.note("Text written **bold**."),
          ..._textControls(ctx, "strong", guide.strong, edit,
              (g, r) => g.copyWith(strong: r),
              maxScale: 2.0),
          const SizedBox(height: 16),
          const Txt.M("Italic"),
          ctx.note("Text written _italic_."),
          ..._textControls(ctx, "em", guide.emphasis, edit,
              (g, r) => g.copyWith(emphasis: r),
              maxScale: 2.0),
        ];

      case _Element.links:
        return [
          ..._textControls(
              ctx, "link", guide.link, edit, (g, r) => g.copyWith(link: r),
              maxScale: 2.0),
          ctx.toggle("Underline",
              value: guide.link.underline ?? false,
              onChanged: (v) =>
                  edit((g) => g.copyWith(link: g.link.copyWith(underline: v)))),
        ];

      case _Element.quotes:
        return [
          ..._textControls(
              ctx, "quote", guide.quote, edit, (g, r) => g.copyWith(quote: r),
              maxScale: 2.0),
          ...ink("Bar colour", guide.quoteBarInk,
              (g, i) => g.copyWith(quoteBarInk: i)),
          ctx.slider("md-quotebar", guide.quoteBarWidth,
              label: (v) => v == 0 ? "Bar: None" : "Bar width: ${v.round()}px",
              max: 12,
              divisions: 12,
              onCommit: (v) => edit((g) => g.copyWith(quoteBarWidth: v))),
          ...ink("Background", guide.quoteBackground,
              (g, i) => g.copyWith(quoteBackground: i)),
          ctx.slider("md-quotepad", guide.quotePadding,
              label: (v) => "Padding: ${v.round()}px",
              max: 40,
              divisions: 20,
              onCommit: (v) => edit((g) => g.copyWith(quotePadding: v))),
        ];

      case _Element.cards:
        return [
          ctx.note("A callout and a card are the same thing with a different "
              "amount filled in -- a title, some text, an icon and a button, "
              "any of which may be left out. Write them with the buttons in "
              "a post's Formatting & Content panel."),
          ...ink("Background", guide.cards.background,
              (g, i) => g.copyWith(cards: g.cards.copyWith(background: i))),
          ctx.slider("md-card-radius", guide.cards.radius,
              label: (v) =>
                  v == 0 ? "Corners: Square" : "Corners: ${v.round()}px",
              max: 48,
              divisions: 24,
              onCommit: (v) =>
                  edit((g) => g.copyWith(cards: g.cards.copyWith(radius: v)))),
          ctx.slider("md-card-border", guide.cards.borderWidth,
              label: (v) => v == 0 ? "Border: None" : "Border: ${v.round()}px",
              max: 12,
              divisions: 12,
              onCommit: (v) => edit(
                  (g) => g.copyWith(cards: g.cards.copyWith(borderWidth: v)))),
          ...ink("Border colour", guide.cards.borderInk,
              (g, i) => g.copyWith(cards: g.cards.copyWith(borderInk: i))),
          ..._cardSpacing(ctx, guide, edit,
              key: "md-card-pad",
              name: "Padding",
              max: 64,
              single: guide.cards.padding,
              sides: guide.cards.paddingSides,
              onSingle: (v) => (c) => c.copyWith(padding: v),
              onSides: (v) => (c) =>
                  c.copyWith(paddingSides: v, clearPaddingSides: v == null)),
          ctx.slider("md-card-gap", guide.cards.gap,
              label: (v) => "Space between cards: ${v.round()}px",
              max: 64,
              divisions: 32,
              onCommit: (v) =>
                  edit((g) => g.copyWith(cards: g.cards.copyWith(gap: v)))),
          const SizedBox(height: 16),
          const Txt.M("Icon"),
          ctx.slider("md-card-icon", guide.cards.iconSize,
              label: (v) => "Size: ${v.round()}px",
              min: 12,
              max: 96,
              divisions: 21,
              onCommit: (v) => edit(
                  (g) => g.copyWith(cards: g.cards.copyWith(iconSize: v)))),
          ...ink("Colour", guide.cards.iconInk,
              (g, i) => g.copyWith(cards: g.cards.copyWith(iconInk: i))),
          ...ink("Disc behind it", guide.cards.iconBackground,
              (g, i) => g.copyWith(cards: g.cards.copyWith(iconBackground: i))),
          ctx.note("Leave the disc on Theme default for a plain icon."),
          const SizedBox(height: 16),
          const Txt.M("Title"),
          ..._textControls(ctx, "card-title", guide.cards.title, edit,
              (g, r) => g.copyWith(cards: g.cards.copyWith(title: r)),
              maxScale: 2.0),
          const SizedBox(height: 16),
          const Txt.M("Text"),
          ..._textControls(ctx, "card-text", guide.cards.text, edit,
              (g, r) => g.copyWith(cards: g.cards.copyWith(text: r)),
              maxScale: 2.0),
          const SizedBox(height: 16),
          const Txt.M("Button"),
          ctx.choice<ButtonRole>(
            "Design",
            value: guide.cards.button,
            options: ButtonRole.values,
            labelOf: buttonRoleLabel,
            onChanged: (r) =>
                edit((g) => g.copyWith(cards: g.cards.copyWith(button: r))),
          ),
          ctx.note("One of the app's own five buttons, so a card's button "
              "matches every other button in the app -- its colours come "
              "from the Buttons theme area, not from here. Shown only on a "
              "card with a button: field."),
        ];

      case _Element.code:
        return [
          ..._textControls(
              ctx, "code", guide.code, edit, (g, r) => g.copyWith(code: r),
              maxScale: 2.0),
          // One colour for both, because they are one thing drawn twice: it
          // is the block's background and it is also what is painted behind
          // the letters, so the two agree exactly and the block reads as a
          // single shape rather than as text on a patch on a panel.
          ...ink("Background", guide.codeBackground,
              (g, i) => g.copyWith(codeBackground: i)),
          ctx.note("Used for fenced blocks and for `inline code`."),
          const SizedBox(height: 16),
          const Txt.M("Fenced blocks"),
          ctx.note("The three below apply to ``` blocks only. Inline code "
              "sits in a line of prose and has no room for any of them."),
          ctx.slider("md-code-pad", guide.codePadding ?? 8,
              label: (v) => "Padding: ${v.round()}px",
              min: 0,
              max: 48,
              divisions: 48,
              onCommit: (v) => edit((g) => g.copyWith(codePadding: v))),
          ctx.toggle("Line numbers",
              subtitle: "A numbered gutter down the left. It is a column of "
                  "its own, so copying the block still gives back the code "
                  "without the numbering",
              value: guide.codeLineNumbers,
              onChanged: (v) => edit((g) => g.copyWith(codeLineNumbers: v))),
          ctx.toggle("Syntax highlighting",
              subtitle: "Colours strings, numbers, comments and keywords. "
                  "The language written after the backticks never reaches "
                  "the renderer, so this is the part every language agrees "
                  "on rather than a grammar per language",
              value: guide.codeHighlight,
              onChanged: (v) => edit((g) => g.copyWith(codeHighlight: v))),
        ];

      case _Element.lists:
        return [
          ctx.note("The bullet of a - list and the numbers of a 1. list."),
          ..._textControls(ctx, "bullet", guide.listBullet, edit,
              (g, r) => g.copyWith(listBullet: r),
              maxScale: 2.0),
          ctx.slider("md-listgap", guide.listItemGap,
              label: (v) => "Space between items: ${v.round()}px",
              max: 32,
              divisions: 16,
              onCommit: (v) => edit((g) => g.copyWith(listItemGap: v))),
          ctx.slider("md-listindent", guide.listIndent,
              label: (v) => "Indent: ${v.round()}px",
              min: 8,
              max: 64,
              divisions: 14,
              onCommit: (v) => edit((g) => g.copyWith(listIndent: v))),
          const SizedBox(height: 16),
          const Txt.M("Check boxes"),
          ctx.note("A list item written `- [ ]` is a task, and one written "
              "`- [x]` is a task that is done. Both ends are set here, "
              "because which mark reads as done is a matter of taste -- a "
              "tick for work finished, a cross for something ruled out."),
          ctx.choice<MarkdownCheckMark>(
            "Done",
            value: guide.listCheckedMark,
            options: MarkdownCheckMark.values,
            labelOf: (m) => m.label,
            onChanged: (m) => edit((g) => g.copyWith(listCheckedMark: m)),
          ),
          ctx.choice<MarkdownCheckMark>(
            "Not done",
            value: guide.listUncheckedMark,
            options: MarkdownCheckMark.values,
            labelOf: (m) => m.label,
            onChanged: (m) => edit((g) => g.copyWith(listUncheckedMark: m)),
          ),
          ctx.slider("md-listchecksize", guide.listCheckSize,
              label: (v) => "Size: ${v.round()}px",
              min: 8,
              max: 48,
              divisions: 20,
              onCommit: (v) => edit((g) => g.copyWith(listCheckSize: v))),
          _inkPick(ctx, "Colour", guide.listCheckInk,
              (i) => edit((g) => g.copyWith(listCheckInk: i))),
          ctx.note("Theme default sets the box in whatever the bullet above "
              "is set in."),
        ];

      case _Element.tables:
        return [
          ctx.note("The header row."),
          ..._textControls(ctx, "thead", guide.tableHead, edit,
              (g, r) => g.copyWith(tableHead: r),
              maxScale: 2.0),
          const SizedBox(height: 16),
          const Txt.M("Body rows"),
          ..._textControls(ctx, "tbody", guide.tableBody, edit,
              (g, r) => g.copyWith(tableBody: r),
              maxScale: 2.0),
          const SizedBox(height: 16),
          const Txt.M("Rows"),
          ctx.note("The two things that make a table readable across as well "
              "as down."),
          ...ink("Header background", guide.tableHeadBackground,
              (g, i) => g.copyWith(tableHeadBackground: i)),
          ...ink("Alternating rows", guide.tableStripeInk,
              (g, i) => g.copyWith(tableStripeInk: i)),
          ctx.note("Every other body row, starting with the first."),
          const SizedBox(height: 16),
          const Txt.M("Cells and grid"),
          ctx.slider("md-tablepad", guide.tableCellPadding,
              label: (v) => "Cell padding: ${v.round()}px",
              max: 32,
              divisions: 16,
              onCommit: (v) => edit((g) => g.copyWith(tableCellPadding: v))),
          ctx.choice<MarkdownTableFit>(
            "Column widths",
            value: guide.tableFit,
            options: MarkdownTableFit.values,
            labelOf: (f) => f.label,
            onChanged: (f) => edit((g) => g.copyWith(tableFit: f)),
          ),
          ...ink("Line colour", guide.tableBorderInk,
              (g, i) => g.copyWith(tableBorderInk: i)),
          ctx.slider("md-tableborder", guide.tableBorderWidth,
              label: (v) =>
                  v == 0 ? "Lines: None" : "Line width: ${v.round()}px",
              max: 6,
              divisions: 6,
              onCommit: (v) => edit((g) => g.copyWith(tableBorderWidth: v))),
        ];

      case _Element.header:
        return [
          ctx.note("A banner across the top of a page, and the bar of links "
              "that usually sits in it. The writer says what goes in them; "
              "these say what they look like here."),
          const Txt.M("Banner"),
          ctx.slider("md-hdrheight", guide.header.height,
              label: (v) => "Tallest: ${v.round()}px",
              min: 80,
              max: 480,
              divisions: 20,
              onCommit: (v) => edit(
                  (g) => g.copyWith(header: g.header.copyWith(height: v)))),
          ctx.note("What a plain --header-- uses. A writer who asks for a "
              "height with --header[300]-- gets that instead."),
          ctx.slider("md-hdrpad", guide.header.padding,
              label: (v) => "Space inside: ${v.round()}px",
              max: 64,
              divisions: 32,
              onCommit: (v) => edit(
                  (g) => g.copyWith(header: g.header.copyWith(padding: v)))),
          ctx.slider("md-hdrradius", guide.header.radius,
              label: (v) => v == 0 ? "Corners: Square" : "Corners: ${v.round()}px",
              max: 48,
              divisions: 24,
              onCommit: (v) => edit(
                  (g) => g.copyWith(header: g.header.copyWith(radius: v)))),
          ctx.slider("md-hdrscrim", guide.header.scrim * 100,
              label: (v) => v == 0
                  ? "Picture: Untouched"
                  : "Picture dimmed by ${v.round()}%",
              max: 90,
              divisions: 18,
              onCommit: (v) => edit((g) =>
                  g.copyWith(header: g.header.copyWith(scrim: v / 100)))),
          ctx.note("A background is chosen for how it looks, rarely for how "
              "readable writing is on top of it -- and the writer cannot "
              "know what colours you read in. This is the answer to that."),
          const SizedBox(height: 16),
          const Txt.M("Navigation"),
          ctx.slider("md-navgap", guide.nav.gap,
              label: (v) => "Space between links: ${v.round()}px",
              max: 48,
              divisions: 24,
              onCommit: (v) =>
                  edit((g) => g.copyWith(nav: g.nav.copyWith(gap: v)))),
          ctx.slider("md-navpad", guide.nav.padding,
              label: (v) => "Space inside a link: ${v.round()}px",
              max: 32,
              divisions: 16,
              onCommit: (v) =>
                  edit((g) => g.copyWith(nav: g.nav.copyWith(padding: v)))),
          ctx.note("What gives a pill or a box its size. A plain bar is just "
              "words and ignores it."),
          ctx.slider("md-navradius", guide.nav.radius,
              label: (v) => v == 0 ? "Corners: Square" : "Corners: ${v.round()}px",
              max: 32,
              divisions: 16,
              onCommit: (v) =>
                  edit((g) => g.copyWith(nav: g.nav.copyWith(radius: v)))),
          ctx.slider("md-navborder", guide.nav.borderWidth,
              label: (v) => "Line: ${v.round()}px",
              max: 8,
              divisions: 8,
              onCommit: (v) => edit(
                  (g) => g.copyWith(nav: g.nav.copyWith(borderWidth: v)))),
          _inkPick(ctx, "Link colour", guide.nav.ink,
              (i) => edit((g) => g.copyWith(nav: g.nav.copyWith(ink: i)))),
        ];

      case _Element.gallery:
        return [
          ctx.note("A gallery is pictures side by side, each with the "
              "writing after it as its caption -- write one with the Gallery "
              "button in a post's Formatting & Content panel. How many "
              "across is set here rather than in the writing, so the same "
              "page reads well in a window of any width."),
          ctx.slider("md-gridcols", guide.grid.columns.toDouble(),
              label: (v) => v == 1
                  ? "One picture across"
                  : "${v.round()} pictures across",
              min: 1,
              max: 4,
              divisions: 3,
              onCommit: (v) => edit((g) =>
                  g.copyWith(grid: g.grid.copyWith(columns: v.round())))),
          ctx.note("What a plain --grid-- uses. A writer who asks for a "
              "width with --grid[3]-- gets that instead."),
          ctx.slider("md-gridgap", guide.grid.gap,
              label: (v) => "Space between pictures: ${v.round()}px",
              max: 64,
              divisions: 32,
              onCommit: (v) =>
                  edit((g) => g.copyWith(grid: g.grid.copyWith(gap: v)))),
          ctx.slider("md-gridstack", guide.grid.stackBelow,
              label: (v) => "Stack when a picture would be under ${v.round()}px",
              min: 80,
              max: 480,
              divisions: 20,
              onCommit: (v) => edit(
                  (g) => g.copyWith(grid: g.grid.copyWith(stackBelow: v)))),
          ctx.note("Four pictures across a narrow window are thumbnails in "
              "a row with a word of caption under each. Below this width "
              "they stack, which is what they would have been without the "
              "markup."),
        ];

      case _Element.columns:
        return [
          ctx.note("Markdown has no columns of its own, so these are Bison "
              "Relay's own -- write them with the buttons in a post's "
              "Formatting & Content panel. A reader whose app does not know "
              "them still sees the writing, in order, with the markers "
              "showing."),
          ctx.slider("md-colgap", guide.columns.gap,
              label: (v) => "Space between columns: ${v.round()}px",
              max: 64,
              divisions: 32,
              onCommit: (v) =>
                  edit((g) => g.copyWith(columns: g.columns.copyWith(gap: v)))),
          ctx.slider("md-colstack", guide.columns.stackBelow,
              label: (v) => "Stack when a column would be under ${v.round()}px",
              min: 80,
              max: 480,
              divisions: 20,
              onCommit: (v) => edit((g) =>
                  g.copyWith(columns: g.columns.copyWith(stackBelow: v)))),
          ctx.note("The same post is read in windows of every width. Below "
              "this, columns become one above another rather than three "
              "words wide."),
          const SizedBox(height: 16),
          const Txt.M("Divider"),
          ctx.note("A single line down the middle of each gap. Its own "
              "setting rather than part of the border below, because a rule "
              "between columns usually reads better at a different weight -- "
              "and most of the time there is no border at all."),
          ctx.slider("md-col-divider", guide.columns.dividerWidth,
              label: (v) => v == 0 ? "Divider: None" : "Width: ${v.round()}px",
              max: 12,
              divisions: 12,
              onCommit: (v) => edit((g) =>
                  g.copyWith(columns: g.columns.copyWith(dividerWidth: v)))),
          _inkPick(
              ctx,
              "Divider colour",
              guide.columns.dividerInk,
              (i) => edit((g) =>
                  g.copyWith(columns: g.columns.copyWith(dividerInk: i)))),
          const SizedBox(height: 16),
          const Txt.M("The run's box"),
          ctx.note("Around the whole run, not around each column: a border "
              "on every column is a row of boxes, and one round the outside "
              "is a block set in columns. Each can be split into four sides."),
          ..._columnSpacing(ctx, guide, edit,
              key: "md-col-pad",
              name: "Padding",
              max: 64,
              single: guide.columns.padding,
              sides: guide.columns.paddingSides,
              onSingle: (v) => (c) => c.copyWith(padding: v),
              onSides: (v) => (c) =>
                  c.copyWith(paddingSides: v, clearPaddingSides: v == null)),
          ..._columnSpacing(ctx, guide, edit,
              key: "md-col-margin",
              name: "Margin",
              max: 64,
              single: guide.columns.margin,
              sides: guide.columns.marginSides,
              onSingle: (v) => (c) => c.copyWith(margin: v),
              onSides: (v) => (c) =>
                  c.copyWith(marginSides: v, clearMarginSides: v == null)),
          ..._columnSpacing(ctx, guide, edit,
              key: "md-col-border",
              name: "Border width",
              max: 12,
              single: guide.columns.borderWidth,
              sides: guide.columns.borderWidthSides,
              onSingle: (v) => (c) => c.copyWith(borderWidth: v),
              onSides: (v) => (c) => c.copyWith(
                  borderWidthSides: v, clearBorderWidthSides: v == null)),
          _inkPick(
              ctx,
              "Border colour",
              guide.columns.borderInk,
              (i) => edit((g) =>
                  g.copyWith(columns: g.columns.copyWith(borderInk: i)))),
          ..._columnSpacing(ctx, guide, edit,
              key: "md-col-radius",
              name: "Corners",
              max: 48,
              single: guide.columns.radius,
              sides: guide.columns.radiusSides,
              slotLabels: cornerLabels,
              onSingle: (v) => (c) => c.copyWith(radius: v),
              onSides: (v) => (c) =>
                  c.copyWith(radiusSides: v, clearRadiusSides: v == null)),
          ctx.note("Rounded corners and a border with different widths per "
              "side cannot be drawn together, so a split border squares the "
              "corners off."),
        ];

      case _Element.rule:
        return [
          ...ink("Colour", guide.ruleInk, (g, i) => g.copyWith(ruleInk: i)),
          ctx.slider("md-rule", guide.ruleThickness,
              label: (v) => "Thickness: ${v.toStringAsFixed(1)}px",
              min: 0.5,
              max: 8,
              divisions: 15,
              onCommit: (v) => edit((g) => g.copyWith(ruleThickness: v))),
        ];

      case _Element.images:
        return [
          ctx.slider("md-img-width", guide.image.boundedWidth,
              label: (v) => "Width: ${v.round()}% of the column",
              min: 10,
              max: 100,
              divisions: 18,
              onCommit: (v) => edit(
                  (g) => g.copyWith(image: g.image.copyWith(widthPercent: v)))),
          ctx.slider("md-img-radius", guide.image.boundedRadius,
              label: (v) =>
                  v == 0 ? "Corners: Square" : "Corners: ${v.round()}px",
              max: 48,
              divisions: 24,
              onCommit: (v) => edit(
                  (g) => g.copyWith(image: g.image.copyWith(cornerRadius: v)))),
          ctx.slider("md-img-border", guide.image.boundedBorder,
              label: (v) => v == 0 ? "Border: None" : "Border: ${v.round()}px",
              max: 8,
              divisions: 8,
              onCommit: (v) => edit(
                  (g) => g.copyWith(image: g.image.copyWith(borderWidth: v)))),
          ...ink("Border colour", guide.image.borderInk,
              (g, i) => g.copyWith(image: g.image.copyWith(borderInk: i))),
          ctx.slider("md-img-gap", guide.image.gap,
              label: (v) => "Space above and below: ${v.round()}px",
              max: 48,
              divisions: 24,
              onCommit: (v) =>
                  edit((g) => g.copyWith(image: g.image.copyWith(gap: v)))),
          ctx.choice<MarkdownAlign>(
            "Alignment",
            value: guide.image.align == MarkdownAlign.inherit
                ? MarkdownAlign.left
                : guide.image.align,
            options: const [
              MarkdownAlign.left,
              MarkdownAlign.center,
              MarkdownAlign.right
            ],
            labelOf: (a) => switch (a) {
              MarkdownAlign.center => "Center",
              MarkdownAlign.right => "Right",
              _ => "Left",
            },
            onChanged: (a) =>
                edit((g) => g.copyWith(image: g.image.copyWith(align: a))),
          ),
        ];
    }
  }
}

/// _MarkdownPreview renders the sample in the chosen guide.
///
/// The whole reason this page exists before an editor for making guides
/// does: whether the vocabulary is the right one is a question you answer by
/// looking at it, not by reading a list of properties.
class _MarkdownPreview extends StatelessWidget {
  /// element decides what the sample contains.
  ///
  /// A sample showing everything at once means the part being adjusted is
  /// somewhere in the middle of it, and a slider's effect has to be hunted
  /// for. Showing the element being tuned -- with a line of body text around
  /// it for scale, since almost every setting is relative to that -- makes
  /// the change the obvious thing on screen.
  final _Element element;

  const _MarkdownPreview({required this.element});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surfaceColor(SurfaceColor.surfaceContainerLow),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colors.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Txt.S("Preview", color: TextColor.onSurfaceVariant),
        const SizedBox(height: 8),
        // Keyed by the guide so switching rebuilds rather than reusing the
        // element tree with a stale stylesheet.
        // No guide passed: the preview shows what this theme renders,
        // which is the reader's own guide once they have edited one. Naming
        // a built-in here is what made every edit look like it did nothing.
        MarkdownArea(_sampleFor(element), false, key: ValueKey(element)),
      ]),
    );
  }
}
