import 'package:bruig/components/text.dart';
import 'package:bruig/models/store.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/theming_system/editor/editor_controls.dart';
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
//
// Built out of the theme editor's own controls -- ValueSlider, the wrapping
// equal-column row, the caption and note text -- rather than a page of text
// boxes. Two reasons, and the second is the stronger one:
//
// Every length here is a number somebody wants to nudge and see, which is
// what a slider is for, and this is the app's second page of appearance
// settings: it should look like the first.
//
// And a page of text boxes was quietly losing what was typed into it. Each
// box saves when it loses focus, Flutter delivers that to *every* box on the
// page rather than the one being left, and the boxes here appear and
// disappear as settings are switched on -- so a box could be handed the text
// of the box that had been in its position a moment earlier and save that
// instead. Corners came out set to numbers nobody typed. A slider holds no
// text to be stale, and commits the value it is showing.

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

const _textAligns = {
  "left": "Left",
  "center": "Middle",
  "right": "Right",
};

const _storeNavs = {
  "own": "A bar of the shop's own",
  "links": "In the site's bar, as words",
  "icons": "In the site's bar, as icons",
};

const _textLayouts = {
  "plain": "Title and price",
  "rows": "Title, description, price and a button",
};

/// _standoff is the gap a plate takes when it is told to stop sitting flush
/// against the picture and has no gap of its own to fall back on.
const _standoff = 10;

/// How far each kind of length may be dragged.
///
/// Room enough for the answer somebody wants and no more: these are the
/// dimensions of a card an inch or two wide, and a slider whose useful range
/// is the first twentieth of it is a slider that cannot be set.
const _maxRoom = 40.0;
const _maxRadius = 60.0;
const _maxBorder = 12.0;

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

    var full = layout.imagePosition == "full";
    var rows = layout.textLayout == "rows";

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (store.frontPageMissing.isEmpty)
        const Txt.S(
            "These settings are read by your front page, which asks the shop "
            "what a card looks like. A front page rewritten to draw its own "
            "cards draws those instead.",
            color: TextColor.onSurfaceVariant)
      else
        _Stale(missing: store.frontPageMissing),

      // ---- where the shop's links go ----
      _Group(title: "The shop's links", children: [
        _choice(
          "Where they go",
          value: layout.storeNav,
          items: _storeNavs,
          onChanged: (v) => save(layout.copyWith(storeNav: v)),
        ),
        _note("A shop inside a site has two bars otherwise -- the site's "
            "pages and the shop's -- one above the other, each saying half "
            "of where you can go. In the site's bar they sit at the "
            "right-hand end, the cart wears what is in it, and on a narrow "
            "screen they fold into one menu."),
        if (layout.storeNav != "own") ...[
          _note("A shop hosted without a site, or one whose header has no "
              "bar of links, keeps its own bar whatever this says."),
          _toggle(
            "No background behind the shop's links",
            subtitle: "A row of icons in boxes is a row of buttons, which is "
                "a different thing from a row of icons",
            value: layout.navPlain,
            onChanged: (v) => save(layout.copyWith(navPlain: v)),
          ),
          labelled(
            "Space between the shop's links",
            ValueSlider(
              key: const ValueKey("store-front/nav-gap"),
              // Below nought is the bar's own, which is where this starts:
              // the shop's links sit like the site's until asked otherwise.
              label: (v) => v < 0 ? "The bar's own" : v.round().toString(),
              value: layout.navGap.toDouble().clamp(-1, _maxRoom),
              min: -1,
              max: _maxRoom,
              divisions: _maxRoom.round() + 1,
              numberField: true,
              onCommit: (v) => save(layout.copyWith(navGap: v.round())),
            ),
          ),
          _note("Icons want to sit closer together than words do."),
          responsiveRow([
            labelled(
              "Icon size",
              ValueSlider(
                key: const ValueKey("store-front/nav-size"),
                label: (v) =>
                    v < 0 ? "The ordinary size" : v.round().toString(),
                value: layout.navIconSize.toDouble().clamp(-1, 40),
                min: -1,
                max: 40,
                divisions: 41,
                numberField: true,
                onCommit: (v) => save(layout.copyWith(navIconSize: v.round())),
              ),
            ),
            _lengthCell(
                "nav-inset",
                "Room at the end of the bar",
                layout.navInset,
                _maxRoom,
                (v) => save(layout.copyWith(navInset: v))),
          ]),
          _toggle(
            "Show the Shop link",
            subtitle: "Off suits a site whose own bar already has a link to "
                "the shop -- which is how a visitor got here",
            value: layout.navShop,
            onChanged: (v) => save(layout.copyWith(navShop: v)),
          ),
          _toggle(
            "Show the Admin link",
            subtitle: "Yours alone -- a buyer is never shown it and cannot "
                "reach those pages. The pages stay where they are either "
                "way, so a bookmark keeps working",
            value: layout.navAdmin,
            onChanged: (v) => save(layout.copyWith(navAdmin: v)),
          ),
        ],
      ]),

      // ---- the grid ----
      _Group(title: "The grid", children: [
        _note("How the cards are laid out on the page, rather than what one "
            "of them looks like. Most of what looks like space between two "
            "products is each card's own margin, which is in The border "
            "round the card below -- try that first."),
        responsiveRow([
          labelled(
            "Space between products",
            ValueSlider(
              key: const ValueKey("store-front/grid-gap"),
              // Below nought is the reader's own, which is where this
              // starts: a shop that has asked for nothing is laid out the
              // way its reader lays out a gallery.
              label: (v) => v < 0 ? "The reader's own" : v.round().toString(),
              value: layout.gridGap.toDouble().clamp(-1, _maxRoom),
              min: -1,
              max: _maxRoom,
              divisions: _maxRoom.round() + 1,
              numberField: true,
              onCommit: (v) => save(layout.copyWith(gridGap: v.round())),
            ),
          ),
          _lengthCell("grid-margin", "Space at the sides", layout.gridMargin,
              _maxRoom, (v) => save(layout.copyWith(gridMargin: v))),
        ]),
      ]),

      // ---- the picture ----
      _Group(title: "The picture", children: [
        _toggle(
          "Draw every picture at the same shape",
          subtitle: "A grid cell is as tall as what is in it, so photographs "
              "at six different shapes make a ragged front page. One shape "
              "lines the cards up, cropping what does not fit",
          value: layout.fixedImage,
          onChanged: (v) => save(layout.copyWith(fixedImage: v)),
        ),
        if (layout.fixedImage) ...[
          _choice(
            "Shape",
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
          _choice(
            "Crop from",
            value: layout.crop,
            items: _crops,
            onChanged: (v) => save(layout.copyWith(crop: v)),
          ),
          _note("Which part of a picture is kept when one has to be cropped. "
              "A photograph of a person crops from the top; a photograph of "
              "a room crops from the middle."),
        ],
        _Corners(layout: layout, onChanged: save),
      ]),

      // ---- what the card is made of ----
      _Group(title: "How a card is laid out", children: [
        _choice(
          "Where the picture goes",
          value: layout.imagePosition,
          items: _imagePositions,
          onChanged: (v) => save(layout.copyWith(imagePosition: v)),
        ),
        _choice(
          "What the writing says",
          value: layout.textLayout,
          items: _textLayouts,
          onChanged: (v) => save(layout.copyWith(textLayout: v)),
        ),
        if (rows) ...[
          _note("The three-row card carries the opening of the description on "
              "one line. The product's own page is where the whole of it "
              "belongs."),
          _toggle(
            "Keep a product's name to one line",
            subtitle: "Cut with an ellipsis, the way the description is. Off, "
                "a long name wraps and that card is taller than the rest",
            value: layout.titleOneLine,
            onChanged: (v) => save(layout.copyWith(titleOneLine: v)),
          ),
          _RowGaps(layout: layout, onChanged: save),
        ],
        if (full)
          _choice(
            "Where the writing sits on it",
            value: layout.textPosition,
            items: _textPositions,
            onChanged: (v) => save(layout.copyWith(textPosition: v)),
          ),
        _choice(
          "Which side the writing sits on",
          value: layout.textAlign,
          items: _textAligns,
          onChanged: (v) => save(layout.copyWith(textAlign: v)),
        ),
      ]),

      // ---- the ribbon on a card nobody can buy ----
      _Group(title: "When something cannot be bought", children: [
        _ButtonLabel(
          label: "What the ribbon says",
          value: layout.soldOutLabel,
          onChanged: (v) => save(layout.copyWith(soldOutLabel: v)),
        ),
        _ColorField(
          label: "Ribbon colour",
          value: layout.soldOutColor,
          noneLabel: "The theme's own warning colour",
          onChanged: (v) => save(layout.copyWith(soldOutColor: v)),
        ),
        _note("Pinned to the top right of a card when the shop has run out "
            "of what is on it, or cannot take payment for it — which happens "
            "to a Lightning-only shop whose channels cannot receive what the "
            "thing costs. One label for both, because from the buyer's side "
            "they are the same fact; the product's own page says which."),
        _lengthCell(
          "low-stock-at",
          "Say how many are left at or below",
          layout.lowStockAt,
          20,
          (v) => save(layout.copyWith(lowStockAt: v)),
        ),
        _ColorField(
          label: "Count colour",
          value: layout.lowStockColor,
          noneLabel: "The theme's own warning colour",
          onChanged: (v) => save(layout.copyWith(lowStockColor: v)),
        ),
        _note("At nought, nothing is said. Set to 2, a card with two or one "
            "left carries a \"2 left\" ribbon in the same corner — a nudge "
            "rather than bad news, which is why it has a colour of its own. "
            "A product with plenty, or one the shop does not count, never "
            "carries it."),
        _note("How many of a product there are is set on the product itself, "
            "under Limited number available."),
      ]),

      // ---- the button on the three-row card ----
      if (rows)
        _Group(title: "The button", children: [
          _ButtonLabel(
            value: layout.buttonLabel,
            onChanged: (v) => save(layout.copyWith(buttonLabel: v)),
          ),
          _ColorField(
            label: "Button colour",
            value: layout.buttonColor,
            noneLabel: "The app's own button",
            onChanged: (v) => save(layout.copyWith(buttonColor: v)),
          ),
          _note("Left as the app's own button, it is the primary button of "
              "whatever theme the shop is being read in. Given a colour, it "
              "is that colour for everyone, and the label is set in black or "
              "white -- whichever can be read on it."),
          responsiveRow([
            _lengthCell("button-radius", "Corner radius", layout.buttonRadius,
                _maxRadius, (v) => save(layout.copyWith(buttonRadius: v))),
            _lengthCell("button-padding", "Padding", layout.buttonPadding,
                _maxRoom, (v) => save(layout.copyWith(buttonPadding: v))),
          ]),
        ]),

      // ---- the plate ----
      _Group(title: "The plate behind the writing", children: [
        _toggle(
          "Draw a plate behind the writing",
          subtitle: "A panel of its own colour under the title and the price",
          value: layout.textBackground,
          onChanged: (v) => save(layout.copyWith(textBackground: v)),
        ),
        if (layout.textBackground) ...[
          _ColorField(
            label: "Plate colour",
            value: layout.textColor,
            onChanged: (v) => save(layout.copyWith(textColor: v)),
          ),
          _toggle(
            "Run it the full width of the card",
            value: layout.textFullWidth,
            onChanged: (v) => save(layout.copyWith(textFullWidth: v)),
          ),
          _toggle(
            "Sit it flush with the picture's edge",
            value: layout.textFlush,
            // Turning it off means standing off the edge, and the room it
            // stands off by is the gap below. A shop whose gap is nought
            // would otherwise see nothing happen: the setting saved, and
            // both states drew the same card.
            onChanged: (v) => save(layout.copyWith(
                textFlush: v,
                textMargin: !v && layout.textMargin == 0
                    ? _standoff
                    : layout.textMargin)),
          ),
          _SideLengths(
            name: "plate-padding",
            label: "Padding",
            toggleLabel: "Set the plate's padding side by side",
            base: layout.textPadding,
            sides: [
              layout.textPaddingTop,
              layout.textPaddingRight,
              layout.textPaddingBottom,
              layout.textPaddingLeft,
            ],
            onBase: (v) => save(layout.copyWith(textPadding: v)),
            onSides: (next) => save(layout.copyWith(
                textPaddingTop: next[0],
                textPaddingRight: next[1],
                textPaddingBottom: next[2],
                textPaddingLeft: next[3])),
          ),
          responsiveRow([
            if (!layout.textFlush)
              _lengthCell(
                  "plate-margin",
                  "Gap from the picture",
                  layout.textMargin,
                  _maxRoom,
                  (v) => save(layout.copyWith(textMargin: v))),
            _lengthCell("plate-radius", "Corner radius", layout.textRadius,
                _maxRadius, (v) => save(layout.copyWith(textRadius: v))),
          ]),
          if (layout.textFullWidth && !layout.textFlush)
            _note("The gap is between the plate and the picture, never at "
                "the plate's sides: room there is not the plate standing off "
                "anything, it is the plate not being the full width."),
        ],
      ]),

      // ---- the border ----
      _Group(title: "The border round the card", children: [
        _toggle(
          "Draw a border round each product",
          subtitle: "What makes a card a card on a page with no other "
              "division between one product and the next. Round the whole "
              "card -- the picture and the writing are both inside it",
          value: layout.cardBorder,
          onChanged: (v) => save(layout.copyWith(cardBorder: v)),
        ),
        if (layout.cardBorder) ...[
          _ColorField(
            label: "Border colour",
            value: layout.cardBorderColor,
            onChanged: (v) => save(layout.copyWith(cardBorderColor: v)),
          ),
          responsiveRow([
            _lengthCell("border-width", "Border width", layout.cardBorderWidth,
                _maxBorder, (v) => save(layout.copyWith(cardBorderWidth: v))),
            _lengthCell(
                "border-radius",
                "Corner radius",
                layout.cardBorderRadius,
                _maxRadius,
                (v) => save(layout.copyWith(cardBorderRadius: v))),
            _lengthCell("card-margin", "Margin", layout.cardMargin, _maxRoom,
                (v) => save(layout.copyWith(cardMargin: v))),
          ]),
          _SideLengths(
            name: "card-padding",
            label: "Padding",
            toggleLabel: "Set the card's padding side by side",
            base: layout.cardPadding,
            sides: [
              layout.cardPaddingTop,
              layout.cardPaddingRight,
              layout.cardPaddingBottom,
              layout.cardPaddingLeft,
            ],
            onBase: (v) => save(layout.copyWith(cardPadding: v)),
            onSides: (next) => save(layout.copyWith(
                cardPaddingTop: next[0],
                cardPaddingRight: next[1],
                cardPaddingBottom: next[2],
                cardPaddingLeft: next[3])),
          ),
        ],
      ]),

      // ---- prices ----
      _Group(title: "Prices", children: [
        _toggle(
          "Show the DCR estimate on the shop front",
          subtitle: "The product's own page always shows both figures -- that "
              "is where somebody is deciding what they will pay",
          value: layout.showDCR,
          onChanged: (v) => save(layout.copyWith(showDCR: v)),
        ),
      ]),
    ]);
  }
}

/// _Stale says that this shop's front page cannot see some of these
/// settings, and what to do about it.
///
/// A shop's templates are copied in when the shop is made and are the
/// seller's own from then on, so a front page written before a setting
/// existed goes on drawing what it always drew: the setting saves, shows
/// what it saved, and changes nothing on the page. That is indistinguishable
/// from a broken setting, and it has been reported as one three times.
class _Stale extends StatelessWidget {
  final List<String> missing;
  const _Stale({required this.missing});

  /// _explains what each call is for, in the words the settings use.
  static const _explains = {
    "productCard": "what one product looks like",
    "storeGrid": "the space between products",
    "storePage": "the space at the sides",
  };

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var what = missing.map((c) => _explains[c] ?? c).join(", ");

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colors.surfaceContainerHighest,
        border: Border.all(color: theme.colors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info_outline, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child:
              Txt.S("Your front page was written before some of these settings "
                  "existed, so they cannot reach it: $what. Everything else "
                  "here works. Use Restore default pages above to bring it up "
                  "to date -- your products, orders and pictures are not "
                  "touched."),
        ),
      ]),
    );
  }
}

/// _Group is one titled run of settings, with a line above it.
///
/// The same shape the theme areas use: a page of thirty settings in one list
/// is a page nobody can find anything on, and what separates them here is
/// what part of a card they are about.
class _Group extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Group({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Txt.L(title),
          const SizedBox(height: 6),
          ...children,
        ],
      );
}

/// _toggle is a labelled on/off switch, the theme editor's shape.
Widget _toggle(String title,
        {String? subtitle,
        required bool value,
        required ValueChanged<bool> onChanged}) =>
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Txt.M(title),
      subtitle: subtitle == null
          ? null
          : Txt.S(subtitle, color: TextColor.onSurfaceVariant),
      value: value,
      onChanged: onChanged,
    );

/// _choice is a labelled dropdown over a fixed set of answers, laid out the
/// way the theme areas lay theirs out: the label gives way before the
/// dropdown does, because this pane can be very narrow.
Widget _choice(String label,
        {required String value,
        required Map<String, String> items,
        required ValueChanged<String> onChanged}) =>
    Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        Flexible(child: Txt("$label: ", overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        Flexible(
          child: DropdownButton<String>(
            value: items.containsKey(value) ? value : items.keys.first,
            isExpanded: true,
            items: [
              for (var entry in items.entries)
                DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ]),
    );

Widget _note(String text) =>
    Padding(padding: const EdgeInsets.only(left: 4), child: noteText(text));

/// _lengthCell is one number, dragged or typed, as a cell of a row.
///
/// The theme editor's own slider, which commits when the drag ends rather
/// than once per frame -- each commit here writes the shop's settings file
/// and reloads what it serves.
Widget _lengthCell(String name, String label, int value, double max,
        ValueChanged<int> onChanged) =>
    labelled(
      label,
      ValueSlider(
        // Keyed by what it is, not by where it sits: these come and go as
        // settings are switched on, and a control keyed by position is handed
        // the state of whatever was in that position before it.
        //
        // By its own name rather than its label, because several of them
        // share a label -- the plate, the border and the button each have a
        // corner radius and a padding -- and two widgets under one key in
        // one tree is an outright assertion, not a muddle.
        key: ValueKey("store-front/$name"),
        label: (v) => v.round().toString(),
        value: value.toDouble().clamp(0, max),
        min: 0,
        max: max,
        divisions: max.round(),
        numberField: true,
        onCommit: (v) => onChanged(v.round()),
      ),
    );

/// _SideLengths is one length that can be set all round or side by side.
///
/// The plate's padding and the card's, which are the same question asked
/// twice. One slider while every side agrees, four when they do not: room
/// inside a box is usually the same all round, and the side that wants a
/// different answer is a caption having to clear the bottom of a photograph
/// -- one side rather than four, so the four are there and out of the way.
class _SideLengths extends StatefulWidget {
  /// name keys the sliders, and label names the single one.
  final String name;
  final String label;
  final String toggleLabel;

  /// base is the length every side takes unless it has one of its own, and
  /// sides are those answers -- top, right, bottom, left -- with anything
  /// below nought meaning "the base".
  final int base;
  final List<int> sides;

  final ValueChanged<int> onBase;

  /// onSides is handed all four at once, so switching between the two states
  /// is one save rather than four.
  final ValueChanged<List<int>> onSides;

  const _SideLengths({
    required this.name,
    required this.label,
    required this.toggleLabel,
    required this.base,
    required this.sides,
    required this.onBase,
    required this.onSides,
  });

  @override
  State<_SideLengths> createState() => _SideLengthsState();
}

class _SideLengthsState extends State<_SideLengths> {
  static const _names = ["top", "right", "bottom", "left"];
  static const _labels = ["Top", "Right", "Bottom", "Left"];

  /// _apart is whether the sides are being set one at a time. Held here
  /// rather than saved: it is which controls are showing, not anything about
  /// the shop.
  bool? _apart;

  bool get apart => _apart ?? widget.sides.any((v) => v >= 0);

  /// _at is what one side comes to now: its own answer, or the base.
  int _at(int i) => widget.sides[i] >= 0 ? widget.sides[i] : widget.base;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _toggle(
          widget.toggleLabel,
          value: apart,
          onChanged: (v) {
            setState(() => _apart = v);
            // Going apart, each side starts where it already is, so nothing
            // moves at the moment the controls change. Coming together, the
            // sides give up their own answers -- otherwise one slider would
            // be showing and four would be drawn.
            widget.onSides(v
                ? [for (var i = 0; i < 4; i++) _at(i)]
                : const [-1, -1, -1, -1]);
          },
        ),
        if (!apart)
          _lengthCell(
              widget.name, widget.label, widget.base, _maxRoom, widget.onBase)
        else
          responsiveRow([
            for (var i = 0; i < 4; i++)
              _lengthCell(
                  "${widget.name}-${_names[i]}", _labels[i], _at(i), _maxRoom,
                  (v) {
                var next = [for (var j = 0; j < 4; j++) _at(j)];
                next[i] = v;
                widget.onSides(next);
              }),
          ], minWidth: 120),
      ]);
}

/// _RowGaps is the room between the three-row card's rows.
///
/// One slider while both gaps are the same, two when they are not. They are
/// different joins -- the description belongs to the title above it, while
/// the price and the button are the end of the card -- but most cards want
/// them alike, and nobody should have to set the same number twice to get
/// that.
class _RowGaps extends StatefulWidget {
  final StoreIndexLayout layout;
  final ValueChanged<StoreIndexLayout> onChanged;
  const _RowGaps({required this.layout, required this.onChanged});

  @override
  State<_RowGaps> createState() => _RowGapsState();
}

class _RowGapsState extends State<_RowGaps> {
  /// _apart is whether the two are being set one at a time. Held here rather
  /// than saved: it is which controls are showing, not anything about the
  /// shop.
  bool? _apart;

  bool get apart => _apart ?? widget.layout.rowGap != widget.layout.metaGap;

  @override
  Widget build(BuildContext context) {
    var layout = widget.layout;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _toggle(
        "Set the space above each row separately",
        value: apart,
        onChanged: (v) {
          setState(() => _apart = v);
          // Coming back together, both take the first: leaving them as they
          // were would show one number and draw two.
          if (!v) {
            widget.onChanged(layout.copyWith(metaGap: layout.rowGap));
          }
        },
      ),
      if (!apart)
        _lengthCell("row-gap", "Space between rows", layout.rowGap, _maxRoom,
            (v) => widget.onChanged(layout.copyWith(rowGap: v, metaGap: v)))
      else
        responsiveRow([
          _lengthCell("row-gap", "Above the description", layout.rowGap,
              _maxRoom, (v) => widget.onChanged(layout.copyWith(rowGap: v))),
          _lengthCell("meta-gap", "Above the price", layout.metaGap, _maxRoom,
              (v) => widget.onChanged(layout.copyWith(metaGap: v))),
        ]),
    ]);
  }
}

/// _Corners is how round the picture's corners are.
///
/// One slider while they are the same, four when they are not. A picture at
/// the top of a card is usually rounded at the top and square where the
/// writing meets it, which is the only reason the four exist -- and a seller
/// who wants all four the same should not have to set the same number four
/// times to get it.
class _Corners extends StatefulWidget {
  final StoreIndexLayout layout;
  final ValueChanged<StoreIndexLayout> onChanged;
  const _Corners({required this.layout, required this.onChanged});

  @override
  State<_Corners> createState() => _CornersState();
}

class _CornersState extends State<_Corners> {
  /// _apart is whether the four are being set one by one.
  ///
  /// Held here rather than saved with the settings: it is which controls are
  /// showing, not anything about the shop. A shop whose corners differ is
  /// opened showing the four, which is the state that can draw what it
  /// already has.
  bool? _apart;

  bool get apart {
    var layout = widget.layout;
    return _apart ??
        !(layout.imageCornerTopLeft == layout.imageCornerTopRight &&
            layout.imageCornerTopLeft == layout.imageCornerBottomRight &&
            layout.imageCornerTopLeft == layout.imageCornerBottomLeft);
  }

  @override
  Widget build(BuildContext context) {
    var layout = widget.layout;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _toggle(
        "Set the picture's corners one by one",
        value: apart,
        onChanged: (v) {
          setState(() => _apart = v);
          // Coming back together, all four take the first one: leaving them
          // as they were would show one number and draw four.
          if (!v) widget.onChanged(_all(layout, layout.imageCornerTopLeft));
        },
      ),
      if (!apart)
        _lengthCell("corners", "Picture corners", layout.imageCornerTopLeft,
            _maxRadius, (v) => widget.onChanged(_all(layout, v)))
      else
        responsiveRow([
          _lengthCell(
              "corner-tl",
              "Top left",
              layout.imageCornerTopLeft,
              _maxRadius,
              (v) => widget.onChanged(layout.copyWith(imageCornerTopLeft: v))),
          _lengthCell(
              "corner-tr",
              "Top right",
              layout.imageCornerTopRight,
              _maxRadius,
              (v) => widget.onChanged(layout.copyWith(imageCornerTopRight: v))),
          _lengthCell(
              "corner-br",
              "Bottom right",
              layout.imageCornerBottomRight,
              _maxRadius,
              (v) =>
                  widget.onChanged(layout.copyWith(imageCornerBottomRight: v))),
          _lengthCell(
              "corner-bl",
              "Bottom left",
              layout.imageCornerBottomLeft,
              _maxRadius,
              (v) =>
                  widget.onChanged(layout.copyWith(imageCornerBottomLeft: v))),
        ], minWidth: 120),
    ]);
  }

  StoreIndexLayout _all(StoreIndexLayout layout, int v) => layout.copyWith(
        imageCornerTopLeft: v,
        imageCornerTopRight: v,
        imageCornerBottomRight: v,
        imageCornerBottomLeft: v,
      );
}

/// _ButtonLabel is one of the two settings on this page that are actually a
/// piece of writing: what the three-row card's button says, and what the
/// ribbon on an unavailable card says.
///
/// It saves when it is submitted or left, and follows the shop when the shop
/// changes underneath it -- which is what a box whose value can change
/// elsewhere has to do.
class _ButtonLabel extends StatefulWidget {
  final String value;
  final String label;
  final ValueChanged<String> onChanged;
  const _ButtonLabel({
    required this.value,
    required this.onChanged,
    this.label = "What the button says",
  });

  @override
  State<_ButtonLabel> createState() => _ButtonLabelState();
}

class _ButtonLabelState extends State<_ButtonLabel> {
  late final _ctrl = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void didUpdateWidget(_ButtonLabel old) {
    super.didUpdateWidget(old);
    // Not while it is being typed in: rewriting the box under the cursor
    // moves the cursor.
    if (widget.value != old.value && !_focus.hasFocus) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _done() {
    var got = _ctrl.text.trim();
    if (got.isEmpty || got == widget.value) {
      _ctrl.text = widget.value;
      return;
    }
    widget.onChanged(got);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: TextField(
          controller: _ctrl,
          focusNode: _focus,
          decoration: InputDecoration(
            labelText: widget.label,
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _done(),
          // Only when this box is the one being left. onTapOutside is
          // delivered to every box on the page, and a box that saves on
          // somebody else's tap is a box that saves text nobody finished.
          onTapOutside: (_) {
            if (_focus.hasFocus) _done();
          },
        ),
      );
}

/// ColorChoice is one entry in the list of colours a plate or a border may
/// take: a named role, or a colour of this client's palette written out.
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

/// colorChoices is what a colour setting may be set to: the theme's named
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

/// _ColorField picks one of those, laid out the way the theme areas lay out
/// their own colour dropdowns.
class _ColorField extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  /// noneLabel is what the empty answer is called, for a setting that has
  /// one -- the button, whose empty colour means the app's own button. A
  /// setting with no empty answer leaves this null and is not offered one.
  final String? noneLabel;

  const _ColorField(
      {required this.label,
      required this.value,
      required this.onChanged,
      this.noneLabel});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var items = [
      if (noneLabel != null)
        DropdownMenuItem(
            value: "",
            child: Text(noneLabel!, overflow: TextOverflow.ellipsis)),
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
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        Flexible(child: Txt("$label: ", overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            items: items,
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ]),
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
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      );
}
