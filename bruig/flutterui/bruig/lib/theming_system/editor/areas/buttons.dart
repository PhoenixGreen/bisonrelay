import 'package:bruig/components/buttons.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/theming_system/theme_editor.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';

// buttons.dart is the "Buttons" area: the app's five button
// appearances (see ButtonRole), each with its own background, hover, border,
// padding and margin.
//
// The five are picked from a dropdown rather than laid out one under the
// other -- five copies of the same five settings stacked up reads as one
// undifferentiated wall of sliders, and only one button is being tuned at a
// time anyway. Which one is showing is local to the editor, so it isn't
// stored on the preset.
//
// Every setting starts at "leave it alone": with nothing set, each role
// compiles to exactly the ButtonStyle its palette colors alone produce.
List<Widget> buttonsAreaEditor(AreaEditorContext ctx) => [
      _ButtonRolePicker(ctx),
    ];

class _ButtonRolePicker extends StatefulWidget {
  final AreaEditorContext ctx;
  const _ButtonRolePicker(this.ctx);

  @override
  State<_ButtonRolePicker> createState() => _ButtonRolePickerState();
}

class _ButtonRolePickerState extends State<_ButtonRolePicker> {
  ButtonRole role = ButtonRole.primary;

  @override
  Widget build(BuildContext context) {
    var ctx = widget.ctx;
    var spec = ctx.style.buttonStyles[role] ?? const ButtonAreaStyle();

    // setSpec writes one role back into the map, re-reading the current
    // style first for the same reason AreaEditorContext.setStyle does: a
    // single action can produce two calls in a row, and the second must
    // start from the first's result rather than this build's snapshot.
    void setSpec(ButtonAreaStyle Function(ButtonAreaStyle) update) =>
        ctx.setStyle((s) => s.copyWith(buttonStyles: {
              ...s.buttonStyles,
              role: update(s.buttonStyles[role] ?? const ButtonAreaStyle()),
            }));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ctx.choice<ButtonRole>(
        "Button",
        value: role,
        options: ButtonRole.values,
        labelOf: buttonRoleLabel,
        onChanged: (r) => setState(() => role = r),
      ),
      ctx.note(buttonRoleExamples[role]!),
      const SizedBox(height: 12),
      _Preview(selected: role, onSelect: (r) => setState(() => role = r)),
      const SizedBox(height: 16),
      // The three colors share one line (stacking as the pane narrows):
      // they're the settings most worth changing and re-judging against the
      // preview above, and three of them stacked pushed it off screen. Each
      // keeps its own one-line explanation underneath, so nothing is lost
      // to the tighter layout.
      ctx.row([
        ctx.colorCell(
          "Background",
          value: spec.resolveBackground(ctx.preset.palette),
          valueIndex: spec.backgroundIndex,
          note: _backgroundNote(role),
          onChanged: (c, i) => setSpec((s) => c == null
              ? s.copyWith(clearBackground: true, clearBackgroundIndex: true)
              : s.copyWith(
                  background: c,
                  backgroundIndex: i,
                  clearBackgroundIndex: i == null)),
        ),
        ctx.colorCell(
          "Hover",
          value: spec.resolveHover(ctx.preset.palette),
          valueIndex: spec.hoverIndex,
          note: "Tints the fill while pointed at. Default: Background "
              "Hover.",
          onChanged: (c, i) => setSpec((s) => c == null
              ? s.copyWith(clearHover: true, clearHoverIndex: true)
              : s.copyWith(
                  hover: c, hoverIndex: i, clearHoverIndex: i == null)),
        ),
        ctx.colorCell(
          "Border color",
          value: spec.resolveBorder(ctx.preset.palette),
          valueIndex: spec.borderIndex,
          note: role == ButtonRole.outlined
              ? "Default: Button Border Color."
              : "No border by default -- a color or a width adds one.",
          onChanged: (c, i) => setSpec((s) => c == null
              ? s.copyWith(clearBorder: true, clearBorderIndex: true)
              : s.copyWith(
                  border: c, borderIndex: i, clearBorderIndex: i == null)),
        ),
      ]),
      const SizedBox(height: 12),
      ctx.slider("buttonBorderWidth.${role.name}", spec.borderWidth,
          label: (v) => v <= 0
              ? "Border width: Default"
              : "Border width: ${v.toStringAsFixed(1)}",
          max: 6,
          onCommit: (v) => setSpec((s) => s.copyWith(borderWidth: v))),
      const SizedBox(height: 8),
      ...ctx.spacing(
        key: "buttonBorderRadius.${role.name}",
        name: "Border radius",
        max: 40,
        single: spec.borderRadius,
        sides: spec.borderRadiusSides,
        // Radius is the one of these measured at the corners rather than
        // along the edges.
        slotLabels: cornerLabels,
        onSingle: (v) => setSpec((s) => s.copyWith(borderRadius: v)),
        updateSides: (f) => setSpec((s) {
          var next = f(s.borderRadiusSides, s.borderRadius);
          return s.copyWith(
              borderRadiusSides: next, clearBorderRadiusSides: next == null);
        }),
      ),
      ctx.note("Default is the pill shape every button already has -- its "
          "corners follow its height. Square a button off with a radius of "
          "1 or so rather than 0, which is what \"Default\" is."),
      ...ctx.spacing(
        key: "buttonPadding.${role.name}",
        name: "Padding",
        max: 60,
        single: spec.padding,
        sides: spec.paddingSides,
        slotLabels: sideLabels,
        onSingle: (v) => setSpec((s) => s.copyWith(padding: v)),
        updateSides: (f) => setSpec((s) {
          var next = f(s.paddingSides, s.padding);
          return s.copyWith(
              paddingSides: next, clearPaddingSides: next == null);
        }),
      ),
      ...ctx.spacing(
        key: "buttonMargin.${role.name}",
        name: "Margin",
        max: 48,
        single: spec.margin,
        sides: spec.marginSides,
        slotLabels: sideLabels,
        onSingle: (v) => setSpec((s) => s.copyWith(margin: v)),
        updateSides: (f) => setSpec((s) {
          var next = f(s.marginSides, s.margin);
          return s.copyWith(marginSides: next, clearMarginSides: next == null);
        }),
      ),
      ctx.note("Space outside the button. Setting one moves the fill, the "
          "border and the hover inwards off the button's own edge, so the "
          "gap belongs to the button rather than to whatever it sits next "
          "to."),
    ]);
  }
}

// _Preview shows all five buttons as they currently render, so a change to
// the one being edited can be judged both on its own and against the other
// four -- which is the whole point of them being one set.
//
// These are the app's *real* buttons, not mock-ups of them: every edit here
// is previewed straight into the active theme (see ThemeNotifier
// .previewPreset), so an ordinary ElevatedButton sitting on this page is
// already drawing through the style being edited. Only the two roles
// Material has no theme slot for have to name their style explicitly.
//
// Each preview is also its own picker: they need a live onPressed for the
// hover state to render at all (which is one of the settings), and
// selecting the button you just pointed at is the useful thing for that tap
// to do.
class _Preview extends StatelessWidget {
  final ButtonRole selected;
  final ValueChanged<ButtonRole> onSelect;
  const _Preview({required this.selected, required this.onSelect});

  // _sample is a real button of each role, labelled with one of that role's
  // own call sites rather than something invented, so what's on screen is
  // recognizably a button from the app.
  Widget _sample(ButtonRole role) {
    void tap() => onSelect(role);
    return switch (role) {
      ButtonRole.primary =>
        LoadingScreenButton(onPressed: tap, text: "Unlock Wallet"),
      ButtonRole.plain =>
        ElevatedButton(onPressed: tap, child: const Text("Export Logs")),
      ButtonRole.outlined =>
        OutlinedButton(onPressed: tap, child: const Txt.S("Read More")),
      ButtonRole.tonal =>
        FilledButton.tonal(onPressed: tap, child: const Text("Create Post")),
      ButtonRole.danger => CancelButton(onPressed: tap, label: "Clear Post"),
    };
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // outlineVariant, not outline: this is a panel edge that should
        // blend, not a control border competing with the buttons inside it.
        border: Border.all(color: theme.colors.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Txt.S("Preview"),
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var role in ButtonRole.values)
              Column(mainAxisSize: MainAxisSize.min, children: [
                _sample(role),
                const SizedBox(height: 4),
                // Every sample names itself -- five unlabelled pills don't
                // say which is which, and the dropdown above can only name
                // one of them. The one being edited is the brighter of the
                // two text colors, so the selection is visible here as well
                // as in the dropdown.
                Txt.S(buttonRoleLabel(role),
                    color: role == selected
                        ? TextColor.onSurface
                        : TextColor.onSurfaceVariant),
              ]),
          ],
        ),
      ]),
    );
  }
}

String _backgroundNote(ButtonRole role) => switch (role) {
      ButtonRole.primary => "Default: Button Background Primary.",
      ButtonRole.plain ||
      ButtonRole.outlined =>
        "No fill by default -- the page shows through.",
      ButtonRole.tonal => "Default: Third Background Color.",
      ButtonRole.danger => "Default: Button Background Secondary.",
    };
