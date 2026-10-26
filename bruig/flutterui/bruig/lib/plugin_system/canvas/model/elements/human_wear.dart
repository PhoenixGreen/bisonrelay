// human_wear.dart is the hair, brows, shoes and teeth a sculpted body can
// wear: meshes from MakeHuman's free collections, each made to fit any
// body -- every vertex of one pinned to three of the body's -- fetched the
// first time they are wanted.
//
// Both collections are CC0: free to use for anything.

/// WearKind is what a piece is worn as.
enum WearKind { hair, eyebrows, shoes, teeth }

/// wearZips is where each collection is fetched from.
const Map<String, String> wearZips = {
  "system": "https://files.makehumancommunity.org/asset_packs/"
      "makehuman_system_assets/makehuman_system_assets_cc0.zip",
  "hair01": "https://files.makehumancommunity.org/asset_packs/hair01/hair01_cc0.zip",
};

/// WearItem is one piece: its name, what it is, where in which collection,
/// and whether its picture is needed -- hair and brows are cut out of flat
/// cards by theirs; shoes and teeth are coloured whole.
class WearItem {
  final String id;
  final String label;
  final WearKind kind;
  final String zip;
  final String dir;
  final String obj;
  final String mhclo;
  final String mhmat;
  final bool cutOut;
  const WearItem(this.id, this.label, this.kind, this.zip, this.dir, this.obj,
      this.mhclo, this.mhmat,
      {this.cutOut = true});
}

final List<WearItem> wearCatalogue = [
  // Hair.
  WearItem("anime", "Anime", WearKind.hair, "hair01", "hair/learning_anime_hair",
      "animehair.obj", "learning_anime_hair.mhclo", "animehair.mhmat"),
  WearItem("bangs", "Straight bangs", WearKind.hair, "hair01",
      "hair/cortu_straight_bangs", "straight_bangs.obj",
      "cortu_straight_bangs.mhclo", "straight_bangs.mhmat"),
  WearItem("messy", "Short messy", WearKind.hair, "hair01",
      "hair/cortu_short_messy_hair", "short_messy.obj",
      "cortu_short_messy_hair.mhclo", "short_messy.mhmat"),
  WearItem("shaggy", "Shaggy", WearKind.hair, "hair01", "hair/cortu_shaggy_green_hair",
      "shaggy_green.obj", "cortu_shaggy_green_hair.mhclo", "shaggy_green.mhmat"),
  WearItem("bobcut", "Bob cut", WearKind.hair, "hair01", "hair/littleright_bobcut_hair",
      "littleright_hair_bobcut.obj", "littleright_bobcut_hair.mhclo",
      "littleright_hair_bobcut.mhmat"),
  WearItem("swept", "Swept", WearKind.hair, "hair01", "hair/culturalibre_hair_05",
      "hair_05.obj", "culturalibre_hair_05.mhclo", "hair_05.mhmat"),
  WearItem("layered", "Layered", WearKind.hair, "hair01", "hair/culturalibre_hair_06",
      "hair_06.obj", "culturalibre_hair_06.mhclo", "hair_06.mhmat"),
  WearItem("wavy", "Wavy", WearKind.hair, "hair01", "hair/faydaen_hair_1", "hair1.obj",
      "faydaen_hair_1.mhclo", "hair1.mhmat"),
  WearItem("cloud", "Cloud", WearKind.hair, "hair01", "hair/cortu_strawberry_cloud_hair",
      "strawberry_cloud.obj", "cortu_strawberry_cloud_hair.mhclo",
      "strawberry_cloud.mhmat"),
  WearItem("braids", "Two braids", WearKind.hair, "hair01", "hair/elvs_double_mh_braid",
      "double_mhbraid.obj", "elvs_double_mh_braid.mhclo", "double_mhbraid.mhmat"),
  WearItem("bun", "Bun", WearKind.hair, "hair01", "hair/rehmanpolanski_hair_bun_brown",
      "hair_bun_brown.obj", "rehmanpolanski_hair_bun_brown.mhclo",
      "hair_bun_brown.mhmat"),
  WearItem("short1", "Short 1", WearKind.hair, "system", "hair/short01", "short01.obj",
      "short01.mhclo", "short01.mhmat"),
  WearItem("short2", "Short 2", WearKind.hair, "system", "hair/short02", "short02.obj",
      "short02.mhclo", "short02.mhmat"),
  WearItem("short3", "Short 3", WearKind.hair, "system", "hair/short03", "short03.obj",
      "short03.mhclo", "short03.mhmat"),
  WearItem("short4", "Short 4", WearKind.hair, "system", "hair/short04", "short04.obj",
      "short04.mhclo", "short04.mhmat"),
  WearItem("bob1", "Bob", WearKind.hair, "system", "hair/bob01", "bob01.obj",
      "bob01.mhclo", "bob01.mhmat"),
  WearItem("bob2", "Long bob", WearKind.hair, "system", "hair/bob02", "bob02.obj",
      "bob02.mhclo", "bob02.mhmat"),
  WearItem("long", "Long", WearKind.hair, "system", "hair/long01", "long01.obj",
      "long01.mhclo", "long01.mhmat"),
  WearItem("ponytail", "Ponytail", WearKind.hair, "system", "hair/ponytail01",
      "ponytail01.obj", "ponytail01.mhclo", "ponytail01.mhmat"),
  WearItem("braid", "Braid", WearKind.hair, "system", "hair/braid01", "braid01.obj",
      "braid01.mhclo", "braid01.mhmat"),
  WearItem("afro", "Afro", WearKind.hair, "system", "hair/afro01", "afro01.obj",
      "afro01.mhclo", "afro01.mhmat"),

  // Brows.
  for (var (id, n) in [("brow1", "001"), ("brow2", "002"), ("brow3", "004"),
    ("brow4", "006"), ("brow5", "009"), ("brow6", "010")])
    WearItem(id, "Brows ${id.substring(4)}", WearKind.eyebrows, "system",
        "eyebrows/eyebrow$n", "eyebrow$n.obj", "eyebrow$n.mhclo", "eyebrow$n.mhmat"),

  // Shoes, coloured as the character's shoes are -- the socks in them as
  // its socks. MakeHuman's other three are these again.
  WearItem("shoes01", "Lace-ups", WearKind.shoes, "system", "clothes/shoes01",
      "shoes01.obj", "shoes01.mhclo", "shoes01.mhmat",
      cutOut: false),
  WearItem("shoes02", "Trainers", WearKind.shoes, "system", "clothes/shoes02",
      "shoes02.obj", "shoes02.mhclo", "shoes02.mhmat",
      cutOut: false),
  WearItem("shoes03", "Boots", WearKind.shoes, "system", "clothes/shoes03",
      "shoes03.obj", "shoes03.mhclo", "shoes03.mhmat",
      cutOut: false),

  WearItem("teeth", "Teeth", WearKind.teeth, "system", "teeth/teeth_base",
      "teeth_base.obj", "teeth_base.mhclo", "teeth.mhmat",
      cutOut: false),
];

WearItem? wearItem(String id) {
  for (var w in wearCatalogue) {
    if (w.id == id) return w;
  }
  return null;
}

List<WearItem> wearOfKind(WearKind kind) =>
    [for (var w in wearCatalogue) if (w.kind == kind) w];
