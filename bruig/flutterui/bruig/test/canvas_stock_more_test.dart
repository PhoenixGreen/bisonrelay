import 'package:bruig/plugin_system/canvas/storage/stock/stock_sources.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_stock_more_test.dart covers the libraries added for backgrounds,
// landscapes and illustration -- Wikimedia Commons, Pexels, The Met, NASA,
// ambientCG and Poly Haven's skies and textures -- read from answers shaped
// as each answered when this was written (November 2026).

void main() {
  test("which need a key, and which need words", () {
    expect(StockSource.pexels.needsKey, isTrue);
    for (var s in [
      StockSource.wikimedia,
      StockSource.met,
      StockSource.nasa,
      StockSource.ambientCG,
      StockSource.polyHavenPictures,
    ]) {
      expect(s.needsKey, isFalse, reason: s.name);
      expect(s.terms, isNotEmpty);
    }
    expect(StockSource.wikimedia.needsText, isTrue);
    expect(StockSource.pexels.needsText, isFalse, reason: "curated");
    expect(StockSource.nasa.terms, contains("cryptocurrency"));
  });

  test("the keyless libraries are asked with the app's name, not a person's",
      () {
    for (var s in [StockSource.wikimedia, StockSource.met, StockSource.nasa]) {
      var r = requestFor(StockQuery(s, text: "sky"), key: "");
      expect(r.headers["User-Agent"], stockAgent, reason: s.name);
      expect(stockAgent, isNot(contains("@")));
    }
    var pexels = requestFor(const StockQuery(StockSource.pexels), key: "k");
    expect(pexels.uri.path, "/v1/curated");
    expect(pexels.headers["Authorization"], "k");
    expect(pexels.cacheKey, isNot(contains("k&")));
    var search = requestFor(
        const StockQuery(StockSource.pexels,
            text: "mountain", filters: {"orientation": "landscape"}),
        key: "k");
    expect(search.uri.path, "/v1/search");
    expect(search.uri.queryParameters["orientation"], "landscape");
    var commons = requestFor(
        const StockQuery(StockSource.wikimedia,
            text: "castle", filters: {"filetype": "drawing"}),
        key: "");
    expect(commons.uri.queryParameters["gsrsearch"], "castle filetype:drawing");
  });

  test("Commons: only files whose licence is read, without tracking tags", () {
    Map<String, dynamic> page(int index, String licence, {String? url}) => {
          "pageid": index,
          "index": index,
          "title": "File:Castle $index.jpg",
          "imageinfo": [
            {
              "width": 4000,
              "height": 3000,
              "thumbwidth": 1600,
              "thumbheight": 1200,
              "thumburl": "https://upload.wikimedia.org/wikipedia/commons/thumb/"
                  "a/ab/Castle_$index.jpg/1920px-Castle_$index.jpg"
                  "?utm_source=commons.wikimedia.org&utm_campaign=imageinfo",
              "url": "https://upload.wikimedia.org/x.jpg",
              "descriptionurl":
                  "https://commons.wikimedia.org/wiki/File:Castle_$index.jpg",
              "extmetadata": {
                if (licence.isNotEmpty) "LicenseShortName": {"value": licence},
                "Artist": {
                  "value": '<a href="//commons.wikimedia.org/wiki/User:A">'
                      'Ann &amp; Co</a>'
                },
                "ObjectName": {"value": "Castle $index"},
              },
            }
          ],
        };
    var json = {
      "continue": {"gsroffset": 30},
      "query": {
        "pages": {
          "2": page(2, "CC BY-SA 4.0"),
          "1": page(1, "Public domain"),
          "3": page(3, ""),
        }
      }
    };
    var any = parseStock(
        const StockQuery(StockSource.wikimedia,
            text: "castle", filters: {"licence": ""}),
        json);
    expect([for (var i in any.items) i.title], ["Castle 1", "Castle 2"],
        reason: "in search order; the file with no licence left out");
    expect(any.items[1].author, "Ann & Co");
    expect(any.items[1].license, "CC BY-SA 4.0");
    expect(any.items.first.media, isNot(contains("utm_")));
    expect(any.items.first.thumb, contains("/330px-"));
    expect(any.more, isTrue);

    var free = parseStock(
        const StockQuery(StockSource.wikimedia, text: "castle"), json);
    expect([for (var i in free.items) i.title], ["Castle 1"],
        reason: "no credit needed is the usual choice");
  });

  test("Pexels, NASA and ambientCG answers are read", () {
    var pexels = parseStock(const StockQuery(StockSource.pexels), {
      "next_page": "https://api.pexels.com/v1/curated?page=2",
      "photos": [
        {
          "id": 7,
          "alt": "lake under a mountain",
          "photographer": "Jo",
          "url": "https://www.pexels.com/photo/7/",
          "width": 6000,
          "height": 4000,
          "src": {
            "large2x": "https://images.pexels.com/7-l.jpg",
            "medium": "https://images.pexels.com/7-m.jpg",
            "original": "https://images.pexels.com/7.jpg"
          }
        }
      ]
    });
    expect(pexels.items.single.title, "Lake under a mountain");
    expect(pexels.items.single.media, endsWith("7-l.jpg"));
    expect(pexels.items.single.credit, contains("by Jo from Pexels"));

    var nasa = parseStock(const StockQuery(StockSource.nasa, text: "nebula"), {
      "collection": {
        "items": [
          {
            "data": [
              {
                "nasa_id": "PIA14417",
                "title": "Weighing in on the Dumbbell Nebula",
                "center": "JPL",
                "secondary_creator": "NASA/JPL-Caltech"
              }
            ],
            "links": [
              {"href": "https://images-assets.nasa.gov/image/P/P~medium.jpg"},
              {"href": "https://images-assets.nasa.gov/image/P/P~thumb.jpg"},
              {"href": "https://images-assets.nasa.gov/image/P/P~orig.jpg"},
            ]
          }
        ],
        "links": [
          {"rel": "next", "href": "x"}
        ]
      }
    });
    var n = nasa.items.single;
    expect(n.media, endsWith("~medium.jpg"), reason: "not the original");
    expect(n.thumb, endsWith("~thumb.jpg"));
    expect(n.page, "https://images.nasa.gov/details/PIA14417");
    expect(nasa.more, isTrue);

    var acg = parseStock(const StockQuery(StockSource.ambientCG), {
      "nextPageHttp": "https://ambientcg.com/api/v3/assets?offset=30",
      "assets": [
        {"id": "WoodFloor051"},
        {"id": "../evil"},
      ]
    });
    expect(acg.items.single.title, "Wood floor 051");
    expect(acg.items.single.media, endsWith("WoodFloor051_SQ_Color.jpg"));
    expect(acg.items.single.license, "CC0");
  });

  test("The Met: only public-domain works with a picture", () {
    var page = metPage([
      {
        "objectID": 1,
        "title": "Landscape",
        "objectDate": "1489",
        "artistDisplayName": "Perugino",
        "isPublicDomain": true,
        "primaryImageSmall": "https://images.metmuseum.org/web-large/1.jpg",
        "objectURL": "https://www.metmuseum.org/art/collection/search/1",
      },
      {"objectID": 2, "isPublicDomain": false, "primaryImageSmall": "x"},
      {"objectID": 3, "isPublicDomain": true, "primaryImageSmall": ""},
    ], more: true);
    expect(page.items.single.title, "Landscape, 1489");
    expect(page.items.single.license, "CC0");
  });

  test("Poly Haven's skies are panoramas, its textures colour maps", () {
    var page = polyHavenPage({
      "sky": {"name": "Partly cloudy", "type": 0, "thumbnail_url": "t"},
      "brick": {"name": "Brick wall", "type": 1, "thumbnail_url": "t"},
    }, null, source: StockSource.polyHavenPictures);
    var byId = {for (var i in page.items) i.id: i};
    expect(byId["sky"]!.media, contains("asset_img/primary/sky.png"));
    expect(byId["brick"]!.media, "polyhaven-texture:brick");
    expect(byId["sky"]!.source, StockSource.polyHavenPictures);
  });
}
