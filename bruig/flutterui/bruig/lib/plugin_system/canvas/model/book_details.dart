import 'package:bruig/plugin_system/canvas/model/canvas_element.dart'
    show jsonInt, jsonStr;

// book_details.dart is what a store and a reader are told about a book: who
// wrote it, what it is, and the ISBN of each edition. Kept with the canvas
// (PagesSpec.book) and written into every EPUB's package. Ken, 2026-11-19,
// step 2 of the ebook plan: Apple takes an ISBN only with a book's first
// upload, so it is set here before any submission.

/// BookEdition is one form a book is sold in, each with its own ISBN where
/// it carries one: the plain and interactive EPUBs are different editions,
/// as is the print one.
enum BookEdition {
  ebook("Ebook", "The plain EPUB: pictures, spreads and panels"),
  interactive("Interactive ebook", "The EPUB with sound, buttons and motion"),
  print("Print", "A printed paperback or hardcover");

  final String label, description;
  const BookEdition(this.label, this.description);
}

class BookDetails {
  /// subtitle goes under the canvas's own title, which is the book's.
  final String subtitle;

  /// author is who wrote it, as the store shows it; several are separated
  /// by commas.
  final String author;
  final String publisher;

  /// description is the blurb a store shows beside the cover.
  final String description;

  /// language is a BCP 47 tag: "en", "en-GB", "fr".
  final String language;

  /// subjects are a store's categories or keywords, comma separated.
  final String subjects;

  /// series is the series it belongs to, and [seriesNumber] its place in it
  /// (0 for none).
  final String series;
  final int seriesNumber;

  /// published is the date it was first published, YYYY-MM-DD, or empty.
  final String published;

  /// rights is the copyright line.
  final String rights;

  /// isbns are each edition's ISBN, by BookEdition name.
  final Map<String, String> isbns;

  const BookDetails({
    this.subtitle = "",
    this.author = "",
    this.publisher = "",
    this.description = "",
    this.language = "en",
    this.subjects = "",
    this.series = "",
    this.seriesNumber = 0,
    this.published = "",
    this.rights = "",
    this.isbns = const {},
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = BookDetails();

  /// isbnOf is [edition]'s ISBN as written, or empty.
  String isbnOf(BookEdition edition) => isbns[edition.name] ?? "";

  BookDetails withIsbn(BookEdition edition, String isbn) => copyWith(
      isbns: {...isbns, edition.name: isbn.trim()}
        ..removeWhere((_, v) => v.isEmpty));

  /// authors are [author] split at its commas.
  List<String> get authors => [
        for (var a in author.split(","))
          if (a.trim().isNotEmpty) a.trim()
      ];

  /// subjectList is [subjects] split at its commas.
  List<String> get subjectList => [
        for (var s in subjects.split(","))
          if (s.trim().isNotEmpty) s.trim()
      ];

  bool get isDefault =>
      subtitle.isEmpty &&
      author.isEmpty &&
      publisher.isEmpty &&
      description.isEmpty &&
      language == "en" &&
      subjects.isEmpty &&
      series.isEmpty &&
      seriesNumber == 0 &&
      published.isEmpty &&
      rights.isEmpty &&
      isbns.isEmpty;

  BookDetails copyWith({
    String? subtitle,
    String? author,
    String? publisher,
    String? description,
    String? language,
    String? subjects,
    String? series,
    int? seriesNumber,
    String? published,
    String? rights,
    Map<String, String>? isbns,
  }) =>
      BookDetails(
        subtitle: subtitle ?? this.subtitle,
        author: author ?? this.author,
        publisher: publisher ?? this.publisher,
        description: description ?? this.description,
        language: language ?? this.language,
        subjects: subjects ?? this.subjects,
        series: series ?? this.series,
        seriesNumber: (seriesNumber ?? this.seriesNumber).clamp(0, 9999),
        published: published ?? this.published,
        rights: rights ?? this.rights,
        isbns: isbns ?? this.isbns,
      );

  Map<String, dynamic> toJson() => {
        if (subtitle.isNotEmpty) "subtitle": subtitle,
        if (author.isNotEmpty) "author": author,
        if (publisher.isNotEmpty) "publisher": publisher,
        if (description.isNotEmpty) "description": description,
        if (language != _defaults.language) "language": language,
        if (subjects.isNotEmpty) "subjects": subjects,
        if (series.isNotEmpty) "series": series,
        if (seriesNumber != _defaults.seriesNumber)
          "seriesNumber": seriesNumber,
        if (published.isNotEmpty) "published": published,
        if (rights.isNotEmpty) "rights": rights,
        if (isbns.isNotEmpty) "isbns": isbns,
      };

  /// fromJson reads what a received file says, bounded: a long field is cut
  /// short, an unknown edition or a non-string ISBN is dropped.
  factory BookDetails.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const BookDetails();
    String text(String key, int max) {
      var v = jsonStr(json[key]) ?? "";
      return v.length > max ? v.substring(0, max) : v;
    }

    var raw = json["isbns"];
    var language = text("language", 35);
    return BookDetails(
      subtitle: text("subtitle", 300),
      author: text("author", 500),
      publisher: text("publisher", 300),
      description: text("description", 8000),
      language: language.isEmpty ? "en" : language,
      subjects: text("subjects", 1000),
      series: text("series", 300),
      seriesNumber:
          jsonInt(json["seriesNumber"], _defaults.seriesNumber).clamp(0, 9999),
      published: text("published", 10),
      rights: text("rights", 500),
      isbns: raw is Map
          ? {
              for (var e in raw.entries)
                if (e.key is String &&
                    e.value is String &&
                    BookEdition.values.any((b) => b.name == e.key) &&
                    (e.value as String).length <= 20)
                  e.key as String: e.value as String,
            }
          : const {},
    );
  }
}

/// isbnDigits is [isbn] without its hyphens and spaces, upper-cased.
String isbnDigits(String isbn) =>
    isbn.replaceAll(RegExp(r"[\s-]"), "").toUpperCase();

/// isbnProblem says what is wrong with [isbn], or null for a valid ISBN-10
/// or ISBN-13 (or none at all).
String? isbnProblem(String isbn) {
  var d = isbnDigits(isbn);
  if (d.isEmpty) return null;
  if (d.length == 13) {
    if (!RegExp(r"^\d{13}$").hasMatch(d)) return "Thirteen digits, please";
    if (!d.startsWith("978") && !d.startsWith("979")) {
      return "An ISBN-13 starts 978 or 979";
    }
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      sum += int.parse(d[i]) * (i.isEven ? 1 : 3);
    }
    var check = (10 - sum % 10) % 10;
    return check == int.parse(d[12])
        ? null
        : "Its last digit should be $check: a digit is wrong";
  }
  if (d.length == 10) {
    if (!RegExp(r"^\d{9}[\dX]$").hasMatch(d)) {
      return "Nine digits and a digit or X";
    }
    var sum = 0;
    for (var i = 0; i < 10; i++) {
      var v = d[i] == "X" ? 10 : int.parse(d[i]);
      sum += v * (10 - i);
    }
    return sum % 11 == 0 ? null : "Its last digit is wrong";
  }
  return "An ISBN has 13 digits (or 10, an older one)";
}

/// isbn13 is [isbn] as an ISBN-13, an ISBN-10 converted; null where it is
/// not a valid ISBN.
String? isbn13(String isbn) {
  var d = isbnDigits(isbn);
  if (d.isEmpty || isbnProblem(d) != null) return null;
  if (d.length == 13) return d;
  var body = "978${d.substring(0, 9)}";
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    sum += int.parse(body[i]) * (i.isEven ? 1 : 3);
  }
  return "$body${(10 - sum % 10) % 10}";
}
