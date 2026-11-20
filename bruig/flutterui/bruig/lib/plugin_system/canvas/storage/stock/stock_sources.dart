import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';

// stock_sources.dart is the stock libraries the Assets sidebar searches:
// what each has, how requests are built and answers read. No network here
// (stock_client.dart), so each API's shape is tested with JSON. Nothing is
// kept until used, and then stored with its author and licence.

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
  ),

  /// polyHaven is Poly Haven's 3D models: CC0, no key (see polyHavenPage
  /// and fetchPolyHavenModel).
  polyHaven(
    label: "Poly Haven models",
    kind: AssetKind.model,
    keyHost: "",
    keyPage: "https://polyhaven.com/models",
    from: "Poly Haven",
  ),

  /// iconify is Iconify's icons: some 200,000 from open-source sets,
  /// keyless, each under its set's licence.
  iconify(
    label: "Iconify icons",
    kind: AssetKind.picture,
    keyHost: "",
    keyPage: "https://iconify.design/",
    from: "Iconify",
  ),

  /// wikimedia is Wikimedia Commons: photographs, paintings, drawings and
  /// old illustrations, each under its own free licence, read with it.
  wikimedia(
    label: "Wikimedia Commons",
    kind: AssetKind.picture,
    keyHost: "",
    keyPage: "https://commons.wikimedia.org/",
    from: "Wikimedia Commons",
  ),

  /// pexels is Pexels' photographs: landscapes, skies, people; free to use,
  /// with the person's own key.
  pexels(
    label: "Pexels photos",
    kind: AssetKind.picture,
    keyHost: "api.pexels.com",
    keyPage: "https://www.pexels.com/api/",
    from: "Pexels",
  ),

  /// met is the Metropolitan Museum of Art's public-domain works: paintings
  /// of landscapes, figures and creatures (CC0), no key.
  met(
    label: "The Met (paintings)",
    kind: AssetKind.picture,
    keyHost: "",
    keyPage: "https://metmuseum.github.io/",
    from: "The Met",
  ),

  /// nasa is NASA's image library: space, the Earth and the sky. Public
  /// domain, but NASA's own rules come with it (see terms).
  nasa(
    label: "NASA images",
    kind: AssetKind.picture,
    keyHost: "",
    keyPage: "https://images.nasa.gov/",
    from: "NASA",
  ),

  /// ambientCG is ambientCG's materials: wood, stone, fabric, ground and
  /// the like, flat and seamless, CC0, no key.
  ambientCG(
    label: "ambientCG textures",
    kind: AssetKind.picture,
    keyHost: "",
    keyPage: "https://ambientcg.com/",
    from: "ambientCG",
  ),

  /// polyHavenPictures is Poly Haven's skies (its HDRIs, as flat panoramas)
  /// and textures, CC0, no key (see polyHavenPage).
  polyHavenPictures(
    label: "Poly Haven skies and textures",
    kind: AssetKind.picture,
    keyHost: "",
    keyPage: "https://polyhaven.com/",
    from: "Poly Haven",
  );

  final String label;

  /// kind is the library section its finds go into.
  final AssetKind kind;

  /// keyHost is what the key is filed under (see CanvasApiKeys). Both
  /// Pixabay searches share Pixabay's one key.
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

  /// needsSecret is whether the key has two halves: the Noun Project signs
  /// with a key and a secret.
  bool get needsSecret => this == nounProject;

  /// needsKey is whether a search needs a key of the person's own; the
  /// rest are open.
  bool get needsKey => switch (this) {
        pixabayPictures ||
        pixabayVideos ||
        nounProject ||
        freesound ||
        jamendo ||
        pexels =>
          true,
        _ => false,
      };

  /// needsText is whether a search must name something; the others show
  /// what is popular for an empty search.
  bool get needsText => switch (this) {
        nounProject || iconify || wikimedia || met || nasa => true,
        _ => false,
      };

  /// terms is the line under the results: their source, which Pixabay asks
  /// to be shown with its results, and what using one asks.
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
        // Poly Haven asks for this credit wherever its live API is used.
        polyHaven => "Powered by Poly Haven. Its models are CC0: free for "
            "any use, no credit needed -- though it is appreciated.",
        iconify => "From Iconify's open-source icon sets. Each icon keeps "
            "its set's licence; CC BY asks for a credit.",
        wikimedia => "From Wikimedia Commons. Each file keeps its own free "
            "licence and author; CC BY and BY-SA ask for a credit, kept with "
            "it.",
        // Pexels asks for a prominent link back to it with its results.
        pexels => "Photos provided by Pexels (pexels.com). Free to use; "
            "crediting the photographer is appreciated.",
        met => "From The Metropolitan Museum of Art's Open Access works: "
            "public domain (CC0), free for any use.",
        // NASA's own media guidelines, which matter for an app like this.
        nasa => "From NASA. Generally public domain; credit NASA. NASA's "
            "rules: never suggest NASA endorses anything -- cryptocurrency "
            "included -- and no use as NFTs.",
        ambientCG => "From ambientCG. Its textures are CC0: free for any "
            "use, no credit needed.",
        polyHavenPictures => "Powered by Poly Haven. Its skies and textures "
            "are CC0: free for any use, no credit needed.",
      };

  static StockSource fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => pixabayPictures);
}

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
      StockSource.polyHaven => const [],
      StockSource.wikimedia => const [
          StockFilter("filetype", "Type", [
            ("bitmap", "Photos and pictures"),
            ("drawing", "Drawings"),
          ]),
          StockFilter("licence", "Licence", [
            ("free", "No credit needed"),
            ("", "Any free licence"),
          ]),
        ],
      StockSource.pexels => const [
          StockFilter("orientation", "Shape", [
            _any,
            ("landscape", "Landscape"),
            ("portrait", "Portrait"),
            ("square", "Square"),
          ]),
          StockFilter("color", "Colour", [
            _any,
            ("red", "Red"),
            ("orange", "Orange"),
            ("yellow", "Yellow"),
            ("green", "Green"),
            ("turquoise", "Turquoise"),
            ("blue", "Blue"),
            ("violet", "Violet"),
            ("pink", "Pink"),
            ("brown", "Brown"),
            ("black", "Black"),
            ("gray", "Grey"),
            ("white", "White"),
          ]),
        ],
      StockSource.met || StockSource.nasa || StockSource.ambientCG => const [],
      StockSource.polyHavenPictures => const [
          StockFilter("t", "Type", [
            ("hdris", "Skies"),
            ("textures", "Textures"),
          ]),
        ],
      StockSource.iconify => const [
          // One colour first: those take a fill, as the canvas's shapes do;
          // the rest keep their set's colours.
          StockFilter("palette", "Colour", [
            ("false", "One colour"),
            ("", "Any"),
          ]),
          StockFilter("licence", "Licence", [
            ("free", "No credit needed"),
            ("", "Any open licence"),
          ]),
        ],
    };

/// iconifyPageSize is the icons on a page of Iconify's. Its search has no
/// offset: page n asks for n pages' worth and shows the last.
const int iconifyPageSize = 48;

/// iconifyMost is the most icons one Iconify search returns.
const int iconifyMost = 999;

/// _creditFree are licences whose Iconify icons need no credit shown:
/// permissive and public domain. CC BY, CC BY-SA and GPL ask for more.
const _creditFree = {
  "MIT", "Apache-2.0", "ISC", "0BSD", "BSD-2-Clause", "BSD-3-Clause", //
  "CC0-1.0", "Unlicense", "OFL-1.1", "MPL-2.0",
};

/// iconifySvg is Iconify's [icon] ("set:name") as an SVG address: black for
/// the current colour, sized in pixels, as a lone drawing has no em.
String iconifySvg(String icon, {String colour = "#000000", int height = 256}) {
  var at = icon.indexOf(":");
  var set = at < 0 ? icon : icon.substring(0, at);
  var name = at < 0 ? icon : icon.substring(at + 1);
  return Uri.https("api.iconify.design", "/$set/$name.svg",
      {"color": colour, "height": "$height"}).toString();
}

/// stockPageSize is how many results a search asks for at a time.
const int stockPageSize = 30;

class StockQuery {
  final StockSource source;
  final String text;

  /// filters holds a value per StockFilter id; unset is the default.
  final Map<String, String> filters;

  /// page is the page wanted, from 1. The Noun Project pages by a token
  /// instead, [cursor].
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

class StockRequest {
  final Uri uri;
  final Map<String, String> headers;

  /// signed is whether the request must still be signed with the Noun
  /// Project's key and secret before sending. See oauthHeader.
  final bool signed;

  const StockRequest(this.uri, {this.headers = const {}, this.signed = false});

  /// cacheKey is the address without the key, so a new key does not make a
  /// new search.
  String get cacheKey {
    var q = Map<String, String>.of(uri.queryParameters)
      ..remove("key")
      ..remove("client_id")
      ..remove("token");
    return uri.replace(queryParameters: q.isEmpty ? null : q).toString();
  }
}

/// requestFor is [q] as a request with [key] where the source wants it:
/// Freesound's in a header, so it cannot slip into a log line.
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
    // Its search names the models; the catalogue says what they are (see
    // StockClient._polyHaven).
    case StockSource.polyHaven:
      return StockRequest(Uri.https("api.polyhaven.com", "/search", {
        "q": text,
        "t": "models",
      }));
    case StockSource.wikimedia:
      return StockRequest(
          Uri.https("commons.wikimedia.org", "/w/api.php", {
            "action": "query",
            "format": "json",
            "generator": "search",
            "gsrsearch": "$text filetype:${q.value("filetype")}",
            "gsrnamespace": "6",
            "gsrlimit": "$stockPageSize",
            "gsroffset": "${(q.page - 1) * stockPageSize}",
            "prop": "imageinfo",
            "iiprop": "url|size|mime|extmetadata",
            "iiurlwidth": "1600",
            "iiextmetadatafilter":
                "LicenseShortName|LicenseUrl|Artist|ObjectName|AttributionRequired",
          }),
          headers: stockAgentHeaders);
    case StockSource.pexels:
      return StockRequest(
          Uri.https(
              "api.pexels.com", text.isEmpty ? "/v1/curated" : "/v1/search", {
            if (text.isNotEmpty) "query": text,
            if (text.isNotEmpty) ...chosen(["orientation", "color"]),
            "per_page": "$stockPageSize",
            "page": "${q.page}",
          }),
          headers: {"Authorization": key});
    // The Met's search answers ids only; each work is asked for in turn
    // (see StockClient._met).
    case StockSource.met:
      return StockRequest(
          Uri.https(
              "collectionapi.metmuseum.org", "/public/collection/v1.1/search", {
            "q": text,
            "hasImages": "true",
          }),
          headers: stockAgentHeaders);
    case StockSource.nasa:
      return StockRequest(
          Uri.https("images-api.nasa.gov", "/search", {
            "q": text,
            "media_type": "image",
            "page": "${q.page}",
            "page_size": "$stockPageSize",
          }),
          headers: stockAgentHeaders);
    case StockSource.ambientCG:
      return StockRequest(
          Uri.https("ambientcg.com", "/api/v3/assets", {
            if (text.isNotEmpty) "q": text,
            "type": "material",
            "sort": "popular",
            "limit": "$stockPageSize",
            "offset": "${(q.page - 1) * stockPageSize}",
          }),
          headers: stockAgentHeaders);
    // Its catalogue, in the order its search gives (see StockClient).
    case StockSource.polyHavenPictures:
      return StockRequest(Uri.https("api.polyhaven.com", "/search", {
        "q": text,
        "t": q.value("t"),
      }));
    case StockSource.iconify:
      return StockRequest(Uri.https("api.iconify.design", "/search", {
        "query": text,
        "limit": "${math.min(q.page * iconifyPageSize, iconifyMost)}",
        if (q.value("palette").isNotEmpty) "palette": q.value("palette"),
      }));
  }
}

/// StockItem is one result: enough to show it, preview it, and fetch it
/// when used.
class StockItem {
  final StockSource source;
  final String id;
  final String title;
  final String author;

  /// license is a short name ("CC BY 4.0"), and licenseUrl its text.
  final String license;
  final String licenseUrl;

  /// page is the item's own page on the library's site.
  final String page;

  /// thumb is a small picture for the results; empty for a sound with
  /// nothing to show.
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

  /// credit is the line a user would print: what, by whom, from where,
  /// under what.
  String get credit => [
        author.isEmpty ? title : "$title by $author",
        "from ${source.from}",
        if (license.isNotEmpty) "($license)",
      ].join(" ");
}

/// StockPage is one page of results, or why there is not one.
class StockPage {
  final List<StockItem> items;

  /// more is whether the next page would find anything.
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

/// licenceName is a Creative Commons address as its short name:
/// .../licenses/by-nc-sa/3.0/ is CC BY-NC-SA 3.0, .../zero/1.0/ CC0.
String licenceName(String url) {
  var u = url.toLowerCase();
  if (u.isEmpty) return "";
  if (u.contains("publicdomain/zero")) return "CC0";
  if (u.contains("publicdomain")) return "Public domain";
  var m = RegExp(r"licenses/([a-z+\-]+)/([0-9.]+)").firstMatch(u);
  if (m == null) {
    // Freesound's own spellings, which it sometimes answers with.
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

/// _titleFromTags names a Pixabay result, which has tags but no title:
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
        // Medium is 1280 wide, the canvas's own size: large is four times
        // the download for unseen pixels.
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
          // The smallest rendition for previewing: a few hundred kilobytes,
          // not the one that is kept.
          preview: ["tiny", "small", "medium"]
              .map((r) => _s(h, ["videos", r, "url"]))
              .firstWhere((u) => u.isNotEmpty, orElse: () => ""),
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
          // The drawing where there is one: sharp at any size, and it takes
          // a fill like any shape.
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
          // The high-quality preview is what a key alone can fetch; the
          // original needs a Freesound login.
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
    case StockSource.polyHaven || StockSource.polyHavenPictures:
      throw StateError("Poly Haven pages are made by polyHavenPage");
    case StockSource.met:
      throw StateError("The Met's pages are made by metPage");
    case StockSource.wikimedia:
      return _wikimedia(q, json);
    case StockSource.pexels:
      var photos = _at<List>(json, ["photos"]) ?? const [];
      var items = [
        for (var h in photos)
          StockItem(
            source: source,
            id: _s(h, ["id"]),
            title: _s(h, ["alt"]).isEmpty
                ? "Pexels ${_s(h, ["id"])}"
                : _capital(_s(h, ["alt"])),
            author: _s(h, ["photographer"]),
            license: "Pexels License",
            licenseUrl: "https://www.pexels.com/license/",
            page: _s(h, ["url"]),
            thumb: _s(h, ["src", "medium"]),
            // Two thousand across at most: the original can be a
            // camera's whole frame, far more than a canvas shows.
            media: [
              _s(h, ["src", "large2x"]),
              _s(h, ["src", "original"])
            ].firstWhere((u) => u.isNotEmpty, orElse: () => ""),
            width: _i(h, ["width"]),
            height: _i(h, ["height"]),
          ),
      ].where((i) => i.media.isNotEmpty).toList();
      return StockPage(items, more: _s(json, ["next_page"]).isNotEmpty);
    case StockSource.nasa:
      var found = _at<List>(json, ["collection", "items"]) ?? const [];
      var items = <StockItem>[];
      for (var h in found) {
        var id = _s(h, ["data", 0, "nasa_id"]);
        var links = _at<List>(h, ["links"]) ?? const [];
        String link(String name) =>
            [
              for (var l in links)
                if (_s(l, ["href"]).contains("~$name.")) _s(l, ["href"])
            ].firstOrNull ??
            "";
        var media = [link("large"), link("medium"), link("orig")]
            .firstWhere((u) => u.isNotEmpty, orElse: () => "");
        if (id.isEmpty || media.isEmpty) continue;
        var by = [
          _s(h, ["data", 0, "photographer"]),
          _s(h, ["data", 0, "secondary_creator"]),
          _s(h, ["data", 0, "center"]),
        ].where((x) => x.isNotEmpty).firstOrNull;
        items.add(StockItem(
          source: source,
          id: id,
          title: _s(h, ["data", 0, "title"]),
          author: by == null ? "NASA" : "NASA, $by",
          license: "Public domain (NASA)",
          licenseUrl:
              "https://www.nasa.gov/nasa-brand-center/images-and-media/",
          page: "https://images.nasa.gov/details/$id",
          thumb: link("thumb").isEmpty ? link("small") : link("thumb"),
          media: media,
        ));
      }
      var links = _at<List>(json, ["collection", "links"]) ?? const [];
      return StockPage(items, more: links.any((l) => _s(l, ["rel"]) == "next"));
    case StockSource.ambientCG:
      var assets = _at<List>(json, ["assets"]) ?? const [];
      var items = [
        for (var h in assets)
          if (_s(h, ["id"]) case var id when RegExp(r"^\w+$").hasMatch(id))
            StockItem(
              source: source,
              id: id,
              title: _spaced(id),
              author: "ambientCG",
              license: "CC0",
              licenseUrl: "https://docs.ambientcg.com/license/",
              page: "https://ambientcg.com/view?id=$id",
              thumb: "https://acg-media.struffelproductions.com/file/"
                  "ambientCG-Web/media/thumbnail/256-JPG-FFFFFF/$id.jpg",
              // Its flat colour map, two thousand square: a texture as a
              // picture.
              media: "https://f003.backblazeb2.com/file/ambientCG-Web/media/"
                  "surface-preview/$id/${id}_SQ_Color.jpg",
              width: 2048,
              height: 2048,
            ),
      ];
      return StockPage(items,
          more: _at<Object>(json, ["nextPageHttp"]) is String);
    case StockSource.iconify:
      var icons = _at<List>(json, ["icons"]) ?? const [];
      var sets = _at<Map>(json, ["collections"]) ?? const {};
      var free = q.value("licence") == "free";
      var items = <StockItem>[];
      // Page n is everything after the pages before it.
      for (var icon in icons.skip((q.page - 1) * iconifyPageSize)) {
        var id = "$icon";
        var at = id.indexOf(":");
        if (at <= 0) continue;
        var set = sets[id.substring(0, at)];
        var spdx = _s(set, ["license", "spdx"]);
        if (free && !_creditFree.contains(spdx)) continue;
        var name = id.substring(at + 1);
        items.add(StockItem(
          source: source,
          id: id,
          title: _capital(name.replaceAll("-", " ")),
          author: [
            _s(set, ["name"]),
            _s(set, ["author", "name"])
          ].where((x) => x.isNotEmpty).join(", "),
          license: _s(set, ["license", "title"]),
          licenseUrl: _s(set, ["license", "url"]),
          page: "https://icon-sets.iconify.design/${id.substring(0, at)}/"
              "?icon-filter=$name",
          thumb: iconifySvg(id, height: 96),
          media: iconifySvg(id),
          width: 1,
          height: 1,
        ));
      }
      var asked = _i(json, ["limit"]);
      return StockPage(items,
          more: asked < iconifyMost &&
              _i(json, ["total"]) >= asked &&
              asked >= q.page * iconifyPageSize);
  }
}

/// polyHavenPage is page [page] of the models [slugs] name, in order, from
/// [catalogue]; with no slugs, the most downloaded first.
StockPage polyHavenPage(Map<String, dynamic> catalogue, List<String>? slugs,
    {int page = 1, StockSource source = StockSource.polyHaven}) {
  var order = slugs ??
      ([...catalogue.keys]..sort((a, b) => _i(catalogue[b], ["download_count"])
          .compareTo(_i(catalogue[a], ["download_count"]))));
  var known = [
    for (var s in order)
      if (catalogue[s] is Map) s
  ];
  var from = (page - 1) * stockPageSize;
  var shown = known.skip(from).take(stockPageSize);
  return StockPage([
    for (var slug in shown)
      StockItem(
        source: source,
        id: slug,
        title: _s(catalogue[slug], ["name"]).isEmpty
            ? slug
            : _s(catalogue[slug], ["name"]),
        author: [
          if (_at<Map>(catalogue[slug], ["authors"]) case var a?) ...a.keys,
        ].join(", "),
        license: "CC0",
        licenseUrl: "https://polyhaven.com/license",
        page: "https://polyhaven.com/a/$slug",
        thumb: _s(catalogue[slug], ["thumbnail_url"]),
        media: source == StockSource.polyHaven
            ? "polyhaven:$slug"
            // A sky as its flat panorama; a texture as its colour map,
            // found when used (see StockClient.polyHavenPicture).
            : _at<num>(catalogue[slug], ["type"]) == 0
                ? "https://cdn.polyhaven.com/asset_img/primary/$slug.png"
                    "?width=2048"
                : "polyhaven-texture:$slug",
      ),
  ], more: from + stockPageSize < known.length);
}

/// stockAgent names the app to the libraries that ask every program to say
/// what it is (Wikimedia, NASA, The Met): the project, never the person.
const stockAgent = "BisonRelay-Canvas/1.0 (https://bisonrelay.org)";
const stockAgentHeaders = {"User-Agent": stockAgent};

/// _spaced is "WoodFloor051" as "Wood floor 051".
String _spaced(String id) => _capital(id
    .replaceAllMapped(RegExp(r"(?<=[a-z])(?=[A-Z0-9])"), (_) => " ")
    .toLowerCase());

/// _plainText is a Commons description's HTML as its words.
String _plainText(String html) => html
    .replaceAll(RegExp(r"<[^>]*>"), "")
    .replaceAll("&amp;", "&")
    .replaceAll("&quot;", '"')
    .replaceAll("&#039;", "'")
    .replaceAll(RegExp(r"\s+"), " ")
    .trim();

/// _untracked is [url] without the campaign tags Commons adds to its links.
String _untracked(String url) {
  var u = Uri.tryParse(url);
  if (u == null || !u.hasQuery) return url;
  var q = {
    for (var e in u.queryParameters.entries)
      if (!e.key.startsWith("utm_")) e.key: e.value
  };
  // Uri.replace keeps the query it is given null for: cut it off instead.
  if (q.isEmpty) return url.substring(0, url.indexOf("?"));
  return u.replace(queryParameters: q).toString();
}

/// _sized is a Commons thumbnail address at [width] across.
String _sized(String thumb, int width) =>
    thumb.replaceFirst(RegExp(r"/\d+px-"), "/${width}px-");

/// _creditFreeLicence is whether a Commons licence asks for no credit.
bool _creditFreeLicence(String name) {
  var n = name.toLowerCase();
  return n.startsWith("cc0") ||
      n.startsWith("public domain") ||
      n.startsWith("pd") ||
      n.contains("no restrictions");
}

StockPage _wikimedia(StockQuery q, Object? json) {
  var pages = _at<Map>(json, ["query", "pages"]) ?? const {};
  var free = q.value("licence") == "free";
  var sorted = [...pages.values]
    ..sort((a, b) => _i(a, ["index"]).compareTo(_i(b, ["index"])));
  var items = <StockItem>[];
  for (var h in sorted) {
    var info = _at<Map>(h, ["imageinfo", 0]);
    if (info == null) continue;
    var meta = _at<Map>(info, ["extmetadata"]) ?? const {};
    String m(String key) => _plainText(_s(meta, [key, "value"]));
    var licence = m("LicenseShortName");
    // Only a file whose licence is read: nothing taken on trust.
    if (licence.isEmpty || (free && !_creditFreeLicence(licence))) continue;
    var thumb = _untracked(_s(info, ["thumburl"]));
    var media = thumb.isNotEmpty ? thumb : _untracked(_s(info, ["url"]));
    if (media.isEmpty) continue;
    var title = m("ObjectName");
    if (title.isEmpty) {
      title = _s(h, ["title"])
          .replaceFirst("File:", "")
          .replaceFirst(RegExp(r"\.\w+$"), "");
    }
    items.add(StockItem(
      source: q.source,
      id: _s(h, ["pageid"]),
      title: title.length > 80 ? "${title.substring(0, 79)}…" : title,
      author: m("Artist"),
      license: licence,
      licenseUrl: _s(meta, ["LicenseUrl", "value"]),
      page: _untracked(_s(info, ["descriptionurl"])),
      thumb: thumb.isEmpty ? media : _sized(thumb, 330),
      media: media,
      width: _i(info, ["thumbwidth"]),
      height: _i(info, ["thumbheight"]),
    ));
  }
  return StockPage(items, more: _at<Object>(json, ["continue"]) != null);
}

/// metPage is a page of The Met's works from [objects], each a work's own
/// answer (v1/objects/id), keeping only those in the public domain with a
/// picture.
StockPage metPage(List<Object?> objects, {required bool more}) => StockPage([
      for (var h in objects)
        if (_at<bool>(h, ["isPublicDomain"]) == true &&
            _s(h, ["primaryImageSmall"]).isNotEmpty)
          StockItem(
            source: StockSource.met,
            id: _s(h, ["objectID"]),
            title: [
              _s(h, ["title"]),
              _s(h, ["objectDate"])
            ].where((x) => x.isNotEmpty).join(", "),
            author: _s(h, ["artistDisplayName"]),
            license: "CC0",
            licenseUrl: "https://www.metmuseum.org/policies/image-resources",
            page: _s(h, ["objectURL"]),
            thumb: _s(h, ["primaryImageSmall"]),
            // The web-sized picture, a thousand or so across: the original
            // is a scan that can run to a hundred megabytes.
            media: _s(h, ["primaryImageSmall"]),
          ),
    ], more: more);
