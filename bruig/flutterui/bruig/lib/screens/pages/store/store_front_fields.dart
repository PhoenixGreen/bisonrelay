import 'package:bruig/components/text.dart';
import 'package:bruig/models/store.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/theming_system/model/color_hex.dart';
import 'package:bruig/theming_system/model/color_palette.dart';
import 'package:bruig/theming_system/model/markdown_style.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/definitions.dart';

// store_front_fields.dart is what one product looks like on the shop front.
//
// Settings rather than lines in a template. index.tmpl decided all of this
// until now -- a picture, a link, a price, in that order and at whatever
// shape the picture happened to be -- so a seller who wanted their front page
// to line up had to know that a grid cell is as tall as what is in it, and
// then edit a template to do anything about it.
//
// Everything here is one card. What the grid does with the cards is the
// reader's own Markdown guide, which is right: how many across a gallery
// should be depends on the window it is being read in.

/// _shapes are the picture shapes offered by name.
///
/// Named rather than typed, because the useful answers are few and a seller
/// choosing between "square" and "landscape" is making the decision they
/// actually have. The exact numbers are kept alongside so a shop that wants
/// something else can still say so.
class _Shape {
  final String label;
  final int width;
  final int height;
  const _Shape(this.label, this.width, this.height);
}

const _shapes = [
  _Shape("Square — 400 × 400", 400, 400),
  _Shape("Landscape — 600 × 400", 600, 400),
  _Shape("Portrait — 400 × 600", 400, 600),
  _Shape("Wide — 800 × 450", 800, 450),
];

const _crops = {
  "topleft": "Top left",
  "top": "Top",
  "topright": "Top right",
  "left": "Left",
  "center": "Centre",
  "right": "Right",
  "bottom": "Bottom",
};

const _imagePositions = {
  "top": "Above the writing",
  "full": "Behind the whole card",
  "bottom": "Below the writing",
};

const _textPositions = {
  "top": "Top",
  "center": "Centre",
  "bottom": "Bottom",
};

class StoreFrontFields extends StatelessWidget {
  final StoreModel store;
  const StoreFrontFields({super.key, required this.store});

  Future<void> _save(BuildContext context, StoreIndexLayout layout) async {
    var snackbar = SnackBarModel.of(context);
    try {
      await store.setIndexLayout(layout);
    } catch (exception) {
      snackbar.error("Unable to save the shop front: $exception");
    }
  }

  @override
  Widget build(BuildContext context) {
    var layout = store.indexLayout;
    void save(StoreIndexLayout next) => _save(context, next);

    // Which shape is chosen, or null for a shop whose numbers are its own.
    _Shape? shape;
    for (var s in _shapes) {
      if (s.width == layout.imageWidth && s.height == layout.imageHeight) {
        shape = s;
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Txt.L("The pictures on the shop front"),
      const SizedBox(height: 6),
      const Txt.S(
          "A grid cell is as tall as what is in it, so photographs at six "
          "different shapes make a ragged front page. Drawing every picture "
          "at one shape lines the cards up; a picture that is not that shape "
          "is cropped to it.",
          color: TextColor.onSurfaceVariant),
      const SizedBox(height: 6),
      const Txt.S(
          "These settings are read by the shipped front page, which calls "
          "productCard for each product. A shop whose index.tmpl has been "
          "rewritten to draw its own cards is drawing those instead -- keep "
          "the productCard line in it, or use Restore default pages above.",
          color: TextColor.onSurfaceVariant),
      const SizedBox(height: 10),
      _Switch(
        label: "Draw every picture at the same shape",
        value: layout.fixedImage,
        onChanged: (v) => save(layout.copyWith(fixedImage: v)),
      ),
      if (layout.fixedImage) ...[
        _Dropdown<String>(
          label: "Shape",
          value: shape?.label ?? "",
          items: {
            for (var s in _shapes) s.label: s.label,
            if (shape == null)
              "": "Its own — ${layout.imageWidth} × ${layout.imageHeight}",
          },
          onChanged: (v) {
            for (var s in _shapes) {
              if (s.label == v) {
                save(layout.copyWith(
                    imageWidth: s.width, imageHeight: s.height));
              }
            }
          },
        ),
        _Dropdown<String>(
          label: "Crop from",
          value: layout.crop,
          items: _crops,
          onChanged: (v) => save(layout.copyWith(crop: v)),
        ),
        const Txt.S(
            "Which part of a picture is kept when one has to be cropped. A "
            "photograph of a person crops from the top; a photograph of a "
            "room crops from the middle.",
            color: TextColor.onSurfaceVariant),
        const SizedBox(height: 6),
      ],
      const SizedBox(height: 20),
      const Txt.L("How a card is laid out"),
      const SizedBox(height: 10),
      _Dropdown<String>(
        label: "Where the picture goes",
        value: layout.imagePosition,
        items: _imagePositions,
        onChanged: (v) => save(layout.copyWith(imagePosition: v)),
      ),
      if (layout.imagePosition == "full")
        _Dropdown<String>(
          label: "Where the writing sits on it",
          value: layout.textPosition,
          items: _textPositions,
          onChanged: (v) => save(layout.copyWith(textPosition: v)),
        ),
      _Switch(
        label: "A plate behind the writing",
        value: layout.textBackground,
        onChanged: (v) => save(layout.copyWith(textBackground: v)),
      ),
      if (layout.textBackground) ...[
        _ColorField(
          label: "Plate colour",
          value: layout.textColor,
          onChanged: (v) => save(layout.copyWith(textColor: v)),
        ),
        _Number(
          label: "Padding",
          value: layout.textPadding,
          onChanged: (v) => save(layout.copyWith(textPadding: v)),
        ),
        _Number(
          label: "Margin",
          value: layout.textMargin,
          onChanged: (v) => save(layout.copyWith(textMargin: v)),
        ),
        _Number(
          label: "Corner radius",
          value: layout.textRadius,
          onChanged: (v) => save(layout.copyWith(textRadius: v)),
        ),
      ],
      const SizedBox(height: 10),
      _Switch(
        label: "Show the DCR estimate on the shop front",
        value: layout.showDCR,
        onChanged: (v) => save(layout.copyWith(showDCR: v)),
      ),
      const Txt.S(
          "The product's own page always shows both figures -- that is where "
          "somebody is deciding what they will pay. Off, the front page is a "
          "page of prices at a glance.",
          color: TextColor.onSurfaceVariant),
    ]);
  }
}

class _Switch extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _Switch(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Txt.M(label),
        value: value,
        onChanged: onChanged,
      );
}

/// _Dropdown is one choice out of a few.
///
/// A dropdown rather than a dialog of its own for every setting on this page:
/// what is being chosen is one word, and a page of settings that each open a
/// window is a page nobody can read at a glance.
class _Dropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  const _Dropdown(
      {required this.label,
      required this.value,
      required this.items,
      required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: DropdownButtonFormField<T>(
          initialValue: items.containsKey(value) ? value : items.keys.first,
          isDense: true,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          items: [
            for (var entry in items.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      );
}

/// _Number is a length in the units the page markup is written in.
///
/// Saved when the field is left rather than on every keystroke: each save
/// writes the shop's settings file and reloads what it serves, and doing that
/// once per digit typed is a lot of work for a number nobody has finished
/// entering.
class _Number extends StatefulWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  const _Number(
      {required this.label, required this.value, required this.onChanged});

  @override
  State<_Number> createState() => _NumberState();
}

class _NumberState extends State<_Number> {
  late final _ctrl = TextEditingController(text: "${widget.value}");

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _done() {
    var got = int.tryParse(_ctrl.text.trim());
    if (got == null || got == widget.value) {
      _ctrl.text = "${widget.value}";
      return;
    }
    widget.onChanged(got);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: _ctrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: widget.label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _done(),
          onTapOutside: (_) => _done(),
        ),
      );
}

/// _ColorField picks the colour of the plate behind a card's writing.
///
/// Two kinds of answer in one list. The roles at the top are named colours --
/// they follow whatever theme the shop is being read in, which is why a page
/// names a colour rather than giving one. Below them is this client's own
/// palette, and choosing one of those writes the colour itself: that is what
/// a shop with a brand colour wants, and the cost is that it is that colour
/// for every reader, in a dark theme as well as a light one.
/// ColorChoice is one entry in the list of colours a plate may take: a named
/// role, or a colour of this client's palette written out.
@immutable
class ColorChoice {
  /// value is what the shop records -- a role's name, or "#rrggbb".
  final String value;
  final String label;

  /// role is the theme role this stands for, or null for a written colour.
  final MarkdownRole? role;
  const ColorChoice(this.value, this.label, {this.role});
}

/// colorOfHex is a written colour, or null for anything that is not one.
Color? colorOfHex(String value) {
  if (!value.startsWith("#")) return null;
  try {
    return colorFromHex(value);
  } catch (_) {
    return null;
  }
}

/// colorChoices is what the plate colour may be set to: the theme's named
/// roles first, then this client's own palette.
///
/// Two kinds of answer in one list. A role follows whatever theme the shop is
/// read in, which is why a page names a colour rather than giving one. A
/// palette colour is written out, which is what a shop with a brand colour
/// wants, at the cost of being that colour in a dark theme as well.
///
/// Each value appears exactly once. A palette holds a slot per job rather
/// than a colour per slot, so the same colour sits in several of them --
/// three of them are seeded to the master background in a fresh theme -- and
/// two entries offering the same colour is not a choice a seller can make.
/// It is also an outright crash: a dropdown asserts that its value matches
/// exactly one of its items, so the second slot holding the colour the shop
/// had chosen took the whole settings page down with a red box.
List<ColorChoice> colorChoices(List<Color> palette, String held) {
  var out = <ColorChoice>[];
  var seen = <String>{};

  void add(ColorChoice choice) {
    if (seen.add(choice.value)) out.add(choice);
  }

  for (var role in MarkdownRole.values) {
    add(ColorChoice(role.name, role.label, role: role));
  }

  var slots = PaletteSlot.values;
  for (var i = 0; i < palette.length && i < slots.length; i++) {
    add(ColorChoice(colorToHex(palette[i]), paletteSlotLabel(slots[i])));
  }

  // A colour the shop already holds that is not in the list -- one written
  // into the file by hand, or picked from a palette this client no longer
  // has -- is offered as itself rather than silently becoming another one.
  if (held.isNotEmpty && !seen.contains(held)) {
    out.insert(0, ColorChoice(held, held));
  }
  return out;
}

class _ColorField extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  const _ColorField(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var items = [
      for (var choice in colorChoices(theme.activePalette, value))
        DropdownMenuItem(
          value: choice.value,
          child: _swatch(
              choice.role == null
                  ? (colorOfHex(choice.value) ?? theme.colors.surfaceContainer)
                  : theme.markdownRoleColor(choice.role!),
              choice.label),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isDense: true,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        items: items,
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }

  Widget _swatch(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: Colors.black26),
            ),
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      );
}
