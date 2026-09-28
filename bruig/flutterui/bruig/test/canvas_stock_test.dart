import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_client.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_sources.dart';
import 'package:bruig/plugin_system/canvas/ui/stock_import.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_stock_test.dart is the four stock libraries on paper: the request
// each search becomes, where the key goes, and each library's answer read
// back into results. No network -- the shapes are pinned from the libraries'
// own documentation.

void main() {
  group("requests", () {
    test("Pixabay pictures: the key and the chosen filters in the address", () {
      var r = requestFor(
          const StockQuery(StockSource.pixabayPictures,
              text: " red fox ",
              filters: {"image_type": "photo", "colors": "red"},
              page: 2),
          key: "K");
      expect(r.uri.host, "pixabay.com");
      expect(r.uri.path, "/api/");
      var q = r.uri.queryParameters;
      expect(q["key"], "K");
      expect(q["q"], "red fox");
      expect(q["image_type"], "photo");
      expect(q["colors"], "red");
      expect(q.containsKey("orientation"), isFalse,
          reason: "a filter left on Any is not sent");
      expect(q["order"], "popular", reason: "the first option is the default");
      expect(q["safesearch"], "true");
      expect(q["page"], "2");
      expect(r.cacheKey, isNot(contains("key=")),
          reason: "the same search with a new key is the same search");
    });

    test("Pixabay videos go to the video search", () {
      var r = requestFor(const StockQuery(StockSource.pixabayVideos), key: "K");
      expect(r.uri.path, "/api/videos/");
      expect(r.uri.queryParameters.containsKey("q"), isFalse);
    });

    test("Freesound: the key in a header, never the address", () {
      var r = requestFor(
          const StockQuery(StockSource.freesound, text: "door slam", filters: {
            "duration": "[0 TO 5]",
            "license": '"Creative Commons 0"'
          }),
          key: "SECRET");
      expect(r.uri.host, "freesound.org");
      expect(r.uri.path, "/apiv2/search/");
      expect(r.uri.toString(), isNot(contains("SECRET")));
      expect(r.headers["Authorization"], "Token SECRET");
      expect(r.uri.queryParameters["filter"],
          'duration:[0 TO 5] license:"Creative Commons 0"');
      expect(r.uri.queryParameters["fields"], contains("previews"));
    });

    test("Jamendo: popular when there is nothing to be relevant to", () {
      var plain = requestFor(const StockQuery(StockSource.jamendo), key: "C");
      expect(plain.uri.queryParameters["order"], "popularity_total");
      expect(plain.uri.queryParameters["client_id"], "C");
      expect(plain.uri.queryParameters["audioformat"], "mp32");
      var searched = requestFor(
          const StockQuery(StockSource.jamendo,
              text: "piano",
              filters: {"vocalinstrumental": "instrumental"},
              page: 3),
          key: "C");
      var q = searched.uri.queryParameters;
      expect(q.containsKey("order"), isFalse, reason: "relevance");
      expect(q["search"], "piano");
      expect(q["vocalinstrumental"], "instrumental");
      expect(q["offset"], "${2 * stockPageSize}");
    });

    test("Noun Project: public domain by default, signed, paged by token", () {
      var r = requestFor(
          const StockQuery(StockSource.nounProject, text: "dog", cursor: "abc"),
          key: "K");
      expect(r.signed, isTrue);
      expect(r.uri.toString(), isNot(contains("K&")));
      var q = r.uri.queryParameters;
      expect(q["limit_to_public_domain"], "1");
      expect(q["include_svg"], "1");
      expect(q["next_page"], "abc");
      var any = requestFor(
          const StockQuery(StockSource.nounProject,
              text: "dog", filters: {"limit_to_public_domain": "0"}),
          key: "K");
      expect(any.uri.queryParameters.containsKey("limit_to_public_domain"),
          isFalse);
    });
  });

  // Worked out independently, with Python's hmac and urllib, over the same
  // request: a query with the characters Dart's encoder leaves alone and
  // OAuth does not.
  test("OAuth 1.0a signing matches an independent signature", () {
    var uri = Uri.https("api.thenounproject.com", "/v2/icon",
        {"query": "dog's (best) friend!", "limit": "30"});
    var header =
        oauthHeader(uri, "ck", "cs", nonce: "abc123", timestamp: 1700000000);
    expect(header, startsWith("OAuth "));
    expect(header,
        contains('oauth_signature="${pct("5a4JEuKU+RUdkplzqiiABEr3zhQ=")}"'));
    expect(header, contains('oauth_signature_method="HMAC-SHA1"'));
    expect(pct("a b!*'()~"), "a%20b%21%2A%27%28%29~");
  });

  group("answers", () {
    test("Pixabay pictures, named from their tags", () {
      var page = parseStock(const StockQuery(StockSource.pixabayPictures), {
        "totalHits": 45,
        "hits": [
          {
            "id": 195893,
            "pageURL": "https://pixabay.com/en/blossom-195893/",
            "tags": "blossom, bloom, flower",
            "previewURL": "https://cdn.pixabay.com/p_150.jpg",
            "webformatURL": "https://pixabay.com/w_640.jpg",
            "largeImageURL": "https://pixabay.com/l_1280.jpg",
            "imageWidth": 4000,
            "imageHeight": 2250,
            "user": "Josch13",
          },
          {"id": 2, "tags": "", "previewURL": "x"}, // nothing to fetch
        ],
      });
      var item = page.items.single;
      expect(item.title, "Blossom bloom flower");
      expect(item.media, "https://pixabay.com/l_1280.jpg");
      expect(item.thumb, "https://cdn.pixabay.com/p_150.jpg");
      expect(item.author, "Josch13");
      expect((item.width, item.height), (4000, 2250));
      expect(item.kind, AssetKind.picture);
      expect(page.more, isTrue, reason: "30 of 45");
    });

    test("Pixabay videos: medium where there is one, and a thumbnail", () {
      var page = parseStock(const StockQuery(StockSource.pixabayVideos), {
        "totalHits": 1,
        "hits": [
          {
            "id": 125,
            "tags": "flowers",
            "duration": 12,
            "user": "Coverr",
            "videos": {
              "large": {"url": "", "width": 0, "height": 0},
              "medium": {
                "url": "https://cdn.pixabay.com/m.mp4",
                "width": 1280,
                "height": 720,
                "thumbnail": "https://cdn.pixabay.com/m.jpg"
              },
              "tiny": {
                "url": "https://cdn.pixabay.com/t.mp4",
                "thumbnail": "https://cdn.pixabay.com/t.jpg"
              },
            },
          },
        ],
      });
      var v = page.items.single;
      expect(v.media, "https://cdn.pixabay.com/m.mp4");
      expect(v.thumb, "https://cdn.pixabay.com/t.jpg");
      expect((v.width, v.height, v.length), (1280, 720, 12.0));
      expect(page.more, isFalse);
    });

    test("Noun Project icons: the drawing, and who drew it", () {
      var page =
          parseStock(const StockQuery(StockSource.nounProject, text: "dog"), {
        "icons": [
          {
            "id": 1,
            "term": "dog",
            "thumbnail_url": "https://static.thenounproject.com/t.png",
            "icon_url": "https://static.thenounproject.com/i.svg",
            "license_description": "public-domain",
            "permalink": "/icon/dog-1/",
            "creator": {"name": "Ann"},
          },
        ],
        "next_page": "tok",
      });
      var icon = page.items.single;
      expect(icon.title, "Dog");
      expect(icon.media, endsWith(".svg"));
      expect(icon.thumb, endsWith(".png"));
      expect(icon.license, "Public domain");
      expect(icon.page, "https://thenounproject.com/icon/dog-1/");
      expect((page.more, page.cursor), (true, "tok"));
    });

    test("Freesound: the preview is what is fetched, with its licence", () {
      var page = parseStock(const StockQuery(StockSource.freesound), {
        "count": 40,
        "next": "https://freesound.org/apiv2/search/?page=2",
        "results": [
          {
            "id": 7,
            "name": "door-slam.wav",
            "username": "bob",
            "license": "http://creativecommons.org/licenses/by/4.0/",
            "url": "https://freesound.org/people/bob/sounds/7/",
            "duration": 1.5,
            "previews": {
              "preview-hq-mp3": "https://cdn.freesound.org/7-hq.mp3",
              "preview-lq-mp3": "https://cdn.freesound.org/7-lq.mp3",
            },
            "images": {"waveform_m": "https://cdn.freesound.org/7.png"},
          },
        ],
      });
      var s = page.items.single;
      expect(s.title, "door-slam", reason: "the file extension is not a name");
      expect(s.media, "https://cdn.freesound.org/7-hq.mp3");
      expect(s.preview, "https://cdn.freesound.org/7-lq.mp3");
      expect(s.license, "CC BY 4.0");
      expect(s.kind, AssetKind.audio);
      expect(page.more, isTrue);
    });

    test("Jamendo: the download where it is allowed, the stream otherwise", () {
      Map<String, dynamic> track(int id, bool allowed) => {
            "id": "$id",
            "name": "Track $id",
            "artist_name": "Band",
            "duration": 200,
            "audio": "https://prod.jamendo.com/stream/$id",
            "audiodownload": "https://prod.jamendo.com/download/$id",
            "audiodownload_allowed": allowed,
            "license_ccurl":
                "http://creativecommons.org/licenses/by-nc-sa/3.0/",
            "image": "https://img.jamendo.com/$id.jpg",
          };
      var page = parseStock(const StockQuery(StockSource.jamendo), {
        "headers": {"status": "success", "results_count": 2},
        "results": [track(1, true), track(2, false)],
      });
      expect(page.items[0].media, contains("/download/"));
      expect(page.items[1].media, contains("/stream/"));
      expect(page.items[0].preview, contains("/stream/"));
      expect(page.items[0].license, "CC BY-NC-SA 3.0");
      expect(page.more, isFalse);

      var refused = parseStock(const StockQuery(StockSource.jamendo), {
        "headers": {"status": "failed", "error_message": "bad client id"},
      });
      expect(refused.problem, "Jamendo: bad client id");
    });
  });

  test("licence names", () {
    expect(licenceName("http://creativecommons.org/publicdomain/zero/1.0/"),
        "CC0");
    expect(licenceName("https://creativecommons.org/licenses/by/3.0/"),
        "CC BY 3.0");
    expect(licenceName("Attribution NonCommercial"), "CC BY-NC");
    expect(licenceName(""), "");
  });

  test("a result's credit, and an asset keeps its own", () {
    const item = StockItem(
        source: StockSource.freesound,
        id: "7",
        title: "Door slam",
        author: "bob",
        license: "CC BY 4.0",
        media: "m");
    expect(item.credit, "Door slam by bob from Freesound (CC BY 4.0)");

    var asset = LibraryAsset(
        id: "0123456789abcdef.mp3",
        kind: AssetKind.audio,
        name: "Door slam",
        added: DateTime(2026),
        author: "bob",
        license: "CC BY 4.0",
        origin: "https://freesound.org/s/7/",
        from: "Freesound");
    var back = LibraryAsset.fromJson(asset.toJson())!;
    expect([back.author, back.license, back.origin, back.from],
        ["bob", "CC BY 4.0", "https://freesound.org/s/7/", "Freesound"]);
    expect(back.credit, "Door slam by bob from Freesound (CC BY 4.0)");
    expect(back.copyWith(name: "Slam").author, "bob",
        reason: "a rename keeps the credit");
  });

  test("file names for a title", () {
    expect(fileNameFor("Door / slam: take 2!"), "Door slam take 2");
    expect(fileNameFor("   "), "stock");
  });
}
