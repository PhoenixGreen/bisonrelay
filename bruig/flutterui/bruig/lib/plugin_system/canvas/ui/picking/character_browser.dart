import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/drawn_characters.dart';
import 'package:bruig/plugin_system/canvas/presets/drawn_styles.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/asset_elements.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// character_browser.dart is the Stock panel's drawn characters: a style, a
// dozen of its characters to choose from (shuffled again on asking), and the
// one chosen made over part by part and colour by colour before it goes on
// the canvas as a drawing. Made on this computer from CC0 drawings; nothing
// is fetched.

/// _shown is the style last shown, and the shuffle it was at, for the run.
String _style = "open-peeps";
int _shuffle = 1;

class CharacterBrowser extends StatefulWidget {
  final CanvasController controller;
  const CharacterBrowser({required this.controller, super.key});

  @override
  State<CharacterBrowser> createState() => CharacterBrowserState();
}

class CharacterBrowserState extends State<CharacterBrowser> {
  Map<String, DrawnStyle> _styles = const {};

  /// _making is the character being made over, or null while choosing.
  DrawnCharacter? _making;
  String _said = "";

  @override
  void initState() {
    super.initState();
    DrawnStyles.load().then((styles) {
      if (mounted) setState(() => _styles = styles);
    });
  }

  DrawnStyle? get _current => _styles[_style] ?? _styles.values.firstOrNull;

  List<DrawnCharacter> _choices(DrawnStyle style) {
    var random = math.Random(_shuffle * 7919 + style.id.hashCode);
    return [for (var i = 0; i < 12; i++) randomCharacter(style, random)];
  }

  Future<void> _add(DrawnStyle style, DrawnCharacter character) async {
    var c = widget.controller;
    var id =
        await keepDrawnCharacter(style, character, "${style.title} character");
    if (!mounted) return;
    if (id == null) {
      setState(() => _said = "That character could not be kept.");
      return;
    }
    var asset =
        (await CanvasLibrary.list()).where((a) => a.id == id).firstOrNull;
    if (asset == null || !mounted) return;
    c.beginInteraction();
    c.addElement(elementForAsset(asset, c.document));
    c.endInteraction();
    setState(() => _said = "Added, and kept with your drawings.");
  }

  @override
  Widget build(BuildContext context) {
    var style = _current;
    if (style == null) {
      return const CanvasStatus("Loading the characters…");
    }
    var making = _making;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CanvasWrap(children: [
        CanvasDropdown<String>(
          key: const ValueKey("characterStyle"),
          label: "Style",
          value: style.id,
          width: 180,
          options: [
            for (var s in _styles.values) (s.id, "${s.title}, ${s.creator}"),
          ],
          onChanged: (id) => setState(() {
            _style = id;
            _making = null;
          }),
        ),
        CanvasTextButton(
          key: const ValueKey("characterShuffle"),
          label: "Shuffle",
          icon: Icons.shuffle,
          onPressed: () => setState(() {
            _shuffle++;
            if (_making != null) {
              _making = randomCharacter(
                  style, math.Random(_shuffle * 104729 + style.id.hashCode));
            }
          }),
        ),
      ]),
      CanvasStatus("${style.title}, drawn by ${style.creator}: "
          "${style.licence} -- free for anything, no credit needed."),
      if (making == null)
        CanvasTiles<int>(
          key: const ValueKey("characterTiles"),
          label: "Choose one to make over",
          columns: 3,
          previewHeight: 96,
          tiles: [
            for (var (i, ch) in _choices(style).indexed)
              CanvasTile(i, "",
                  preview: (_) => _CharacterPicture(style: style, of: ch)),
          ],
          selected: (_) => false,
          keyOf: (i) => "character-$i",
          onPick: (i) => setState(() => _making = _choices(style)[i]),
        )
      else
        ..._makeOver(style, making),
      if (_said.isNotEmpty) CanvasStatus(_said),
    ]);
  }

  List<Widget> _makeOver(DrawnStyle style, DrawnCharacter making) => [
        SizedBox(
            height: 180,
            child: _CharacterPicture(
                key: const ValueKey("characterMaking"),
                style: style,
                of: making)),
        CanvasControlGroup(
          label: "Parts",
          rule: false,
          children: [
            for (var g in style.groups)
              CanvasDropdown<String>(
                key: ValueKey("characterPart-$g"),
                label: _words(g),
                value: making.parts[g] ?? "",
                width: 150,
                options: [
                  if (style.optional(g)) ("", "None"),
                  for (var v in style.choices(g)) (v, _words(v)),
                ],
                onChanged: (v) => setState(
                    () => _making = making.withPart(g, v.isEmpty ? null : v)),
              ),
          ],
        ),
        if (style.colours.any((c) => style.palette(c).length > 1))
          CanvasControlGroup(
            label: "Colours",
            rule: false,
            children: [
              for (var c in style.colours)
                if (style.palette(c).length > 1)
                  CanvasDropdown<String>(
                    key: ValueKey("characterColour-$c"),
                    label: _words(c),
                    value: making.colours[c] ?? style.palette(c).first,
                    width: 150,
                    options: [
                      for (var hex in style.palette(c))
                        (hex, hex == "transparent" ? "None" : "#$hex"),
                    ],
                    onChanged: (hex) =>
                        setState(() => _making = making.withColour(c, hex)),
                  ),
            ],
          ),
        CanvasWrap(children: [
          CanvasTextButton(
            key: const ValueKey("characterAdd"),
            label: "Add to the canvas",
            icon: Icons.add,
            primary: true,
            onPressed: () => _add(style, making),
          ),
          CanvasTextButton(
            key: const ValueKey("characterBack"),
            label: "Back to the choice",
            icon: Icons.grid_view,
            onPressed: () => setState(() => _making = null),
          ),
        ]),
      ];
}

/// _words is a part's or a choice's name in words: "facialHair" is "Facial
/// hair", "variant04" "Variant 04".
String _words(String id) {
  var spaced = id
      .replaceAllMapped(RegExp(r"(?<=[a-z])(?=[A-Z0-9])"), (_) => " ")
      .toLowerCase();
  return spaced.isEmpty ? id : spaced[0].toUpperCase() + spaced.substring(1);
}

class _CharacterPicture extends StatelessWidget {
  final DrawnStyle style;
  final DrawnCharacter of;
  const _CharacterPicture({required this.style, required this.of, super.key});

  @override
  Widget build(BuildContext context) => SvgPicture.string(drawnSvg(style, of),
      fit: BoxFit.contain, allowDrawingOutsideViewBox: false);
}
