// character_look.dart is how a new 3D character is drawn: its lines, its
// fill, its shading and light, its colour, and the finish of the page. 2D and
// 3D are both looks of the same character. What the dials do is in
// render/vrm/vrm_look.dart.

/// CharacterLook is one look. Immutable.
class CharacterLook {
  /// lineStyle is none, clean, pencil or brush.
  final String lineStyle;

  /// width is the outline's, inner how strongly folds and edges inside the
  /// figure are lined; both nought to one.
  final double width, inner;

  /// lineColour is the ink, 0xRRGGBB; lineMode "ink" draws every line in
  /// it, "tinted" in a dark shade of the colour under the line.
  final int lineColour;
  final String lineMode;

  /// fill is painted (the textures as made) or flat (fewer tones), with
  /// [levels] how few.
  final String fill;
  final double levels;

  /// shading is none, cel (two tone), soft or smooth; amount how dark the
  /// shadow; shadowTint neutral, warm, cool or purple.
  final String shading;
  final double amount;
  final String shadowTint;

  /// highlight is none, rim, gloss or both; shine how bright.
  final String highlight;
  final double shine;

  /// light is where the light comes from: left, front, right or top.
  final String light;

  /// The colour of the whole: saturation, brightness and warmth, -1 to 1,
  /// and bands, nought to one, for the tones stepped into bands.
  final double sat, bright, warmth, bands;

  /// render is the page's finish: colour, manga, pencil, watercolour,
  /// painterly, comic or sketch; the numbers after it are each finish's own.
  final String render;
  final double tone, contrast, hatch, wash, bleed, edge, brush, dots, paper;
  final int paperColour;

  const CharacterLook({
    this.lineStyle = "clean",
    this.width = 0.5,
    this.inner = 0.45,
    this.lineColour = 0x1b1a22,
    this.lineMode = "ink",
    this.fill = "painted",
    this.levels = 0.4,
    this.shading = "cel",
    this.amount = 0.5,
    this.shadowTint = "warm",
    this.highlight = "rim",
    this.shine = 0.45,
    this.light = "left",
    this.sat = 0,
    this.bright = 0,
    this.warmth = 0,
    this.bands = 0,
    this.render = "colour",
    this.tone = 0.5,
    this.contrast = 0.5,
    this.hatch = 0.5,
    this.wash = 0.5,
    this.bleed = 0.5,
    this.edge = 0.5,
    this.brush = 0.5,
    this.dots = 0.5,
    this.paper = 0.5,
    this.paperColour = 0xe9e6df,
  });

  /// numbers are the dials, by name, for the page's sliders.
  Map<String, double> get numbers => {
        "width": width,
        "inner": inner,
        "levels": levels,
        "amount": amount,
        "shine": shine,
        "sat": sat,
        "bright": bright,
        "warmth": warmth,
        "bands": bands,
        "tone": tone,
        "contrast": contrast,
        "hatch": hatch,
        "wash": wash,
        "bleed": bleed,
        "edge": edge,
        "brush": brush,
        "dots": dots,
        "paper": paper,
      };

  /// choices are the named settings, by name.
  Map<String, String> get choices => {
        "lineStyle": lineStyle,
        "lineMode": lineMode,
        "fill": fill,
        "shading": shading,
        "shadowTint": shadowTint,
        "highlight": highlight,
        "light": light,
        "render": render,
      };

  /// withNumber and withChoice change one setting by its name.
  CharacterLook withNumber(String name, double v) =>
      _with({...numbers, name: v}, choices, lineColour, paperColour);
  CharacterLook withChoice(String name, String v) =>
      _with(numbers, {...choices, name: v}, lineColour, paperColour);
  CharacterLook withLineColour(int c) =>
      _with(numbers, choices, c, paperColour);
  CharacterLook withPaperColour(int c) =>
      _with(numbers, choices, lineColour, c);

  static CharacterLook _with(
          Map<String, double> n, Map<String, String> c, int line, int paper) =>
      CharacterLook(
        lineStyle: c["lineStyle"]!,
        width: n["width"]!,
        inner: n["inner"]!,
        lineColour: line,
        lineMode: c["lineMode"]!,
        fill: c["fill"]!,
        levels: n["levels"]!,
        shading: c["shading"]!,
        amount: n["amount"]!,
        shadowTint: c["shadowTint"]!,
        highlight: c["highlight"]!,
        shine: n["shine"]!,
        light: c["light"]!,
        sat: n["sat"]!,
        bright: n["bright"]!,
        warmth: n["warmth"]!,
        bands: n["bands"]!,
        render: c["render"]!,
        tone: n["tone"]!,
        contrast: n["contrast"]!,
        hatch: n["hatch"]!,
        wash: n["wash"]!,
        bleed: n["bleed"]!,
        edge: n["edge"]!,
        brush: n["brush"]!,
        dots: n["dots"]!,
        paper: n["paper"]!,
        paperColour: paper,
      );

  Map<String, dynamic> toJson() => {
        ...numbers,
        ...choices,
        "lineColour": lineColour,
        "paperColour": paperColour
      };

  /// fromJson reads what toJson wrote, each setting missing or wrong
  /// taken from [base].
  factory CharacterLook.fromJson(Map<String, dynamic> j,
      [CharacterLook base = const CharacterLook()]) {
    final n = {
      for (final e in base.numbers.entries)
        e.key: j[e.key] is num && (j[e.key] as num).isFinite
            ? (j[e.key] as num).toDouble().clamp(-1.0, 1.0)
            : e.value,
    };
    final c = {
      for (final e in base.choices.entries)
        e.key: (lookOptions[e.key]?.any((o) => o.$1 == j[e.key]) ?? false)
            ? j[e.key] as String
            : e.value,
    };
    int colour(String k, int d) => j[k] is int ? (j[k] as int) & 0xffffff : d;
    return _with(n, c, colour("lineColour", base.lineColour),
        colour("paperColour", base.paperColour));
  }

  @override
  bool operator ==(Object other) =>
      other is CharacterLook &&
      other.lineColour == lineColour &&
      other.paperColour == paperColour &&
      numbers.entries.every((e) => other.numbers[e.key] == e.value) &&
      choices.entries.every((e) => other.choices[e.key] == e.value);

  @override
  int get hashCode => Object.hash(lineColour, paperColour,
      Object.hashAll(numbers.values), Object.hashAll(choices.values));
}

/// lookOptions are each choice's options, with their names.
const Map<String, List<(String, String)>> lookOptions = {
  "lineStyle": [
    ("none", "None"),
    ("clean", "Clean"),
    ("pencil", "Pencil"),
    ("brush", "Brush")
  ],
  "lineMode": [("ink", "One ink"), ("tinted", "Tinted by the colour under it")],
  "fill": [("painted", "Painted"), ("flat", "Flat colour")],
  "shading": [
    ("none", "None"),
    ("cel", "Two tone"),
    ("soft", "Soft"),
    ("smooth", "Smooth 3D")
  ],
  "shadowTint": [
    ("neutral", "Grey"),
    ("warm", "Warm"),
    ("cool", "Cool"),
    ("purple", "Violet")
  ],
  "highlight": [
    ("none", "None"),
    ("rim", "Rim light"),
    ("gloss", "Gloss"),
    ("both", "Both")
  ],
  "light": [
    ("left", "Left"),
    ("front", "Front"),
    ("right", "Right"),
    ("top", "Above")
  ],
  "render": [
    ("colour", "Colour"), ("manga", "Manga"), ("pencil", "Pencil"),
    ("watercolour", "Watercolour"), //
    ("painterly", "Painterly"), ("comic", "Comic"), ("sketch", "Ink sketch"),
  ],
};

/// characterLooks are the looks to start from, by name.
const Map<String, CharacterLook> characterLooks = {
  "Anime cel": CharacterLook(),
  "Clean ink": CharacterLook(
      width: 0.85,
      inner: 0.85,
      lineColour: 0x111111,
      fill: "flat",
      levels: 0.45,
      amount: 0.35,
      shadowTint: "cool",
      highlight: "none",
      shine: 0),
  "Flat": CharacterLook(
      width: 0.35,
      inner: 0.2,
      lineColour: 0x3a2a26,
      fill: "flat",
      levels: 0.25,
      shading: "none",
      amount: 0,
      highlight: "none",
      shine: 0,
      sat: 0.1),
  "Soft 3D": CharacterLook(
      lineStyle: "none",
      width: 0,
      inner: 0,
      shading: "smooth",
      amount: 0.55,
      shadowTint: "cool",
      highlight: "both",
      shine: 0.5),
  "Manga": CharacterLook(
      width: 0.8,
      inner: 0.9,
      lineColour: 0x000000,
      amount: 0.55,
      shadowTint: "neutral",
      highlight: "none",
      shine: 0,
      render: "manga",
      paperColour: 0xf6f4ee),
  "Pencil": CharacterLook(
      lineStyle: "pencil",
      width: 0.55,
      inner: 0.75,
      lineColour: 0x3b3a40,
      shading: "soft",
      shadowTint: "neutral",
      highlight: "none",
      shine: 0,
      render: "pencil",
      paper: 0.6),
  "Watercolour": CharacterLook(
      lineStyle: "pencil",
      width: 0.3,
      inner: 0.35,
      lineColour: 0x5a4a48,
      lineMode: "tinted",
      shading: "soft",
      amount: 0.45,
      highlight: "none",
      shine: 0, //
      render: "watercolour",
      bleed: 0.55,
      edge: 0.6,
      paper: 0.6,
      wash: 0.45,
      paperColour: 0xf3efe6),
  "Painterly": CharacterLook(
      lineStyle: "none",
      width: 0,
      inner: 0.12,
      shading: "smooth",
      amount: 0.6,
      highlight: "both",
      shine: 0.4,
      render: "painterly",
      brush: 0.55,
      paper: 0.3,
      sat: 0.12),
  "Comic": CharacterLook(
      width: 0.95,
      inner: 0.85,
      lineColour: 0x000000,
      fill: "flat",
      levels: 0.2,
      amount: 0.6,
      shadowTint: "neutral",
      highlight: "none",
      shine: 0, //
      render: "comic",
      dots: 0.45,
      contrast: 0.6,
      sat: 0.05,
      paperColour: 0xf7f1e3),
  "Ink sketch": CharacterLook(
      lineStyle: "pencil",
      width: 0.6,
      inner: 0.95,
      lineColour: 0x1e1e24,
      shading: "soft",
      shadowTint: "neutral",
      highlight: "none",
      shine: 0, //
      render: "sketch",
      hatch: 0.6,
      paper: 0.5,
      paperColour: 0xf4f1ea),
  "Pastel": CharacterLook(
      width: 0.4,
      inner: 0.3,
      lineColour: 0x8a7a90,
      lineMode: "tinted",
      shading: "soft",
      amount: 0.3,
      shadowTint: "purple",
      shine: 0.3, //
      sat: -0.35,
      bright: 0.25,
      warmth: 0.1,
      paperColour: 0xf3eef2),
  "Noir": CharacterLook(
      width: 0.7,
      inner: 0.8,
      lineColour: 0x000000,
      amount: 0.8,
      shadowTint: "neutral",
      highlight: "rim",
      shine: 0.8,
      sat: -1,
      bright: -0.08,
      bands: 0.6, //
      paperColour: 0xd8d6d2),
};
