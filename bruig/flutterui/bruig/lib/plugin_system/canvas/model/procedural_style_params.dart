import 'package:bruig/plugin_system/canvas/model/procedural_params.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';

// procedural_style_params.dart is each style's own settings. See StyleParam.

/// paramsOf is [style]'s own settings, in the order they are shown.
List<StyleParam> paramsOf(ProceduralStyle style) => switch (style) {
      ProceduralStyle.blockchain => blockchainParams,
      ProceduralStyle.dotGrid => dotGridParams,
      ProceduralStyle.lineGrid => lineGridParams,
      ProceduralStyle.hexGrid => hexGridParams,
      ProceduralStyle.circuit => circuitParams,
      ProceduralStyle.rain => rainParams,
      ProceduralStyle.gradientMesh => meshParams,
      ProceduralStyle.flowWaves => waveParams,
      ProceduralStyle.bokeh => bokehParams,
      ProceduralStyle.starfield => starParams,
      ProceduralStyle.contours => contourParams,
      ProceduralStyle.flames => flameParams,
      ProceduralStyle.halftone => halftoneParams,
      ProceduralStyle.speedLines => speedParams,
      ProceduralStyle.crosshatch => hatchParams,
      ProceduralStyle.splatter => splatParams,
      ProceduralStyle.surface => surfaceParams,
      _ => const [],
    };

/// BlockchainMode is what [ProceduralStyle.blockchain] draws, as the index
/// of its "mode" setting.
abstract final class BlockchainMode {
  static const chain = 0;
  static const network = 1;
  static const ledger = 2;
  static const merkle = 3;
  static const field = 4;
}

const _chain = {
  "mode": [BlockchainMode.chain]
};
const _blocks = {
  "mode": [BlockchainMode.chain, BlockchainMode.merkle]
};

const List<StyleParam> blockchainParams = [
  StyleParam.choice("mode", "Draw",
      ["Chain", "Network", "Ledger", "Merkle tree", "Block field"]),
  // Chain, and the blocks a Merkle tree is made of.
  StyleParam("rows", "Chains",
      min: 1, max: 8, initial: 3, decimals: 0, onlyWhen: _chain),
  StyleParam.choice("blockShape", "Blocks", ["Cube", "Flat", "Rounded"],
      onlyWhen: _blocks),
  StyleParam("blockDepth", "Depth", initial: 0.45, onlyWhen: {
    "mode": [BlockchainMode.chain, BlockchainMode.merkle],
    "blockShape": [0],
  }),
  StyleParam("blockGap", "Gap", max: 3, initial: 0.8, onlyWhen: _chain),
  StyleParam.choice(
      "link", "Links", ["Line", "Double", "Chain links", "Dashed", "Arrows"],
      onlyWhen: _blocks),
  StyleParam.toggle("hashText", "Hashes", initial: true, onlyWhen: _blocks),
  StyleParam.toggle("ripple", "Confirmations", initial: true, onlyWhen: _chain),
  // Network.
  StyleParam.choice("nodeShape", "Nodes", [
    "Dot",
    "Hexagon",
    "Cube",
    "Ring"
  ], onlyWhen: {
    "mode": [BlockchainMode.network]
  }),
  StyleParam("linkReach", "Reach",
      min: 0.05,
      max: 0.5,
      initial: 0.18,
      onlyWhen: {
        "mode": [BlockchainMode.network]
      }),
  StyleParam("hubs", "Hubs", initial: 0.15, onlyWhen: {
    "mode": [BlockchainMode.network]
  }),
  StyleParam("pulses", "Pulses", initial: 0.5, onlyWhen: {
    "mode": [
      BlockchainMode.chain,
      BlockchainMode.network,
      BlockchainMode.merkle
    ]
  }),
  // Ledger.
  StyleParam.choice("ledgerKind", "Lines", ["Hashes", "Transactions", "Blocks"],
      initial: 1,
      onlyWhen: {
        "mode": [BlockchainMode.ledger]
      }),
  StyleParam("columns", "Columns",
      min: 1,
      max: 6,
      initial: 3,
      decimals: 0,
      onlyWhen: {
        "mode": [BlockchainMode.ledger]
      }),
  StyleParam("highlight", "Highlight", initial: 0.15, onlyWhen: {
    "mode": [BlockchainMode.ledger, BlockchainMode.field]
  }),
  // Merkle tree.
  StyleParam("levels", "Levels",
      min: 2,
      max: 7,
      initial: 4,
      decimals: 0,
      onlyWhen: {
        "mode": [BlockchainMode.merkle]
      }),
  StyleParam.choice("treeDir", "Root at", [
    "Top",
    "Bottom"
  ], onlyWhen: {
    "mode": [BlockchainMode.merkle]
  }),
  // Block field.
  StyleParam("fieldHeight", "Height", initial: 0.5, onlyWhen: {
    "mode": [BlockchainMode.field]
  }),
];

// --------------------------------------------------------------------------
// Grids & tech
//
// Every default here is what the style drew before it had settings of its
// own, so a document saved then is the same picture now.
// --------------------------------------------------------------------------

const _dots = {
  "dotKind": [0]
};
const _led = {
  "dotKind": [1]
};

const List<StyleParam> dotGridParams = [
  // LED wall was a style of its own. It is a grid of dots that light up,
  // which is what this is.
  StyleParam.choice("dotKind", "Kind", ["Dots", "LED wall"]),
  StyleParam.choice(
      "dotShape", "Shape", ["Circle", "Square", "Diamond", "Cross"],
      onlyWhen: _dots),
  StyleParam("dotSize", "Dot size",
      min: 0.02, max: 0.5, initial: 0.12, onlyWhen: _dots),
  StyleParam.choice("layout", "Layout", ["Square", "Staggered"],
      onlyWhen: _dots),
  StyleParam.choice("shading", "Light", ["Drifts", "Even", "Ripple", "Sweep"],
      onlyWhen: _dots),
  StyleParam.toggle("unlit", "Unlit cells", onlyWhen: _led),
];

/// GridLayout is [ProceduralStyle.lineGrid]'s "gridLayout" setting.
abstract final class GridLayout {
  static const square = 0;
  static const isometric = 1;
  static const perspective = 2;
}

const _floor = {
  "gridLayout": [GridLayout.perspective]
};

const List<StyleParam> lineGridParams = [
  StyleParam.choice(
      "gridLayout", "Layout", ["Square", "Isometric", "Perspective"]),
  StyleParam("major", "Bold every", min: 0, max: 12, initial: 4, decimals: 0),
  StyleParam("weight", "Weight", min: 0.2, max: 4, initial: 1, decimals: 1),
  StyleParam("horizon", "Horizon",
      min: 0.1, max: 0.9, initial: 0.45, onlyWhen: _floor),
  StyleParam.toggle("sun", "Sun", onlyWhen: _floor),
];

const List<StyleParam> hexGridParams = [
  StyleParam.choice("hexStyle", "Cells", ["Outline", "Tiles", "Raised"]),
  StyleParam("gap", "Gap", max: 0.6, initial: 0),
  StyleParam("weight", "Weight", min: 0.2, max: 4, initial: 1, decimals: 1),
  StyleParam.choice("shading", "Light", ["Scattered", "Drifts", "Ripple"]),
];

const List<StyleParam> circuitParams = [
  StyleParam.choice("corners", "Corners", ["Square", "Angled"]),
  StyleParam("weight", "Weight", min: 0.2, max: 4, initial: 1, decimals: 1),
  StyleParam.choice("pads", "Pads", ["Dots", "Rings", "None"]),
  StyleParam("chips", "Chips", initial: 0),
  StyleParam("pulses", "Pulses", initial: 0),
];

const _rainOnly = {
  "mode": [0]
};

const List<StyleParam> rainParams = [
  // Symbol field was a style of its own: the same characters, scattered
  // rather than falling.
  StyleParam.choice("mode", "Kind", ["Rain", "Field"]),
  StyleParam.choice("glyphFont", "Font", ["System", "Mono", "Serif"]),
  StyleParam("trail", "Trail",
      min: 0.2, max: 3, initial: 1, decimals: 1, onlyWhen: _rainOnly),
  StyleParam("spacing", "Spacing",
      min: 0.6, max: 3, initial: 1, decimals: 1, onlyWhen: _rainOnly),
  StyleParam.choice("direction", "Falls", ["Down", "Up"], onlyWhen: _rainOnly),
  StyleParam.toggle("headGlow", "Glowing heads", onlyWhen: _rainOnly),
];

/// glyphSets is the character sets offered for the symbol styles, by name.
const List<(String, String)> glyphSets = [
  ("Katakana", defaultGlyphs),
  ("Binary", "01"),
  ("Hex", "0123456789ABCDEF"),
  ("Letters", "ABCDEFGHIJKLMNOPQRSTUVWXYZ"),
  ("Crypto", "\u20bf\u039e\u0110\u0141\u20ae\$\u20ac\u00a5\u25ce"),
  (
    "Maths",
    "+\u2212\u00d7\u00f7=\u2260\u2248\u2211\u220f\u221a\u221e\u222b\u2202\u03c0"
  ),
  ("Arrows", "\u2190\u2191\u2192\u2193\u2196\u2197\u2198\u2199"),
  ("Blocks", "\u2580\u2584\u2588\u258c\u2590\u2591\u2592\u2593\u25a0\u25a1"),
];

// --------------------------------------------------------------------------
// Gradient & light
// --------------------------------------------------------------------------

const _meshOnly = {
  "meshKind": [1]
};

const List<StyleParam> meshParams = [
  StyleParam.choice("meshKind", "Kind", ["Blooms", "Mesh", "Aurora"]),
  StyleParam("points", "Points",
      min: 2, max: 9, initial: 5, decimals: 0, onlyWhen: _meshOnly),
  StyleParam("softness", "Softness", initial: 0.4, onlyWhen: _meshOnly),
  StyleParam("warp", "Warp", initial: 0.4, onlyWhen: _meshOnly),
];

const _waves = {
  "waveKind": [1, 2]
};

const List<StyleParam> waveParams = [
  StyleParam.choice("waveKind", "Kind", ["Strands", "Silk", "Lines"]),
  StyleParam("waves", "Waves",
      min: 1, max: 40, initial: 6, decimals: 0, onlyWhen: _waves),
  StyleParam("amplitude", "Height", initial: 0.6, onlyWhen: _waves),
  StyleParam("spread", "Spread", initial: 0.3, onlyWhen: _waves),
  StyleParam("twist", "Twist", initial: 0.3, onlyWhen: _waves),
  StyleParam("thickness", "Thickness", initial: 0.4, onlyWhen: _waves),
];

const List<StyleParam> bokehParams = [
  StyleParam.choice(
      "aperture", "Aperture", ["Round", "Six blades", "Eight blades"]),
  StyleParam("rim", "Rim", initial: 0.5),
  StyleParam.toggle("depth", "Near and far"),
];

const List<StyleParam> starParams = [
  StyleParam("nebula", "Nebula", initial: 0),
  StyleParam("spikes", "Spikes", max: 0.3, initial: 0.04),
  StyleParam("shooting", "Shooting", initial: 0),
  StyleParam.toggle("warp", "Warp speed"),
];

// --------------------------------------------------------------------------
// Organic
// --------------------------------------------------------------------------

const List<StyleParam> contourParams = [
  StyleParam.choice("contourKind", "Kind", ["Lines", "Terrain"]),
  StyleParam("weight", "Weight", min: 0.2, max: 4, initial: 1, decimals: 1),
  StyleParam("major", "Bold every", min: 0, max: 10, initial: 0, decimals: 0),
];

const List<StyleParam> flameParams = [
  StyleParam.choice("flameKind", "Kind", ["Tongues", "Soft fire"]),
  StyleParam("height", "Height", min: 0.3, max: 1.6, initial: 1, decimals: 2),
  StyleParam("embers", "Embers", initial: 0),
];

// --------------------------------------------------------------------------
// Graphic & comic
// --------------------------------------------------------------------------

const List<StyleParam> halftoneParams = [
  StyleParam.choice(
      "dotShape", "Dots", ["Circle", "Square", "Diamond", "Lines"]),
  StyleParam.choice("ink", "Ink", ["Drifts", "Across", "From middle"]),
];

const _aimSet = {
  "aim": [2]
};

const List<StyleParam> speedParams = [
  StyleParam.choice("burstKind", "Kind", ["Burst", "Parallel"]),
  StyleParam.choice("aim", "Centre", [
    "Shuffled",
    "Middle",
    "Set"
  ], onlyWhen: {
    "burstKind": [0]
  }),
  StyleParam("aimX", "X", min: -0.5, max: 1.5, initial: 0.5, onlyWhen: _aimSet),
  StyleParam("aimY", "Y", min: -0.5, max: 1.5, initial: 0.5, onlyWhen: _aimSet),
];

const List<StyleParam> hatchParams = [
  StyleParam.choice("tone", "Tone", ["Even", "Shaded"]),
  StyleParam("wobble", "Wobble", initial: 0),
];

const List<StyleParam> splatParams = [
  StyleParam.choice("splatKind", "Kind", ["Blobs", "Drips", "Spray"]),
];

// --------------------------------------------------------------------------
// Surfaces
// --------------------------------------------------------------------------

const List<StyleParam> surfaceParams = [
  StyleParam.choice("surfaceKind", "Kind", [
    "Paper",
    "Concrete",
    "Wood",
    "Marble",
    "Carbon fibre",
    "Fabric",
    "Leather",
  ]),
  StyleParam("relief", "Relief", initial: 0.5),
  StyleParam("polish", "Polish", initial: 0.3),
  StyleParam.toggle("laid", "Laid lines", onlyWhen: {
    "surfaceKind": [0]
  }),
  StyleParam.toggle("panels", "Formwork", onlyWhen: {
    "surfaceKind": [1]
  }),
  StyleParam.toggle("planks", "Planks", onlyWhen: {
    "surfaceKind": [2]
  }),
  StyleParam.choice("weave", "Weave", [
    "Plain",
    "Twill"
  ], onlyWhen: {
    "surfaceKind": [5]
  }),
];
