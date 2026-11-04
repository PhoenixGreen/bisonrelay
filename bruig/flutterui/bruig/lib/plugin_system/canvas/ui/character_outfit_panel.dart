import 'package:bruig/plugin_system/canvas/model/elements/character_outfit.dart';
import 'package:bruig/plugin_system/canvas/ui/character_shape_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_controls.dart';
import 'package:flutter/material.dart';

// character_outfit_panel.dart is the clothes' side of the Character Studio's
// Character base step: the whole outfit's quick changes, and each piece (the
// body's own, none, or one made to fit, with its cut, colour and pattern).

/// CharacterOutfitControls are the settings of [part]: the outfit, or one
/// piece of it (see wearPartId).
class CharacterOutfitControls extends StatelessWidget {
  final String part;
  final CharacterOutfit outfit;
  final ValueChanged<CharacterOutfit> onChanged;

  /// bodyName is whose body it is ("Vivi"); [own] is the pieces that body
  /// comes with.
  final String bodyName;
  final Set<WearSlot> own;

  /// male picks boxers and trousers rather than a bra set and shorts.
  final bool male;

  const CharacterOutfitControls({
    required this.part,
    required this.outfit,
    required this.onChanged,
    required this.bodyName,
    this.own = const {},
    this.male = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final slot = wearSlotOf(part);
    final changed = slot == null
        ? outfit != CharacterOutfit.asDesigned
        : outfit.changed(slot);
    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          StudioPanelHead(
            title: slot?.label ?? "Outfit",
            says: slot == null ? _outfitSays : _says[slot]!,
            resetLabel: "As designed",
            onReset: !changed
                ? null
                : () => onChanged(slot == null
                    ? CharacterOutfit.asDesigned
                    : outfit.wear(slot, CharacterOutfit.defaults[slot]!)),
          ),
          const SizedBox(height: 6),
          if (slot == null) ..._quick() else ..._piece(slot),
        ]);
  }

  static const _outfitSays =
      "Everything at once. Each piece is changed on its own below it. "
      "Underwear stays on under everything; take it off under Underwear.";

  static const Map<WearSlot, String> _says = {
    WearSlot.underwear:
        "Worn under everything, and what is left when the clothes come off.",
    WearSlot.top:
        "The body's own top, or one made to fit: sleeves, hem, neckline, fit "
            "and pattern. Made to fit is made from the body itself, so it fits "
            "whatever shape you give it and moves with it.",
    WearSlot.bottom:
        "Trousers, leggings, shorts or a skirt, made to fit, or the body's own.",
    WearSlot.legwear: "From ankle socks to tights, in any colour and pattern.",
    WearSlot.shoes:
        "Bare feet, the body's own shoes, or a pair made to fit, with their own "
            "sole colour.",
    WearSlot.gloves: "Gloves, long gloves or fingerless.",
  };

  List<Widget> _quick() => [
        const StudioLabel("Quick changes"),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (key, label, next) in [
            ("wearQuick-designed", "As designed", CharacterOutfit.asDesigned),
            (
              "wearQuick-underwear",
              "Underwear only",
              outfit.underwearOnly(male: male)
            ),
            ("wearQuick-swim", "Swimwear", outfit.swimwear(male: male)),
            ("wearQuick-casual", "Casual", outfit.casual(male: male)),
          ])
            StudioPill(
                key: ValueKey(key), label: label, onTap: () => onChanged(next)),
        ]),
      ];

  List<Widget> _piece(WearSlot slot) {
    final g = outfit[slot];
    void set(Garment n) => onChanged(outfit.wear(slot, n));
    final hasOwn = slot.fromBody && own.contains(slot);
    final wearing = switch (g.source) {
      WearSource.own when hasOwn => "own",
      WearSource.made => "made:${g.kind}",
      _ => "none",
    };
    Widget number(String field, String label, double value,
            Garment Function(double) change,
            {required double rest}) =>
        StudioSlider(
          key: ValueKey("wear-${slot.name}-$field"),
          label: label,
          value: value,
          min: 0,
          max: 1,
          rest: rest,
          onChanged: (v) => set(change(v)),
        );
    final d = CharacterOutfit.defaults[slot]!;
    final out = <Widget>[
      StudioPills<String>(
        key: ValueKey("wear-${slot.name}-wearing"),
        id: "wear-${slot.name}-wearing",
        label: hasOwn ? "Wearing: $bodyName's own, or made to fit" : "Wearing",
        value: wearing,
        options: [
          ("none", slot == WearSlot.shoes ? "Bare feet" : "None"),
          if (hasOwn) ("own", "$bodyName's"),
          for (final (k, name) in madeKinds[slot]!) ("made:$k", name),
        ],
        onChanged: (v) => set(switch (v) {
          "own" => g.copyWith(source: WearSource.own),
          "none" => g.copyWith(source: WearSource.none),
          _ => g.copyWith(source: WearSource.made, kind: v.substring(5)),
        }),
      ),
    ];
    if (wearing == "own" && slot != WearSlot.shoes) {
      out.add(const SizedBox(height: 8));
      out.add(number("ownCut", slot == WearSlot.top ? "Sleeves" : "Leg length",
          g.ownCut, (v) => g.copyWith(ownCut: v),
          rest: 1));
    }
    if (!g.made) return out;
    final k = g.kind;
    out.add(const SizedBox(height: 8));
    if (slot == WearSlot.top) {
      if (k != "long" && k != "turtle" && k != "tank") {
        out.add(number(
            "sleeves", "Sleeves", g.sleeves, (v) => g.copyWith(sleeves: v),
            rest: d.sleeves));
      }
      out.add(number("hem", k == "crop" ? "Crop" : "Length", g.hem,
          (v) => g.copyWith(hem: v),
          rest: d.hem));
      out.add(number("fit", "Loose", g.fit, (v) => g.copyWith(fit: v),
          rest: d.fit));
      if (k != "turtle") {
        out.add(StudioPills<String>(
          key: const ValueKey("wear-top-neckline"),
          id: "wear-top-neckline",
          label: "Neckline",
          value: g.neckline,
          options: necklines,
          onChanged: (v) => set(g.copyWith(neckline: v)),
        ));
        out.add(const SizedBox(height: 4));
        out.add(number("depth", "Depth", g.depth, (v) => g.copyWith(depth: v),
            rest: d.depth));
      }
    }
    if (slot == WearSlot.bottom) {
      out.add(number("length", "Length", g.length, (v) => g.copyWith(length: v),
          rest: d.length));
      out.add(number("rise", "Waist height", g.rise, (v) => g.copyWith(rise: v),
          rest: d.rise));
      if (k == "skirt") {
        out.add(number("flare", "Flare", g.flare, (v) => g.copyWith(flare: v),
            rest: d.flare));
        out.add(number(
            "pleats", "Pleats", g.pleats, (v) => g.copyWith(pleats: v),
            rest: d.pleats));
      } else {
        out.add(number("fit", "Loose", g.fit, (v) => g.copyWith(fit: v),
            rest: d.fit));
      }
    }
    out.add(StudioSwatches(
        id: "wear-${slot.name}-colour",
        label: "Colour",
        palette: slot == WearSlot.underwear ? underwearPalette : clothPalette,
        value: g.colour,
        onPick: (c) => set(g.copyWith(colour: c))));
    if (slot == WearSlot.shoes) {
      out.add(StudioSwatches(
          id: "wear-shoes-sole",
          label: "Sole",
          palette: clothPalette,
          value: g.sole,
          onPick: (c) => set(g.copyWith(sole: c))));
      return out;
    }
    out.add(StudioPills<String>(
      key: ValueKey("wear-${slot.name}-pattern"),
      id: "wear-${slot.name}-pattern",
      label: "Pattern",
      value: g.pattern,
      options: wearPatterns,
      onChanged: (v) => set(g.copyWith(pattern: v)),
    ));
    if (g.pattern != "solid") {
      out.add(StudioSwatches(
          id: "wear-${slot.name}-patternColour",
          label: "Pattern colour",
          palette: clothPalette,
          value: g.patternColour,
          onPick: (c) => set(g.copyWith(patternColour: c))));
      out.add(const SizedBox(height: 4));
      out.add(number(
          "scale", "Pattern size", g.scale, (v) => g.copyWith(scale: v),
          rest: d.scale));
    }
    return out;
  }
}
