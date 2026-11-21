import 'package:flutter/material.dart';

import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/book_details.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_estimate.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/responsive_layout.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_dialogs.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart'
    show CanvasStateNote;
import 'package:bruig/plugin_system/canvas/ui/timeline/canvas_strip.dart';
import 'package:bruig/theming_system/theme_manager.dart';

// canvas_settings_panel.dart is the canvas's own settings, on the line the
// settings band opens under itself: its kind and shape, its pages, a
// book's details, how its sound is written out, and the size it would
// publish at.

/// _customRate is the Rate list's Custom entry. Not a rate, so it cannot
/// collide: real rates are at least one, and zero names the rate set.
const int _customRate = -1;

/// CanvasSettingsPanel is the canvas's own settings: shape, export width and
/// what publishing will cost, shown under the band while the Canvas
/// settings button is pressed.
class CanvasSettingsPanel extends StatefulWidget {
  final CanvasController controller;
  const CanvasSettingsPanel({required this.controller, super.key});

  @override
  State<CanvasSettingsPanel> createState() => _CanvasSettingsPanelState();
}

class _CanvasSettingsPanelState extends State<CanvasSettingsPanel> {
  CanvasController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => CanvasSettingsStrip(
      groups: (context) => _canvasGroups(context, ThemeNotifier.of(context)));

  /// _estimateGroup is what publishing this canvas will cost, beside the
  /// ratio and width that decide it. An estimate, and it says so: rendering
  /// on every edit would be too slow. See estimateStillBytes.
  Widget _estimateGroup(ThemeNotifier theme, CanvasDocument document) {
    var spec = document.estimate;
    // The formats that mean anything for this canvas: a GIF of a still is a
    // still, and a PNG of an animation is one frame of it.
    var offered = [
      for (var format in EstimateAs.values)
        if (format == EstimateAs.audio || format.moving == document.isAnimated)
          format,
    ];
    if (!offered.contains(spec.format)) {
      spec = spec.copyWith(format: offered.first);
    }

    var bytes = estimateBytes(document, spec);
    var behind = document.lastAnimatedFrame >= document.frames;

    void set(CanvasEstimate next) =>
        controller.apply(document.copyWith(estimate: next));

    return CanvasControlGroup(label: "Estimated size", children: [
      Padding(
        padding: const EdgeInsets.only(right: 4),
        child: SizedBox(
          height: controlHeight,
          child: Row(children: [
            Text(
              formatBytes(bytes),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colors.onSurface),
            ),
            if (behind) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: "There are keyframes past the end of the timeline. "
                    "Raise the frame count to reach them.",
                // error, not tertiary: tertiary is a panel background,
                // near-black in the dark theme.
                child: Icon(Icons.warning_amber_rounded,
                    size: 14, color: theme.colors.error),
              ),
            ],
          ]),
        ),
      ),
      // A canvas is four hundred kilobytes as a PNG and forty as a JPEG.
      CanvasDropdown<EstimateAs>(
        key: const ValueKey("estimateAs"),
        label: "As a",
        value: spec.format,
        width: 118,
        options: [for (var format in offered) (format, format.label)],
        onChanged: (v) => set(spec.copyWith(format: v)),
      ),
      if (spec.format.lossy)
        CanvasNumberField(
          key: const ValueKey("estimateQuality"),
          label: "Quality",
          value: spec.quality.toDouble(),
          min: 1,
          max: 100,
          decimals: 0,
          width: 56,
          onChanged: (v) {
            controller.beginInteraction();
            controller.apply(
                document.copyWith(estimate: spec.copyWith(quality: v.round())),
                transient: true);
          },
          onCommit: controller.endInteraction,
        ),
      CanvasHint("An estimate rather than a measurement: encoding the real "
          "thing on every edit would make the editor unusable. "
          "${spec.format.description}."
          "${spec.format.lossy ? " Quality is what it is squeezed to — "
              "everything above about 90 costs a great deal and shows almost "
              "nothing." : ""}"),
    ]);
  }

  /// _bookGroup is the book's details (BookDetails): what each EPUB tells a
  /// store and a reader, and each edition's ISBN. Set before the first
  /// upload: Apple takes an ISBN with no other.
  ///
  /// No CanvasLineBreak in it: this panel lays its groups along a strip
  /// with no width of its own, where a break is infinitely wide.
  Widget _bookGroup(CanvasDocument document) {
    var book = document.pages.book;
    // The details now, not as built: the panel is not rebuilt while a field
    // is typed in.
    void typed(BookDetails Function(BookDetails) change) {
      controller.beginInteraction();
      var now = controller.document;
      controller.apply(
          now.copyWith(pages: now.pages.copyWith(book: change(now.pages.book))),
          transient: true);
    }

    Widget field(String key, String label, String value,
            BookDetails Function(BookDetails, String) set,
            {double width = 160, int lines = 1, String hint = ""}) =>
        CanvasTextField(
          key: ValueKey("book$key"),
          label: label,
          value: value,
          width: width,
          maxLines: lines,
          hint: hint,
          onChanged: (v) => typed((b) => set(b, v)),
          onCommit: controller.endInteraction,
        );

    var problems = [
      for (var e in BookEdition.values)
        if (isbnProblem(book.isbnOf(e)) case var p?) "${e.label}: $p",
    ];
    var missing = [
      if (book.author.isEmpty) "an author",
      if (book.description.isEmpty) "a description",
    ];
    // Said where it is seen, not behind the "?": a wrong ISBN uploaded to
    // Apple cannot be changed. A fixed width, as the panel's strip has none.
    var notes = [
      if (problems.isNotEmpty) "${problems.join(". ")}.",
      if (missing.isNotEmpty) "Stores ask for ${missing.join(" and ")}.",
    ];
    return CanvasControlGroup(
      key: const ValueKey("bookDetails"),
      label: "Book details",
      below: notes.isEmpty
          ? null
          : SizedBox(
              width: 380,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (var n in notes) CanvasStateNote(n),
              ]),
            ),
      help: "What every EPUB of this book tells a store and a reader: who "
          "wrote it, what it is about, its series, and the ISBN of each "
          "edition. The plain and interactive ebooks and the printed book "
          "are separate editions, each with its own ISBN where it has one. "
          "Apple Books takes an ISBN only with a book's first upload, never "
          "later.",
      children: [
        field("Subtitle", "Subtitle", book.subtitle,
            (b, v) => b.copyWith(subtitle: v),
            width: 220),
        field("Author", "Author", book.author, (b, v) => b.copyWith(author: v),
            hint: "Several: commas between"),
        field("Publisher", "Publisher", book.publisher,
            (b, v) => b.copyWith(publisher: v)),
        field("Language", "Language", book.language,
            (b, v) => b.copyWith(language: v.trim()),
            width: 70, hint: "en"),
        field("Published", "Published", book.published,
            (b, v) => b.copyWith(published: v.trim()),
            width: 100, hint: "2026-12-01"),
        field("Description", "Description", book.description,
            (b, v) => b.copyWith(description: v),
            width: 380, lines: 4, hint: "The blurb a store shows"),
        field("Subjects", "Subjects", book.subjects,
            (b, v) => b.copyWith(subjects: v),
            width: 220, hint: "Comics, Cryptocurrency, History"),
        field("Series", "Series", book.series, (b, v) => b.copyWith(series: v)),
        CanvasNumberField(
          key: const ValueKey("bookSeriesNumber"),
          label: "Number",
          value: book.seriesNumber.toDouble(),
          min: 0,
          max: 9999,
          decimals: 0,
          width: 58,
          onChanged: (v) => typed((b) => b.copyWith(seriesNumber: v.round())),
          onCommit: controller.endInteraction,
        ),
        field("Rights", "Rights", book.rights, (b, v) => b.copyWith(rights: v),
            width: 220, hint: "© 2026 Your name"),
        for (var e in BookEdition.values)
          field("Isbn${e.name}", "ISBN, ${e.label.toLowerCase()}",
              book.isbnOf(e), (b, v) => b.withIsbn(e, v),
              width: 150, hint: "978-…"),
      ],
    );
  }

  /// _pageValuesGroup is the shown page's own values (CanvasScene.values),
  /// which a text on it -- usually one on the master canvas -- shows with
  /// a {value:Name} field: the chapter a running head names, say.
  Widget _pageValuesGroup(CanvasDocument document) {
    var at = document.at;
    var values = document.scene.values.entries.toList();
    void put(List<MapEntry<String, String>> next, {bool transient = false}) {
      var now = controller.document;
      controller.apply(
          now.withScene(
              at,
              now.scene.copyWith(values: {
                for (var MapEntry(:key, :value) in next) key: value,
              })),
          transient: transient);
    }

    void typed(int i, {String? name, String? value}) {
      controller.beginInteraction();
      var list = controller.document.scene.values.entries.toList();
      if (i >= list.length) return;
      list[i] = MapEntry(name ?? list[i].key, value ?? list[i].value);
      put(list, transient: true);
    }

    return CanvasControlGroup(label: "This page", children: [
      for (var (i, MapEntry(:key, :value)) in values.indexed) ...[
        CanvasTextField(
          key: ValueKey("pageValueName$i"),
          label: "Name",
          value: key,
          width: 90,
          onChanged: (v) => typed(i, name: v),
          onCommit: controller.endInteraction,
        ),
        CanvasTextField(
          key: ValueKey("pageValue$i"),
          label: "Value",
          value: value,
          width: 120,
          onChanged: (v) => typed(i, value: v),
          onCommit: controller.endInteraction,
        ),
        CanvasIconButton(
          key: ValueKey("pageValueRemove$i"),
          icon: Icons.close,
          tooltip: "Remove this value",
          // The values now, not as built: the panel is not rebuilt while
          // a name is typed.
          onPressed: () => put(
              controller.document.scene.values.entries.toList()..removeAt(i)),
        ),
      ],
      CanvasTextButton(
        key: const ValueKey("pageValueAdd"),
        label: "Add value",
        icon: Icons.add,
        onPressed: () {
          var values = controller.document.scene.values.entries.toList();
          var taken = {for (var v in values) v.key};
          var name = "Value";
          for (var n = 2; taken.contains(name); n++) {
            name = "Value $n";
          }
          put([...values, MapEntry(name, "")]);
        },
      ),
      const CanvasHint("A text shows one with {value:Name}, Name being the "
          "value's name: on the master canvas, every page shows its own."),
    ]);
  }

  /// _audioGroup is the document's sound as a production: its destination
  /// preset, how it is written, and how loud. Tempo, metre and quantise are
  /// on the timeline's control bar.
  Widget _audioGroup(CanvasDocument document) {
    var audio = document.audio;
    var export = audio.export;
    var mix = document.masterMix;
    void write(AudioSettings next, {MasterMix? master}) =>
        controller.apply(document.copyWith(audio: next, masterMix: master));
    void writeExport(AudioOptions next) => write(audio.copyWith(export: next));
    var preset = AudioPreset.values
        .where((p) =>
            p.options == export &&
            mix.normalise &&
            p.target == mix.target &&
            p.ceilingDb == mix.ceilingDb)
        .firstOrNull;
    var fixed = export.format.fixedRate;
    return CanvasControlGroup(label: "Audio", children: [
      CanvasDropdown<String>(
        key: const ValueKey("audioPreset"),
        label: "For",
        value: preset?.name ?? "",
        width: 150,
        options: [
          if (preset == null) ("", "Custom"),
          for (var p in AudioPreset.values) (p.name, p.label),
        ],
        onChanged: (name) {
          var p = AudioPreset.values.where((p) => p.name == name).firstOrNull;
          if (p == null) return;
          write(audio.copyWith(export: p.options),
              master: mix.copyWith(
                  target: p.target,
                  ceilingDb: p.ceilingDb,
                  normalise: true,
                  limiter: true));
        },
      ),
      // What it is mixed for. Surround is heard here folded down to two
      // speakers, and written whole wherever the file can carry it.
      CanvasDropdown<SpeakerLayout>(
        key: const ValueKey("audioSpeakers"),
        label: "Speakers",
        value: audio.speakers,
        width: 110,
        options: [for (var l in SpeakerLayout.values) (l, l.label)],
        onChanged: (l) => write(audio.copyWith(speakers: l)),
      ),
      CanvasDropdown<AudioFormat>(
        key: const ValueKey("audioFormat"),
        label: "Format",
        value: export.format,
        width: 104,
        options: [for (var f in AudioFormat.values) (f, f.label)],
        onChanged: (f) => writeExport(export.copyWith(format: f)),
      ),
      if (fixed == null)
        CanvasDropdown<int>(
          key: const ValueKey("audioRate"),
          label: "Rate",
          value: export.sampleRate,
          width: 86,
          options: [
            for (var r in audioRates)
              (r, "${(r / 1000).toStringAsFixed(1)} kHz")
          ],
          onChanged: (r) => writeExport(export.copyWith(sampleRate: r)),
        ),
      export.format.lossless
          ? CanvasDropdown<int>(
              key: const ValueKey("audioDepth"),
              label: "Depth",
              value: export.bitDepth,
              width: 76,
              options: [for (var d in audioDepths) (d, "$d-bit")],
              onChanged: (d) => writeExport(export.copyWith(bitDepth: d)),
            )
          : CanvasDropdown<int>(
              key: const ValueKey("audioBitrate"),
              label: "Bitrate",
              value: export.kbps,
              width: 90,
              options: [for (var k in audioBitrates) (k, "$k kbps")],
              onChanged: (k) => writeExport(export.copyWith(kbps: k)),
            ),
      CanvasToggle(
        key: const ValueKey("audioToTarget"),
        label: "To a loudness",
        value: mix.normalise,
        onChanged: (v) => controller
            .apply(document.copyWith(masterMix: mix.copyWith(normalise: v))),
      ),
      if (mix.normalise)
        CanvasDropdown<double>(
          key: const ValueKey("audioTarget"),
          label: "Of",
          value: mix.target,
          width: 104,
          options: [
            for (var (t, _) in loudnessOptions(mix.target))
              (t, "${t.round()} LUFS"),
          ],
          onChanged: (t) => controller
              .apply(document.copyWith(masterMix: mix.copyWith(target: t))),
        ),
      CanvasHint("Where this is going, and how its sound is written when it "
          "is published — every publish starts from these. ${preset?.note ?? "Choose a destination to set the format and the loudness at once, or set each yourself."} "
          "The loudness is measured over the whole mix and then limited, "
          "so a quiet piece is brought up and a loud one down."
          "${audio.speakers.isSurround ? " Mixed for ${audio.speakers.label}: heard here folded down to two speakers, and published with every speaker in WAV, FLAC, AAC, Opus and video — an MP3 carries the fold-down." : ""}"),
    ]);
  }

  List<Widget> _canvasGroups(BuildContext context, ThemeNotifier theme) {
    var document = controller.document;

    /// write is an immediate change (a dropdown), its own undo step.
    void write(CanvasDocument next) => controller.apply(next);

    /// edit is a continuous change, typed or dragged, opening the undo step
    /// itself: beginInteraction is idempotent, and a transient edit outside
    /// an interaction is silently never pushed onto the history.
    void edit(CanvasDocument next) {
      controller.beginInteraction();
      controller.apply(next, transient: true);
    }

    return [
      CanvasControlGroup(label: "Canvas", children: [
        // What this document is for, first: shape, rate, scene joins and
        // names follow from it. See CanvasKind.
        CanvasDropdown<CanvasKind>(
          key: const ValueKey("canvasKind"),
          label: "Type",
          value: document.kind,
          width: 104,
          options: [for (var k in CanvasKind.values) (k, k.label)],
          onChanged: controller.setKind,
        ),
        const CanvasHint(
            "Scenes are canvases played one after another — a video, "
            "an animation, a presentation, a set of images. Pages are the "
            "leaves of a document: they take covers, page numbers and facing "
            "pages, and one gives way to the next with a page turn. Choosing "
            "Pages puts a new canvas on A4 at one frame a second; a canvas "
            "already on paper is left as it is."),
        // Sound starts with no picture (Ratio "None") and can be given one;
        // everything else always has one.
        if (document.kind.isAudio)
          CanvasDropdown<String>(
            key: const ValueKey("canvasRatio"),
            label: "Ratio",
            value: document.hasCanvas ? document.size.ratio.name : "",
            width: 116,
            options: [
              ("", "None"),
              for (var r in CanvasRatio.values) (r.name, r.label),
            ],
            onChanged: (name) {
              var r = CanvasRatio.values.where((r) => r.name == name);
              controller.beginInteraction();
              controller.setHasCanvas(r.isNotEmpty);
              if (r.isNotEmpty && r.first != document.size.ratio) {
                controller.setShape(document.size.copyWith(ratio: r.first));
              }
              controller.endInteraction();
            },
          )
        else
          CanvasDropdown<CanvasRatio>(
            key: const ValueKey("canvasRatio"),
            label: "Ratio",
            value: document.size.ratio,
            width: 116,
            options: [for (var r in CanvasRatio.values) (r, r.label)],
            // Shapes this document is laid out for are marked, each with a
            // cross to give it up; clicking one starts a layout for it. See
            // CanvasDocument.targets.
            marked: {
              for (var r in CanvasRatio.values)
                if (document.targets.contains(r.name)) r,
            },
            removeTip: (r) => r.name == shapeKey(document.size)
                ? "Lay ${r.label} out again from another shape"
                : "Stop laying out for ${r.label}",
            onRemove: (r) {
              // The shape on screen cannot be dropped: its cross lays it out
              // again from another.
              if (r.name != shapeKey(document.size)) {
                controller.forgetShape(r.name);
                return;
              }
              var other = document.targets
                  .where((t) => t != shapeKey(document.size))
                  .firstOrNull;
              if (other != null) controller.resetShape(other);
            },
            onChanged: (v) {
              // A shape change brings its own frame rate, but only where none
              // was chosen (a typed 30 is kept).
              var rate = document.frameRate;
              if (rate == defaultRateFor(document.size.ratio, document.kind)) {
                // Through defaultRateFor, not the shape alone: pages on A4
                // turn, so must not drop to one frame a second.
                rate = defaultRateFor(v, document.kind);
              }
              // Through the controller, which keeps the layout of the shape
              // left and takes out the one opened (CanvasController.setShape).
              controller.setShape(document.size.copyWith(ratio: v),
                  frameRate: rate);
            },
          ),
        // The named sizes of this shape beside a box for any other: 1920
        // across is 1080p at 16:9 and nothing on A4. With no canvas there is
        // no size or frame count: the timeline goes by the tempo.
        if (document.hasCanvas) ...[
          if (sizePresetsFor(document.size.ratio) case var named
              when named.isNotEmpty)
            CanvasDropdown<int>(
              key: const ValueKey("canvasWidthPreset"),
              label: "Size",
              value: named.any((p) => p.width == document.size.exportWidth)
                  ? document.size.exportWidth
                  : 0,
              width: 168,
              options: [
                // "Custom" when the width is not one of the named ones.
                if (!named.any((p) => p.width == document.size.exportWidth))
                  (0, "Custom"),
                for (var preset in named)
                  (preset.width, "${preset.label} · ${preset.width}"),
              ],
              onChanged: (v) {
                if (v == 0) return;
                write(document.copyWith(
                    size: document.size.copyWith(exportWidth: v)));
              },
            ),
          CanvasNumberField(
            key: const ValueKey("canvasWidth"),
            label: "Max width",
            value: document.size.exportWidth.toDouble(),
            min: minCanvasWidth.toDouble(),
            max: maxCanvasWidth.toDouble(),
            width: 66,
            suffix: "px",
            onChanged: (v) => edit(document.copyWith(
                size: document.size.copyWith(exportWidth: v.round()))),
            onCommit: controller.endInteraction,
          ),
          // Frames a second, beside the shape since it follows it: a page is
          // one a second, a screen twenty-four.
          CanvasDropdown<int>(
            key: const ValueKey("canvasRatePreset"),
            label: "Rate",
            value: canvasFrameRates.contains(document.frameRate)
                ? document.frameRate
                : 0,
            width: 118,
            options: [
              // A typed rate, at the top and only while set: there is never
              // more than one custom rate to keep.
              if (!canvasFrameRates.contains(document.frameRate))
                (0, "Custom · ${document.frameRate}"),
              for (var rate in canvasFrameRates)
                (rate, rate == 1 ? "Still · 1" : "$rate fps"),
              (_customRate, "Custom…"),
            ],
            onChanged: (v) async {
              // The rate already set: writing it would be an empty undo step.
              if (v == 0) return;
              if (v != _customRate) {
                write(document.copyWith(frameRate: v));
                return;
              }
              var typed =
                  await askForFrameRate(context, initial: document.frameRate);
              if (typed == null) return;
              // The document now: the one captured when the list was built is
              // out of date once the dialog closes.
              write(controller.document.copyWith(frameRate: typed));
            },
          ),
          if (document.size.ratio == CanvasRatio.custom)
            CanvasNumberField(
              key: const ValueKey("canvasAspect"),
              label: "Aspect",
              value: document.size.customRatio,
              min: 0.05,
              max: 20,
              decimals: 3,
              width: 58,
              onChanged: (v) => edit(document.copyWith(
                  size: document.size.copyWith(customRatio: v))),
              onCommit: controller.endInteraction,
            ),
          Padding(
            // No nudge: on the band, captions sit beside their controls.
            padding: const EdgeInsets.only(left: 2),
            child: SizedBox(
              height: controlHeight,
              child: Center(
                child: Text(
                  // The file's size: the larger, where published larger.
                  "${document.size.exportWidth} × ${document.size.exportHeight}",
                  style: TextStyle(
                      fontSize: 10, color: theme.colors.onSurfaceVariant),
                ),
              ),
            ),
          ),
        ],
      ]),
      // The settings only a document of pages reads.
      if (document.isPages)
        CanvasControlGroup(label: "Pages", children: [
          CanvasToggle(
            key: const ValueKey("pagesFacing"),
            label: "Facing pages",
            value: document.pages.facing,
            onChanged: (v) => write(
                document.copyWith(pages: document.pages.copyWith(facing: v))),
          ),
          CanvasNumberField(
            key: const ValueKey("pagesStartAt"),
            label: "Numbered from",
            value: document.pages.startAt.toDouble(),
            min: 0,
            max: 9999,
            decimals: 0,
            width: 74,
            onChanged: (v) => edit(document.copyWith(
                pages: document.pages.copyWith(startAt: v.round()))),
            onCommit: controller.endInteraction,
          ),
          CanvasToggle(
            key: const ValueKey("pagesCountCovers"),
            label: "Covers count",
            value: document.pages.countCovers,
            onChanged: (v) => write(document.copyWith(
                pages: document.pages.copyWith(countCovers: v))),
          ),
          CanvasToggle(
            key: const ValueKey("pagesMasterOnCovers"),
            label: "Master on covers",
            value: document.pages.masterOnCovers,
            onChanged: (v) => write(document.copyWith(
                pages: document.pages.copyWith(masterOnCovers: v))),
          ),
          // Only where covers are counted, so a cover has a number to print.
          if (document.pages.countCovers)
            CanvasToggle(
              key: const ValueKey("pagesNumbersOnCovers"),
              label: "Number on covers",
              value: document.pages.numbersOnCovers,
              onChanged: (v) => write(document.copyWith(
                  pages: document.pages.copyWith(numbersOnCovers: v))),
            ),
          CanvasHint(
              "Facing pages draws the page beside the one you are working "
              "on, so a spread is seen as it is read — every page is still "
              "one page. A page number is a text with the Page number field "
              "in it (or a counter set to show the page number): put one on "
              "the master canvas and every page wears it. Covers are left "
              "out of the count unless you say otherwise"
              "${document.pages.countCovers ? "" : ", and are never "
                  "paired with another page"}, and show the master's "
              "backdrop without its elements unless Master on covers is on."),
        ]),
      // What a store and a reader are told about the book.
      if (document.isPages) _bookGroup(document),
      // The shown page's own values, which a text's {value:Name} reads.
      if (document.isPages && !document.editingMaster)
        _pageValuesGroup(document),
      _audioGroup(document),
      // What changing the size does. On, the size is a resolution: the
      // design is drawn in its own space and scaled on the way out, so 4K is
      // the same picture with more pixels. Off, it is a page: the design
      // keeps its scale and gains room round it.
      if (document.hasCanvas)
        CanvasControlGroup(label: "Scaling", children: [
          CanvasToggle(
            key: const ValueKey("canvasScalesDesign"),
            label: "Size scales the design",
            value: document.size.scalesDesign,
            onChanged: (v) => write(document.copyWith(
                size: document.size.copyWith(scalesDesign: v))),
          ),
          const CanvasHint(
              "On, the size is a resolution: the design is drawn in its own "
              "space and scaled on the way out, so publishing larger gives the "
              "same picture with more pixels in it. Off, the size is a page: "
              "the design keeps its scale and there is more room around it."),
        ]),
      // Last: what all of the above comes to.
      _estimateGroup(theme, document),
    ];
  }
}
