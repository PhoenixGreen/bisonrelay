import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';

// stock_sources.dart is the four stock libraries the Assets sidebar searches:
// what each is called, what it has, what can be asked of it, and how its
// answer is read.
//
// Nothing here touches the network. A search is built into a request here
// and read back here, and the request is made in stock_client.dart -- so the
// shape of five different APIs can be pinned by tests with nothing but JSON.
//
// Previews only. What a search returns is addresses: a thumbnail to show, a
// sound to listen to. Nothing is kept until it is used -- clicked onto the
// canvas, dragged, or added to the library -- and then it is stored like any
// other asset, with who made it and under what licence.

/// StockSource is one library to search.
enum StockSource {
  pixabayPictures(
    label: "Pixabay pictures",
    kind: AssetKind.picture,
    keyHost: "pixabay.com",
    keyPage: "https://pixabay.com/api/docs/",
    from: "Pixabay",
  ),
  pixabayVideos(
    label: "Pixabay videos",
    kind: AssetKind.video,
    keyHost: "pixabay.com",
    keyPage: "https://pixabay.com/api/docs/",
    from: "Pixabay",
  ),
  nounProject(
    label: "Noun Project icons",
    kind: AssetKind.picture,
    keyHost: "api.thenounproject.com",
    keyPage: "https://thenounproject.com/developers/",
    from: "Noun Project",
  ),
  freesound(
    label: "Freesound effects",
    kind: AssetKind.audio,
    keyHost: "freesound.org",
    keyPage: "https://freesound.org/apiv2/apply/",
    from: "Freesound",
  ),
  jamendo(
    label: "Jamendo music",
    kind: AssetKind.audio,
    keyHost: "api.jamendo.com",
    keyPage: "https://devportal.jamendo.com/",
    from: "Jamendo",
  );

  final String label;

  /// kind is which library section what is found here goes into.
  final AssetKind kind;

  /// keyHost is what the key is filed under -- see CanvasApiKeys. Both Pixabay
  /// searches share one key, because Pixabay gives one.
  final String keyHost;

  /// keyPage is where somebody gets a key of their own.
  final String keyPage;

  /// from is the library's own name, for the credit an asset keeps.
  final String from;

  const StockSource({
    required this.label,
    required this.kind,
    required this.keyHost,
    required this.keyPage,
    required this.from,
  });

  /// needsSecret is whether the key comes in two halves. The Noun Project
  /// signs every request with a key and a secret; the rest take a key alone.
  bool get needsSecret => this == nounProject;

  /// needsText is whether a search must say what it is looking for. The
  /// others show what is popular when asked for nothing in particular.
  bool get needsText => this == nounProject;

  /// terms is the line shown under the results: where they come from, which
  /// Pixabay asks to be shown wherever its results are, and what using one
  /// asks of the person using it.
  String get terms => switch (this) {
        pixabayPictures || pixabayVideos => "From Pixabay. Free to use under "
            "the Pixabay Content License; no credit needed.",
        nounProject => "From the Noun Project. Icons are public domain or "
            "CC BY, which asks for a credit -- kept with each icon you use.",
        freesound => "From Freesound. Each sound has its own Creative Commons "
            "licence, kept with it; CC BY asks for a credit, NC for no "
            "commercial use.",
        jamendo => "From Jamendo. Creative Commons music, most of it for "
            "non-commercial use only; each track keeps its licence.",
      };

  static StockSource fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => pixabayPictures);
}

/// StockFilter is one of the dropdowns under the search box.
class StockFilter {
  /// id is the setting's name in a StockQuery.
  final String id;
  final String label;

  /// options are (value, label). The first is the default.
  final List<(String, String)> options;

  const StockFilter(this.id, this.label, this.options);
}

const _any = ("", "Any");

const _pixabayCategories = [
  "backgrounds", "fashion", "nature", "science", "education", "feelings", //
  "health", "people", "religion", "places", "animals", "industry",
  "computer", "food", "sports", "transportation", "travel", "buildings",
  "business", "music",
];

const _pixabayColours = [
  "grayscale", "transparent", "red", "orange", "yellow", "green", //
  "turquoise", "blue", "lilac", "pink", "white", "gray", "black", "brown",
];

String _capital(String s) =>
    s.isEmpty ? s : "${s[0].toUpperCase()}${s.substring(1)}";

/// filtersFor is what [source] can be narrowed by.
List<StockFilter> filtersFor(StockSource source) => switch (source) {
      StockSource.pixabayPictures => [
          const StockFilter("image_type", "Type", [
            _any,
            ("photo", "Photos"),
            ("illustration", "Illustrations"),
            ("vector", "Vectors"),
          ]),
          const StockFilter("orientation", "Shape", [
            _any,
            ("horizontal", "Landscape"),
            ("vertical", "Portrait"),
          ]),
          StockFilter("colors", "Colour", [
            _any,
            for (var c in _pixabayColours) (c, _capital(c)),
          ]),
          StockFilter("category", "Category", [
            _any,
            for (var c in _pixabayCategories) (c, _capital(c)),
          ]),
          const StockFilter("order", "Order", [
            ("popular", "Popular"),
            ("latest", "Latest"),
          ]),
        ],
      StockSource.pixabayVideos => [
          const StockFilter("video_type", "Type", [
            _any,
            ("film", "Film"),
            ("animation", "Animation"),
          ]),
          StockFilter("category", "Category", [
            _any,
            for (var c in _pixabayCategories) (c, _capital(c)),
          ]),
          const StockFilter("order", "Order", [
            ("popular", "Popular"),
            ("latest", "Latest"),
          ]),
        ],
      // Public domain first: a free Noun Project key sees nothing else.
      StockSource.nounProject => [
          const StockFilter("limit_to_public_domain", "Licence", [
            ("1", "Public domain"),
            ("0", "Any (paid key)"),
          ]),
        ],
      StockSource.freesound => [
          const StockFilter("duration", "Length", [
            _any,
            ("[0 TO 5]", "Under 5s"),
            ("[5 TO 30]", "5-30s"),
            ("[30 TO 120]", "30s-2m"),
            ("[120 TO *]", "Over 2m"),
          ]),
          const StockFilter("license", "Licence", [
            _any,
            ('"Creative Commons 0"', "CC0"),
            ('"Attribution"', "CC BY"),
            ('"Attribution NonCommercial"', "CC BY-NC"),
          ]),
          const StockFilter("sort", "Order", [
            ("score", "Relevance"),
            ("downloads_desc", "Most downloaded"),
            ("rating_desc", "Top rated"),
            ("created_desc", "Newest"),
            ("duration_asc", "Shortest"),
          ]),
        ],
      StockSource.jamendo => [
          const StockFilter("fuzzytags", "Genre", [
            _any,
            ("ambient", "Ambient"),
            ("electronic", "Electronic"),
            ("soundtrack", "Cinematic"),
            ("classical", "Classical"),
            ("jazz", "Jazz"),
            ("rock", "Rock"),
            ("pop", "Pop"),
            ("hiphop", "Hip hop"),
            ("folk", "Folk"),
            ("lounge", "Lounge"),
            ("world", "World"),
            ("metal", "Metal"),
          ]),
          const StockFilter("vocalinstrumental", "Vocals", [
            _any,
            ("instrumental", "Instrumental"),
            ("vocal", "With vocals"),
          ]),
          const StockFilter("speed", "Tempo", [
            _any,
            ("verylow", "Very slow"),
            ("low", "Slow"),
            ("medium", "Medium"),
            ("high", "Fast"),
            ("veryhigh", "Very fast"),
          ]),
          const StockFilter("order", "Order", [
            ("", "Relevance"),
            ("popularity_total", "Popular"),
            ("listens_week", "Listened to this week"),
            ("releasedate_desc", "Newest"),
          ]),
        ],
    };

/// pageSize is how many results a search asks for at a time.
const int stockPageSize = 30;

/// StockQuery is one search: where, for what, narrowed how, and which page.
class StockQuery {
  final StockSource source;
  final String text;

  /// filters holds a value per StockFilter id; one not set is the default.
  final Map<String, String> filters;

  /// page is the page wanted, from 1. The Noun Project pages by a token
  /// instead, which is [cursor].
  final int page;
  final String cursor;

  const StockQuery(
    this.source, {
    this.text = "",
    this.filters = const {},
    this.page = 1,
    this.cursor = "",
  });

  /// value is [id]'s filter setting, or the filter's default.
  String value(String id) {
    var set = filters[id];
    if (set != null) return set;
    for (var f in filtersFor(source)) {
      if (f.id == id) return f.options.first.$1;
    }
    return "";
  }

  StockQuery next(StockPage from) => StockQuery(source,
      text: text, filters: filters, page: page + 1, cursor: from.cursor);
}

/// StockRequest is a search as the request that makes it.
class StockRequest {
  final Uri uri;
  final Map<String, String> headers;

  /// signed is whether the request still has to be signed with the key and
  /// secret -- the Noun Project's -- before it is sent. See oauthHeader.
  final bool signed;

  const StockRequest(this.uri, {this.headers = const {}, this.signed = false});

  /// cacheKey is the address without the key in it: the same search made
  /// with a new key is the same search.
  String get cacheKey {
    var q = Map<String, String>.of(uri.queryParameters)
      ..remove("key")
      ..remove("client_id")
      ..remove("token");
    return uri.replace(queryParameters: q.isEmpty ? null : q).toString();
  }
}

/// requestFor is [q] as a request, with [key] where the source wants it.
///
/// Freesound's goes in a header rather than the address, so it is not
/// written into a log line by accident; Pixabay and Jamendo take it only in
/// the address.
StockRequest requestFor(StockQuery q, {required String key}) {
  var text = q.text.trim();
  Map<String, String> chosen(List<String> ids) => {
        for (var id in ids)
          if (q.value(id).isNotEmpty) id: q.value(id),
      };

  switch (q.source) {
    case StockSource.pixabayPictures:
      return StockRequest(Uri.https("pixabay.com", "/api/", {
        "key": key,
        if (text.isNotEmpty) "q": text,
        ...chosen(["image_type", "orientation", "colors", "category", "order"]),
        "safesearch": "true",
        "per_page": "$stockPageSize",
        "page": "${q.page}",
      }));
    case StockSource.pixabayVideos:
      return StockRequest(Uri.https("pixabay.com", "/api/videos/", {
        "key": key,
        if (text.isNotEmpty) "q": text,
        ...chosen(["video_type", "category", "order"]),
        "safesearch": "true",
        "per_page": "$stockPageSize",
        "page": "${q.page}",
      }));
    case StockSource.nounProject:
      return StockRequest(
        Uri.https("api.thenounproject.com", "/v2/icon", {
          "query": text,
          "limit": "$stockPageSize",
          "thumbnail_size": "200",
          "include_svg": "1",
          "blacklist": "1",
          if (q.value("limit_to_public_domain") == "1")
            "limit_to_public_domain": "1",
          if (q.cursor.isNotEmpty) "next_page": q.cursor,
        }),
        signed: true,
      );
    case StockSource.freesound:
      var filter = [
        if (q.value("duration").isNotEmpty) "duration:${q.value("duration")}",
        if (q.value("license").isNotEmpty) "license:${q.value("license")}",
      ].join(" ");
      return StockRequest(
        Uri.https("freesound.org", "/apiv2/search/", {
          "query": text,
          if (filter.isNotEmpty) "filter": filter,
          "sort": q.value("sort"),
          "fields": "id,name,previews,duration,license,username,url,images",
          "page_size": "$stockPageSize",
          "page": "${q.page}",
        }),
        headers: {"Authorization": "Token $key"},
      );
    case StockSource.jamendo:
      var order = q.value("order");
      return StockRequest(Uri.https("api.jamendo.com", "/v3.0/tracks/", {
        "client_id": key,
        "format": "json",
        "limit": "$stockPageSize",
        "offset": "${(q.page - 1) * stockPageSize}",
        if (text.isNotEmpty) "search": text,
        // Jamendo has no "relevance" without something to be relevant to.
        if (order.isNotEmpty) "order": order,
        if (order.isEmpty && text.isEmpty) "order": "popularity_total",
        ...chosen(["fuzzytags", "vocalinstrumental", "speed"]),
        "audioformat": "mp32",
        "include": "licenses musicinfo",
      }));
  }
}

/// StockItem is one result: enough to show it, play a preview of it, and
/// fetch it when it is used.
class StockItem {
  final StockSource source;
  final String id;
  final String title;
  final String author;

  /// license is a short name -- "CC BY 4.0" -- and licenseUrl its text.
  final String license;
  final String licenseUrl;

  /// page is the item's own page on the library's site.
  final String page;

  /// thumb is a small picture of it, for the results; empty for a sound
  /// with nothing to show.
  final String thumb;

  /// media is what is fetched when it is used.
  final String media;

  /// preview is a sound to listen to before choosing, for audio.
  final String preview;

  final int width;
  final int height;
  final double length;

  const StockItem({
    required this.source,
    required this.id,
    required this.title,
    required this.media,
    this.author = "",
    this.license = "",
    this.licenseUrl = "",
    this.page = "",
    this.thumb = "",
    this.preview = "",
    this.width = 0,
    this.height = 0,
    this.length = 0,
  });

  AssetKind get kind => source.kind;

  /// key is unique across every source, for the results list.
  String get key => "${source.name}-$id";

  /// credit is the line somebody using it would print: what, by whom, from
  /// where, under what.
  String get credit => [
        author.isEmpty ? title : "$title by $author",
        "from ${source.from}",
        if (license.isNotEmpty) "($license)",
      ].join(" ");
}

/// StockPage is one page of results, or why there is not one.
class StockPage {
  final List<StockItem> items;

  /// more is whether asking for the next page would find anything.
  final bool more;

  /// cursor is the Noun Project's token for the next page.
  final String cursor;

  final String? problem;

  const StockPage(this.items, {this.more = false, this.cursor = ""})
      : problem = null;
  const StockPage.failed(this.problem)
      : items = const [],
        more = false,
        cursor = "";

  bool get worked => problem == null;
}

/// licenceName is a Creative Commons address as the short name people know
/// it by: .../licenses/by-nc-sa/3.0/ is CC BY-NC-SA 3.0, .../zero/1.0/ CC0.
String licenceName(String url) {
  var u = url.toLowerCase();
  if (u.isEmpty) return "";
  if (u.contains("publicdomain/zero")) return "CC0";
  if (u.contains("publicdomain")) return "Public domain";
  var m = RegExp(r"licenses/([a-z+\-]+)/([0-9.]+)").firstMatch(u);
  if (m == null) {
    // Freesound's own spellings, which it also answers with sometimes.
    return switch (url) {
      "Creative Commons 0" => "CC0",
      "Attribution" => "CC BY",
      "Attribution NonCommercial" => "CC BY-NC",
      _ => url,
    };
  }
  var terms = m.group(1)!;
  var name = terms == "sampling+" ? "Sampling+" : "CC ${terms.toUpperCase()}";
  return "$name ${m.group(2)}";
}

T? _at<T>(Object? json, List<Object> path) {
  var here = json;
  for (var step in path) {
    if (step is String && here is Map) {
      here = here[step];
    } else if (step is int && here is List && step < here.length) {
      here = here[step];
    } else {
      return null;
    }
  }
  return here is T ? here : null;
}

String _s(Object? json, List<Object> path) {
  var v = _at<Object>(json, path);
  return v == null ? "" : "$v";
}

int _i(Object? json, List<Object> path) => _at<num>(json, path)?.toInt() ?? 0;

double _d(Object? json, List<Object> path) =>
    _at<num>(json, path)?.toDouble() ?? 0;

/// _titleFromTags names a Pixabay result, which has tags and no title:
/// "mountain, lake, sunrise" is "Mountain lake sunrise".
String _titleFromTags(String tags, String fallback) {
  var words = tags
      .split(",")
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .take(3)
      .join(" ");
  return words.isEmpty ? fallback : _capital(words);
}

String _absolute(String url, String site) =>
    url.isEmpty || url.startsWith("http") ? url : "$site$url";

/// parseStock reads [json], the answer to a search of [q].
StockPage parseStock(StockQuery q, Object? json) {
  var source = q.source;
  switch (source) {
    case StockSource.pixabayPictures:
      var hits = _at<List>(json, ["hits"]) ?? const [];
      var items = [
        for (var h in hits)
          StockItem(
            source: source,
            id: _s(h, ["id"]),
            title: _titleFromTags(_s(h, ["tags"]), "Pixabay ${_s(h, ["id"])}"),
            author: _s(h, ["user"]),
            license: "Pixabay Content License",
            licenseUrl: "https://pixabay.com/service/license-summary/",
            page: _s(h, ["pageURL"]),
            thumb: _s(h, ["previewURL"]),
            media: [
              _s(h, ["largeImageURL"]),
              _s(h, ["webformatURL"])
            ].firstWhere((u) => u.isNotEmpty, orElse: () => ""),
            width: _i(h, ["imageWidth"]),
            height: _i(h, ["imageHeight"]),
          ),
      ].where((i) => i.media.isNotEmpty).toList();
      return StockPage(items,
          more: q.page * stockPageSize < _i(json, ["totalHits"]));

    case StockSource.pixabayVideos:
      var hits = _at<List>(json, ["hits"]) ?? const [];
      var items = <StockItem>[];
      for (var h in hits) {
        // Medium is 1280 wide, which is the canvas's own size: large is
        // four times the download for pixels nobody sees.
        var chosen = ["medium", "small", "large", "tiny"]
            .map((r) => _at<Map>(h, ["videos", r]))
            .firstWhere((v) => v != null && _s(v, ["url"]).isNotEmpty,
                orElse: () => null);
        if (chosen == null) continue;
        var thumb = ["tiny", "small", "medium"]
            .map((r) => _s(h, ["videos", r, "thumbnail"]))
            .firstWhere((t) => t.isNotEmpty, orElse: () => "");
        items.add(StockItem(
          source: source,
          id: _s(h, ["id"]),
          title: _titleFromTags(_s(h, ["tags"]), "Pixabay ${_s(h, ["id"])}"),
          author: _s(h, ["user"]),
          license: "Pixabay Content License",
          licenseUrl: "https://pixabay.com/service/license-summary/",
          page: _s(h, ["pageURL"]),
          thumb: thumb,
          media: _s(chosen, ["url"]),
          width: _i(chosen, ["width"]),
          height: _i(chosen, ["height"]),
          length: _d(h, ["duration"]),
        ));
      }
      return StockPage(items,
          more: q.page * stockPageSize < _i(json, ["totalHits"]));

    case StockSource.nounProject:
      var icons = _at<List>(json, ["icons"]) ?? const [];
      var items = <StockItem>[];
      for (var h in icons) {
        var svg = _s(h, ["icon_url"]);
        var png = _s(h, ["thumbnail_url"]);
        if (svg.isEmpty && png.isEmpty) continue;
        var pd = _s(h, ["license_description"]) == "public-domain";
        items.add(StockItem(
          source: source,
          id: _s(h, ["id"]),
          title: _capital(_s(h, ["term"])),
          author: _s(h, ["creator", "name"]),
          license: pd ? "Public domain" : "CC BY 3.0",
          licenseUrl: pd
              ? "https://creativecommons.org/publicdomain/zero/1.0/"
              : "https://creativecommons.org/licenses/by/3.0/",
          page: _absolute(_s(h, ["permalink"]), "https://thenounproject.com"),
          thumb: png.isEmpty ? svg : png,
          // The drawing itself where there is one: it stays sharp at any
          // size and takes a fill like any other shape.
          media: svg.isEmpty ? png : svg,
          width: 1,
          height: 1,
        ));
      }
      var cursor = _s(json, ["next_page"]);
      return StockPage(items, more: cursor.isNotEmpty, cursor: cursor);

    case StockSource.freesound:
      var results = _at<List>(json, ["results"]) ?? const [];
      var items = <StockItem>[];
      for (var h in results) {
        var hq = _s(h, ["previews", "preview-hq-mp3"]);
        if (hq.isEmpty) continue;
        var licence = _s(h, ["license"]);
        items.add(StockItem(
          source: source,
          id: _s(h, ["id"]),
          title: _s(h, ["name"]).replaceAll(
              RegExp(r"\.(wav|mp3|aiff?|flac|ogg)$", caseSensitive: false), ""),
          author: _s(h, ["username"]),
          license: licenceName(licence),
          licenseUrl: licence.startsWith("http") ? licence : "",
          page: _s(h, ["url"]),
          thumb: _s(h, ["images", "waveform_m"]),
          // The high-quality preview is what a key alone can fetch: the
          // original file needs a login to Freesound, which this is not.
          media: hq,
          preview: _s(h, ["previews", "preview-lq-mp3"]).isEmpty
              ? hq
              : _s(h, ["previews", "preview-lq-mp3"]),
          length: _d(h, ["duration"]),
        ));
      }
      return StockPage(items, more: _at<Object>(json, ["next"]) != null);

    case StockSource.jamendo:
      if (_s(json, ["headers", "status"]) == "failed") {
        var why = _s(json, ["headers", "error_message"]);
        return StockPage.failed(
            why.isEmpty ? "Jamendo refused the search." : "Jamendo: $why");
      }
      var results = _at<List>(json, ["results"]) ?? const [];
      var items = <StockItem>[];
      for (var h in results) {
        var stream = _s(h, ["audio"]);
        var download = _at<bool>(h, ["audiodownload_allowed"]) == true
            ? _s(h, ["audiodownload"])
            : "";
        if (stream.isEmpty && download.isEmpty) continue;
        var licence = _s(h, ["license_ccurl"]);
        items.add(StockItem(
          source: source,
          id: _s(h, ["id"]),
          title: _s(h, ["name"]),
          author: _s(h, ["artist_name"]),
          license: licenceName(licence),
          licenseUrl: licence,
          page: _s(h, ["shareurl"]),
          thumb: [
            _s(h, ["image"]),
            _s(h, ["album_image"])
          ].firstWhere((u) => u.isNotEmpty, orElse: () => ""),
          media: download.isEmpty ? stream : download,
          preview: stream.isEmpty ? download : stream,
          length: _d(h, ["duration"]),
        ));
      }
      return StockPage(items, more: results.length >= stockPageSize);
  }
}
