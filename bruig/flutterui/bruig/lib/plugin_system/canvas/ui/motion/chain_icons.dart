import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// chain_icons.dart is the Chain prototype's icons, as they are: each one
// path on a 16-unit square, drawn in a 1.5 line with round ends (or filled,
// where its path starts "F:"). See ChainIcon, and chainIconFor for the
// Material icons the cards were given before, each mapped to its own.

/// chainIcons are the prototype's icons by name, as its core.js has them.
const Map<String, String> chainIcons = {
  "eq": "M1 11 C4 11 5 4 8 4 S12 11 15 11",
  "dyn": "M2 14 L7 9 L14 6 M2 14 H14",
  "space":
      "M8 8m-2 0a2 2 0 1 0 4 0a2 2 0 1 0-4 0 M8 8m-5.5 0a5.5 5.5 0 1 0 11 0a5.5 5.5 0 1 0-11 0",
  "filter": "M1 6 H8 C11 6 11 3.5 12.5 6 L15 13",
  "sine": "M1 8 C3 2 5 2 7 8 S11 14 13 8 15 5 15 5",
  "drive": "M1 14 C6 14 6 2 11 2 H15",
  "note": "M6 13a2 2 0 1 1 0-.1 M8 13 V3 L13 5",
  "bars": "M3 14V9 M6.5 14V4 M10 14V8 M13.5 14V2",
  "plus": "M3 8H13 M8 3V13",
  "lfo": "M1 9 C3 3 5 3 7 9 S11 15 15 6",
  "pads": "F:M2 3h5v4H2z M9 3h5v4H9z M2 9h5v4H2z M9 9h5v4H9z",
  "diamond": "M8 1.5 L14.5 8 L8 14.5 L1.5 8 Z",
  "voice": "M6 2h4v7a2 2 0 0 1-4 0z M3.5 8a4.5 4.5 0 0 0 9 0 M8 12.5V15",
  "clips": "M2 3h12v4H2z M2 9h8v4H2z",
  "motion": "M2 13 C6 13 6 4 13 4 M10 1.5 L13 4 L10 6.5",
  "wig": "M1 8 L3 4 L5 11 L7 5 L9 12 L11 4 L13 10 L15 7",
  "sun":
      "M8 1.5V3 M8 13v1.5 M1.5 8H3 M13 8h1.5 M3.4 3.4l1 1 M11.6 11.6l1 1 M3.4 12.6l1-1 M11.6 4.4l1-1 M8 5.5a2.5 2.5 0 1 1 0 5a2.5 2.5 0 1 1 0-5",
  "frame": "M2 3h12v9H2z M5 15l1.5-3 M11 15l-1.5-3",
  "out": "M2 8H11 M8 4.5L11.5 8L8 11.5 M14 3v10",
  "split": "M2 8H6 M6 8C8 8 8 3 11 3H14 M6 8C8 8 8 13 11 13H14 M6 8H14",
  "macro":
      "M4 4m-2 0a2 2 0 1 0 4 0a2 2 0 1 0-4 0 M12 4m-2 0a2 2 0 1 0 4 0a2 2 0 1 0-4 0 M4 12m-2 0a2 2 0 1 0 4 0a2 2 0 1 0-4 0 M12 12m-2 0a2 2 0 1 0 4 0a2 2 0 1 0-4 0",
  "select": "F:M3 1.5 L3 13 L6.2 10 L8.6 14.6 L10.3 13.8 L7.9 9.3 L12.3 9.3 Z",
  "draw": "M2.5 13.5 L3 10.5 L11 2.5 L13.5 5 L5.5 13 Z M9.5 4 L12 6.5",
  "paint": "M2 14c2.5 0 3.5-1.5 3.5-3 M5.5 11 L12.5 4 L14 5.5 L7 12.5 Z",
  "erase": "M2.5 10 L8 4.5 L13.5 10 L10.5 13 H5.5 Z M9 13 H14.5",
  "knife": "M2 14 L12.5 3.5 L14.5 5.5 L6 13 Z",
  "velo":
      "M3 14V9 M8 14V4 M13 14V7 M3 9m-1.3 0a1.3 1.3 0 1 0 2.6 0a1.3 1.3 0 1 0-2.6 0 M8 4m-1.3 0a1.3 1.3 0 1 0 2.6 0a1.3 1.3 0 1 0-2.6 0 M13 7m-1.3 0a1.3 1.3 0 1 0 2.6 0a1.3 1.3 0 1 0-2.6 0",
  "mute": "M2 6h3l4-3v10l-4-3H2z M11 6l4 4 M15 6l-4 4",
  "glue": "M2.5 5h4.5v6H2.5z M9 5h4.5v6H9z M7 8h2",
  "line":
      "M3 13L13 3 M3 13m-1.3 0a1.3 1.3 0 1 0 2.6 0a1.3 1.3 0 1 0-2.6 0 M13 3m-1.3 0a1.3 1.3 0 1 0 2.6 0a1.3 1.3 0 1 0-2.6 0",
  "curve": "M1.5 12 C5 1 9 15 14.5 4",
  "undo": "M5 3.5L2 6.5L5 9.5 M2 6.5H10a4 4 0 0 1 0 8H7",
  "redo": "M11 3.5L14 6.5L11 9.5 M14 6.5H6a4 4 0 0 0 0 8H9",
  "chord": "M3 4h10 M3 8h10 M3 12h10 M6 4h.01 M9 8h.01 M6 12h.01",
  "scale": "M2 3h12v10H2z M5.5 3v6 M8 3v6 M10.5 3v6",
  "ghost":
      "M3.5 14.5V7a4.5 4.5 0 0 1 9 0v7.5l-1.8-1.5-1.5 1.5L8 13l-1.2 1.5-1.5-1.5z M6.5 7.5h.01 M9.5 7.5h.01",
  "step": "M2 13h3v-3h3V7h3V4h3",
  "dice":
      "M2.5 2.5h11v11h-11z M5.5 5.5h.01 M10.5 10.5h.01 M8 8h.01 M10.5 5.5h.01 M5.5 10.5h.01",
  "warp": "M1.5 13L5 3L8 13L11 3L14.5 13",
  "fade": "M1.5 13.5Q2.5 3 14.5 2.5",
  "reverse": "M14 8H3 M6.5 4.5L3 8l3.5 3.5",
  "slice": "M5 1.5v13 M11 1.5v13 M1.5 8h13",
  "wave": "M1 8L3 5L5 11L7 3L9 13L11 6L13 10L15 8",
  "spectral": "M2 14V10 M5 14V6 M8 14V3 M11 14V7 M14 14V11",
  "env": "M2 12L5.5 5L10 7.5L14 3.5",
  "keys": "M1 3.5h14v9H1z M4.5 3.5v5 M7.5 3.5v5 M11 3.5v5",
  "insp": "M2 3h12v10H2z M10 3v10",
  "more": "M3.5 8h.01 M8 8h.01 M12.5 8h.01",
  "max": "M2 6V2h4 M10 2h4v4 M14 10v4h-4 M6 14H2v-4",
  "min": "M6 2v4H2 M14 6h-4V2 M10 14v-4h4 M2 10h4v4",
  "zoomin":
      "M7 7m-4.5 0a4.5 4.5 0 1 0 9 0a4.5 4.5 0 1 0-9 0 M10.5 10.5L14.5 14.5 M5 7h4 M7 5v4",
  "zoomout":
      "M7 7m-4.5 0a4.5 4.5 0 1 0 9 0a4.5 4.5 0 1 0-9 0 M10.5 10.5L14.5 14.5 M5 7h4",
  "fit": "M1.5 8h13 M4 5.5L1.5 8L4 10.5 M12 5.5L14.5 8L12 10.5",
  "play": "F:M4.5 2.5L13 8L4.5 13.5Z",
  "stop": "F:M4 4h8v8H4z",
  "loop": "M3 6.5h8.5l-2-2 M13 9.5H4.5l2 2",
  "onion":
      "M5.5 8m-3.5 0a3.5 3.5 0 1 0 7 0a3.5 3.5 0 1 0-7 0 M10.5 8m-3.5 0a3.5 3.5 0 1 0 7 0a3.5 3.5 0 1 0-7 0",
  "speed": "M2 12a6 6 0 0 1 12 0 M8 12l3-4",
  "back": "M10 3L5 8l5 5",
  "open": "M9 2h5v5 M14 2L8 8 M12 9v5H2V4h5",
};

/// ChainIcon draws the prototype's icon [name], [size] square, in [color]
/// (the text's, where none is given). Nothing for a name it has not.
class ChainIcon extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;
  const ChainIcon(this.name, {this.size = 15, this.color, super.key});

  @override
  Widget build(BuildContext context) {
    var d = chainIcons[name];
    if (d == null) return SizedBox.square(dimension: size);
    var fill = d.startsWith("F:");
    if (fill) d = d.substring(2);
    var paint = fill
        ? 'fill="#000"'
        : 'fill="none" stroke="#000" stroke-width="1.5" '
            'stroke-linecap="round" stroke-linejoin="round"';
    var colour = color ?? IconTheme.of(context).color ?? Colors.white;
    return SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">'
      '<path d="$d" $paint/></svg>',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(colour, BlendMode.srcIn),
    );
  }
}

/// chainIconFor is the prototype's icon for [icon], one of the Material
/// icons the Chain's cards and tabs were given, or null for one it has no
/// match for.
String? chainIconFor(IconData icon) => switch (icon) {
      Icons.blur_circular => "space",
      Icons.compress => "dyn",
      Icons.filter_alt_outlined => "filter",
      Icons.waves => "sine",
      Icons.whatshot_outlined => "drive",
      Icons.music_note => "note",
      Icons.tune => "plus",
      Icons.insights => "bars",
      Icons.swap_vert => "lfo",
      Icons.grid_view => "pads",
      Icons.piano => "diamond",
      Icons.speaker => "out",
      Icons.equalizer => "eq",
      Icons.call_split => "split",
      Icons.graphic_eq => "wave",
      Icons.timeline => "motion",
      Icons.record_voice_over => "voice",
      Icons.multiline_chart => "note",
      Icons.open_in_full => "max",
      Icons.close_fullscreen => "min",
      Icons.more_horiz => "more",
      Icons.open_in_new => "open",
      _ => null,
    };

/// chainIconOr is the prototype's icon for [icon] where it has one, else
/// [icon] itself.
Widget chainIconOr(IconData icon, {double size = 15, Color? color}) {
  var name = chainIconFor(icon);
  return name == null
      ? Icon(icon, size: size, color: color)
      : ChainIcon(name, size: size, color: color);
}
