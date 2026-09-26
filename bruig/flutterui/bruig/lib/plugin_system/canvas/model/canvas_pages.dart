import 'package:bruig/plugin_system/canvas/model/canvas_element.dart'
    show jsonBool, jsonInt;

// canvas_pages.dart is what a canvas is *for*, and what follows from the
// answer.
//
// The editor was built for one kind of work: a sequence of canvases played one
// after another, which is what a title card, a presentation, an animation and
// a video all are. A document is the other kind. It is the same elements on
// the same canvases, but the canvases are leaves rather than moments: they sit
// side by side rather than in time, the first and last of them are covers
// rather than content, they are numbered, and what happens between two of them
// is a page turning rather than a cut.
//
// So the difference is a handful of settings and a word, not a second editor.
// Everything in this file is either which of the two a document is, or a thing
// that only means something to the second.

/// CanvasKind is which sort of document this is.
///
/// Scenes is the default and always will be: it is what the editor was for,
/// and it is what somebody who has not thought about the question wants. A
/// document that has to be told what it is before it can be started is a
/// document nobody starts.
enum CanvasKind {
  scenes(
      "Scenes",
      "Canvases played one after another: a video, an animation, "
          "a presentation, a set of images"),
  pages(
      "Pages",
      "Leaves of a document: covers, page numbers, facing pages "
          "and a page turn between them");

  final String label;
  final String description;
  const CanvasKind(this.label, this.description);

  /// isPages is the question almost every caller actually asks.
  bool get isPages => this == pages;

  /// one and many are what a canvas of this kind is called, which is the whole
  /// of what the panels and the buttons need from this enum.
  ///
  /// Here rather than in each of them: "Add a scene" appears in the panel, in
  /// the menu, in the undo history and in four tooltips, and a word changed in
  /// five places out of six is worse than one that was never changed at all.
  String get one => this == pages ? "page" : "scene";
  String get many => this == pages ? "pages" : "scenes";

  /// Capitalised, for the start of a sentence or a heading.
  String get oneCap => this == pages ? "Page" : "Scene";
  String get manyCap => this == pages ? "Pages" : "Scenes";

  static CanvasKind fromName(String? name) =>
      values.firstWhere((k) => k.name == name, orElse: () => scenes);
}

/// PageCover marks a page that is not part of the body.
///
/// A cover is an ordinary canvas -- designed with the same elements, in the
/// same editor -- and what marking it does is take it out of three things: it
/// is not numbered, it is never paired with another page, and an exporter
/// knows it is the picture to put on the outside.
///
/// Marked rather than kept in slots of its own. A cover is a page you design,
/// and a second kind of row with its own reorder rules and its own preset path
/// is a second kind of page to keep working.
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
///
/// Its own object rather than four fields on the document, so that a document
/// of scenes carries one null-ish thing it never reads instead of four, and so
/// that the whole of "what makes this a document" is in one place to look at.
class PagesSpec {
  /// facing is whether the page being worked on is shown beside the one it
  /// faces.
  ///
  /// A way of *looking*, not a shape of canvas: every page stays one page, and
  /// two of them shown together is the editor drawing the neighbour beside the
  /// work. A spread built as one double-width canvas would make the page size
  /// two sizes, which every layout, ratio and export in here would then have
  /// to know about -- and epub and PDF both want one page per page at the end
  /// of it regardless.
  final bool facing;

  /// startAt is the number the first numbered page carries.
  ///
  /// For the document that carries on from another, and for the one whose
  /// front matter is numbered separately and starts the body at 1.
  final int startAt;

  /// countCovers is whether a cover takes a number of its own.
  ///
  /// Off, because a printed cover is not page one. On for the document that
  /// is counted from its outside in, which is how a magazine is paginated.
  final bool countCovers;

  /// numbersOnCovers is whether a number is *drawn* on a cover.
  ///
  /// Separate from [countCovers] on purpose: a magazine counts its cover as
  /// page one and does not print a 1 on it, which is two answers to what
  /// reads like one question.
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

  /// isDefault is whether this says anything at all, so that a document of
  /// scenes writes nothing down.
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
/// Worked out from the list of covers rather than stored on each page, because
/// it has to change when a page is added, removed or dragged: a number written
/// down is a number that is right until the first reorder.
///
/// [covers] is one entry per page, in order.
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
/// One rule, and it is the whole of it: **the first leaf of the document
/// stands alone, and everything after it pairs two at a time.** A front cover
/// is simply the first leaf; without one, page one takes that place, which is
/// how a bound document opens either way.
///
/// It was written as "covers stand outside, and the body pairs from its own
/// first page" -- which put a cover alone *and* page one alone, two single
/// leaves at the front, and was reported as the bug it is. Counting covers
/// separately made the rule impossible to state without saying "and then"
/// twice.
///
/// A pair containing a cover is broken, both of them standing alone: the back
/// of a document has nothing beside it, and a leaf paired with a cover would
/// be a page facing the outside of the book.
int? facingPage(List<PageCover> covers, int index) {
  if (index <= 0 || index >= covers.length) return null;
  if (covers[index].isCover) return null;
  var beside = index.isOdd ? index + 1 : index - 1;
  if (beside <= 0 || beside >= covers.length) return null;
  if (covers[beside].isCover) return null;
  return beside;
}

/// leftOfSpread is whether the page at [index] is the left-hand leaf of a
/// spread. Null where it has no facing page at all.
bool? leftOfSpread(List<PageCover> covers, int index) {
  var beside = facingPage(covers, index);
  if (beside == null) return null;
  return beside > index;
}
