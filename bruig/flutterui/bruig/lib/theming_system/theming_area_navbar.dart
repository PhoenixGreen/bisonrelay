import 'package:bruig/theming_system/theme_area.dart';
import 'package:bruig/theming_system/theming_areas_section.dart';
import 'package:flutter/material.dart';

// theming_area_navbar.dart is the "Navigation Bar" area's own settings. Its
// width/padding/margin aren't editable -- the third-party sidebarx package
// composes its own fixed layout and animates off specific width values (see
// theming_areas_section.dart).
List<Widget> navBarAreaEditor(AreaEditorContext ctx) => [
      ctx.toggle(
        "Show logo",
        subtitle: "Displays the Bison Relay logo at the top of the nav bar -- "
            "useful when the header is set to Content or None",
        value: ctx.style.showLogo,
        onChanged: (v) => ctx.setStyle((s) => s.copyWith(showLogo: v)),
      ),
      if (ctx.style.showLogo) ...[
        ctx.slider("logoSize", ctx.style.logoSize ?? 32,
            label: (v) => "Logo size: ${v.toStringAsFixed(1)}",
            min: 16,
            max: 80,
            onCommit: (v) => ctx.setStyle((s) => s.copyWith(logoSize: v))),
        ctx.choice<ContentAlign>(
          "Logo position",
          value: ctx.style.logoAlign ?? ContentAlign.center,
          // hidden doesn't apply here -- showLogo above already covers
          // visibility.
          options: const [
            ContentAlign.start,
            ContentAlign.center,
            ContentAlign.end
          ],
          labelOf: contentAlignLabel,
          onChanged: (a) => ctx.setStyle((s) => s.copyWith(logoAlign: a)),
        ),
      ],
      ctx.toggle(
        "Show DCR price",
        subtitle: "Decred's USD price at the foot of the nav bar, with an "
            "arrow over the coin showing which way it last moved",
        value: ctx.style.showDcrPrice,
        onChanged: (v) => ctx.setStyle((s) => s.copyWith(showDcrPrice: v)),
      ),
      ctx.toggle(
        "Show BTC price",
        subtitle: "The same for Bitcoin's USD price",
        value: ctx.style.showBtcPrice,
        onChanged: (v) => ctx.setStyle((s) => s.copyWith(showBtcPrice: v)),
      ),
      // One size for both: they sit in the same column and a mismatched
      // pair reads as a mistake rather than a choice.
      if (ctx.style.showDcrPrice || ctx.style.showBtcPrice)
        ctx.slider("priceIconSize", ctx.style.priceIconSize ?? 26,
            label: (v) => "Coin icon size: ${v.toStringAsFixed(1)}",
            min: 16,
            max: 48,
            onCommit: (v) => ctx.setStyle((s) => s.copyWith(priceIconSize: v))),
      // One padding per coin rather than one for the pair: the two rows get
      // nudged and spaced independently.
      if (ctx.style.showDcrPrice)
        ...ctx.spacing(
          key: "dcrPricePadding",
          name: "DCR price padding",
          max: 24,
          single: ctx.style.dcrPricePadding,
          sides: ctx.style.dcrPricePaddingSides,
          onSingle: (v) => ctx.setStyle((s) => s.copyWith(dcrPricePadding: v)),
          updateSides: (f) => ctx.setStyle((s) {
            var next = f(s.dcrPricePaddingSides, s.dcrPricePadding);
            return s.copyWith(
                dcrPricePaddingSides: next,
                clearDcrPricePaddingSides: next == null);
          }),
        ),
      if (ctx.style.showBtcPrice)
        ...ctx.spacing(
          key: "btcPricePadding",
          name: "BTC price padding",
          max: 24,
          single: ctx.style.btcPricePadding,
          sides: ctx.style.btcPricePaddingSides,
          onSingle: (v) => ctx.setStyle((s) => s.copyWith(btcPricePadding: v)),
          updateSides: (f) => ctx.setStyle((s) {
            var next = f(s.btcPricePaddingSides, s.btcPricePadding);
            return s.copyWith(
                btcPricePaddingSides: next,
                clearBtcPricePaddingSides: next == null);
          }),
        ),
      if (ctx.style.showDcrPrice || ctx.style.showBtcPrice)
        ctx.note("Splitting a padding per side moves that row around and "
            "spaces it from the other. While the nav bar is collapsed only "
            "the bottom applies, so the rows keep their spacing."),
    ];
