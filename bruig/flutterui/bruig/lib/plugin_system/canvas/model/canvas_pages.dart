import 'package:bruig/plugin_system/canvas/model/canvas_element.dart'
    show jsonBool, jsonInt;

// canvas_pages.dart is which sort of document a canvas is, and the settings
// that only mean something to a document of pages: leaves side by side rather
// than moments in time, with covers, numbers and a page turn between them.

/// CanvasKind is which sort of document this is. Scenes is the default.
enum CanvasKind {
  scenes(
      "Scenes",
      "Canvases played one after another: a video, an animation, "
          "a presentation, a set of images"),
  pages(
      "Pages",
      "Leaves of a document: covers, page numbers, facing pages "
          "and a page turn between them"),
  audio(
      "Audio",
      "A piece of sound: a song, a podcast, a soundtrack, made on the "
          "timeline and the mixer");

  final String label;
  final String description;
  const CanvasKind(this.label, this.description);

  bool get isPages => this == pages;

  /// isAudio is whether this is an audio document: its timeline and mixer,
  /// with the canvas put away.
  bool get isAudio => this == audio;

  /// one and many are what a canvas of this kind is called. Every label that
  /// names one should use these.
  String get one => switch (this) {
        pages => "page",
        audio => "section",
        scenes => "scene",
      };
  String get many => "${one}s";

  /// oneCap and manyCap are capitalised, for the start of a sentence.
  String get oneCap => one[0].toUpperCase() + one.substring(1);
  String get manyCap => many[0].toUpperCase() + many.substring(1);

  static CanvasKind fromName(String? name) =>
      values.firstWhere((k) => k.name == name, orElse: () => scenes);
}

/// PageCover marks a page that is not part of the body. A cover is an
/// ordinary canvas; marking it means it is not numbered (unless
/// PagesSpec.countCovers), is never paired with another page, and is what an
/// exporter puts on the outside.
enum PageCover {
  none("Not a cover"),
  front("Front cover"),
  back("Back cover");

  final String label;
  const PageCover(this.label);

  bool get isCover => this != none;

  static PageCover fromName(String? name) =>
      values.firstWhere((c) => c.name == name, orElse: () => none);
}

/// PagesSpec is the settings that only mean something to a document of pages.
class PagesSpec {
  /// facing is whether the page being worked on is shown beside the one it
  /// faces. A way of looking only: every page stays one canvas of the page
  /// size, which is also what EPUB and PDF export want.
  final bool facing;

  /// startAt is the number the first numbered page carries.
  final int startAt;

  /// countCovers is whether a cover takes a number of its own, as a magazine
  /// is paginated. Off by default.
  final bool countCovers;

  /// numbersOnCovers is whether a number is *drawn* on a cover. Separate from
  /// [countCovers]: a magazine counts its cover as page one without printing
  /// the 1.
  final bool numbersOnCovers;

  const PagesSpec({
    this.facing = false,
    this.startAt = 1,
    this.countCovers = false,
    this.numbersOnCovers = false,
  });

  PagesSpec copyWith({
    bool? facing,
    int? startAt,
    bool? countCovers,
    bool? numbersOnCovers,
  }) =>
      PagesSpec(
        facing: facing ?? this.facing,
        startAt: startAt ?? this.startAt,
        countCovers: countCovers ?? this.countCovers,
        numbersOnCovers: numbersOnCovers ?? this.numbersOnCovers,
      );

  /// isDefault is whether every setting is at its default, so nothing need
  /// be saved.
  bool get isDefault =>
      !facing && startAt == 1 && !countCovers && !numbersOnCovers;

  Map<String, dynamic> toJson() => {
        if (facing) "facing": true,
        if (startAt != 1) "startAt": startAt,
        if (countCovers) "countCovers": true,
        if (numbersOnCovers) "numbersOnCovers": true,
      };

  factory PagesSpec.fromJson(Map<String, dynamic> json) => PagesSpec(
        facing: jsonBool(json["facing"], false),
        startAt: jsonInt(json["startAt"], 1),
        countCovers: jsonBool(json["countCovers"], false),
        numbersOnCovers: jsonBool(json["numbersOnCovers"], false),
      );
}

/// pageNumberFor is the number printed on the page at [index], or null for a
/// page that carries none.
///
/// Worked out rather than stored, so it follows every add, remove and
/// reorder. [covers] is one entry per page, in order.
int? pageNumberFor(List<PageCover> covers, int index, PagesSpec spec) {
  if (index < 0 || index >= covers.length) return null;
  if (covers[index].isCover && !spec.numbersOnCovers) return null;
  var number = spec.startAt;
  for (var at = 0; at < index; at++) {
    if (covers[at].isCover && !spec.countCovers) continue;
    number++;
  }
  return number;
}

/// facingPage is the page shown beside the one at [index], or null where it is
/// shown alone.
///
/// The first leaf stands alone, whether it is a front cover or page one, and
/// everything after it pairs two at a time. Covers are not counted
/// separately, or a cover and page one would both stand alone. A pair
/// containing a cover is broken, both standing alone.
int? facingPage(List<PageCover> covers, int index) {
  if (index <= 0 || index >= covers.length) return null;
  if (covers[index].isCover) return null;
  var beside = index.isOdd ? index + 1 : index - 1;
  if (beside <= 0 || beside >= covers.length) return null;
  if (covers[beside].isCover) return null;
  return beside;
}

/// pageIsLeft is whether the leaf at [index] is a left-hand page.
///
/// The first leaf is a right-hand page and they alternate from there,
/// whether or not facing pages are shown, so a page number on the outside
/// edge does not move when the view changes.
bool pageIsLeft(int index) => index > 0 && index.isOdd;

/// leftOfSpread is whether the page at [index] is the left-hand leaf of a
/// spread. Null where it has no facing page at all.
bool? leftOfSpread(List<PageCover> covers, int index) {
  var beside = facingPage(covers, index);
  if (beside == null) return null;
  return beside > index;
}
