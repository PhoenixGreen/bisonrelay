import 'package:bruig/plugin_system/canvas/model/canvas_element.dart'
    show jsonBool, jsonInt;

// canvas_pages.dart is which sort of document a canvas is, and the settings
// that only mean something to a document of pages: leaves side by side rather
// than moments in time, with covers, numbers and a page turn between them.

/// CanvasKind is which sort of document this is; scenes by default.
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

  /// isAudio is an audio document: timeline and mixer, the canvas put away.
  bool get isAudio => this == audio;

  /// one and many name a canvas of this kind; every label naming one uses them.
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

/// PageCover marks a page outside the body, an ordinary canvas otherwise: not
/// numbered (unless PagesSpec.countCovers), never paired, and what an
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

class PagesSpec {
  /// facing shows the page being worked on beside the one it faces: a view
  /// only, every page staying one canvas of the page size, as exports want.
  final bool facing;

  final int startAt;

  /// countCovers gives a cover a number of its own, as in a magazine; off by
  /// default.
  final bool countCovers;

  /// numbersOnCovers is whether a number is *drawn* on a cover, apart from
  /// [countCovers]: a magazine counts its cover as page one unprinted.
  final bool numbersOnCovers;

  /// masterOnCovers draws the master canvas's elements on the covers too.
  /// Off by default: a cover keeps the master's backdrop, but a running
  /// head or a page number has no place on it.
  final bool masterOnCovers;

  const PagesSpec({
    this.facing = false,
    this.startAt = 1,
    this.countCovers = false,
    this.numbersOnCovers = false,
    this.masterOnCovers = false,
  });

  PagesSpec copyWith({
    bool? facing,
    int? startAt,
    bool? countCovers,
    bool? numbersOnCovers,
    bool? masterOnCovers,
  }) =>
      PagesSpec(
        facing: facing ?? this.facing,
        startAt: startAt ?? this.startAt,
        countCovers: countCovers ?? this.countCovers,
        numbersOnCovers: numbersOnCovers ?? this.numbersOnCovers,
        masterOnCovers: masterOnCovers ?? this.masterOnCovers,
      );

  /// isDefault is every setting at its default, so nothing need be saved.
  bool get isDefault =>
      !facing &&
      startAt == 1 &&
      !countCovers &&
      !numbersOnCovers &&
      !masterOnCovers;

  Map<String, dynamic> toJson() => {
        if (facing) "facing": true,
        if (startAt != 1) "startAt": startAt,
        if (countCovers) "countCovers": true,
        if (numbersOnCovers) "numbersOnCovers": true,
        if (masterOnCovers) "masterOnCovers": true,
      };

  factory PagesSpec.fromJson(Map<String, dynamic> json) => PagesSpec(
        facing: jsonBool(json["facing"], false),
        startAt: jsonInt(json["startAt"], 1),
        countCovers: jsonBool(json["countCovers"], false),
        numbersOnCovers: jsonBool(json["numbersOnCovers"], false),
        masterOnCovers: jsonBool(json["masterOnCovers"], false),
      );
}

/// pageNumberFor is the number printed on the page at [index], or null for
/// one that carries none. Worked out rather than stored, so it follows
/// every add, remove and reorder. [covers] has one entry per page, in order.
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

/// facingPage is the page shown beside the one at [index], or null where it
/// is shown alone. The first leaf stands alone, cover or page one, and the
/// rest pair two at a time (covers are not counted separately, or a cover
/// and page one would both stand alone). A pair holding a cover is broken.
int? facingPage(List<PageCover> covers, int index) {
  if (index <= 0 || index >= covers.length) return null;
  if (covers[index].isCover) return null;
  var beside = index.isOdd ? index + 1 : index - 1;
  if (beside <= 0 || beside >= covers.length) return null;
  if (covers[beside].isCover) return null;
  return beside;
}

/// pageIsLeft is whether the leaf at [index] is a left-hand page. The first
/// is a right-hand page and they alternate, facing pages shown or not, so a
/// page number on the outside edge stays put when the view changes.
bool pageIsLeft(int index) => index > 0 && index.isOdd;

/// leftOfSpread is whether page [index] is a spread's left leaf; null alone.
bool? leftOfSpread(List<PageCover> covers, int index) {
  var beside = facingPage(covers, index);
  if (beside == null) return null;
  return beside > index;
}
