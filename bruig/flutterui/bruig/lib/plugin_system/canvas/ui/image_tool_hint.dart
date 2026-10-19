import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_mask.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/image_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/image_layer_settings.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// image_tool_hint.dart is what floats over the canvas while a picture's
// layers are open: the tool in hand and what to do with it, where the eye
// already is -- the panel's hint is a long way off across the screen -- and
// a button that shows the picture as it was put in for as long as it is
// held.

/// toolHint is what to do with [tool], in a line.
String toolHint(CanvasController controller, ImageTool tool) => switch (tool) {
      ImageTool.move => "",
      ImageTool.subject => "Click a person or thing to keep only it",
      ImageTool.quick => "Brush over what to keep · Option takes away",
      ImageTool.refine => "Brush along hair and soft edges",
      ImageTool.brush => "Paint to hide · X swaps to show",
      ImageTool.lasso => "Draw round what to hide",
      ImageTool.fade => controller.maskRadial
          ? "Drag out from the middle · whole inside, faded past the end"
          : controller.maskHide
              ? "Drag from hidden to shown"
              : "Drag from brought back to unchanged",
      ImageTool.paint => "Paint · the pen's pressure sets the width",
      ImageTool.erase => "Rub out paint",
      ImageTool.clone => controller.cloneFrom == null
          ? "Option-click where to copy from"
          : "Paint where the copy goes · Esc clears the point",
      ImageTool.heal => "Paint over a spot",
      ImageTool.dodge => "Paint to lighten · Option darkens",
      ImageTool.soften => "Paint to soften",
      ImageTool.sharpen => "Paint to crisp",
      ImageTool.smudge => "Drag colour along",
    };

/// original is [e] as its picture was put in: no layers, no mask, no
/// retouching, no colour work and no outline.
ImageElement original(ImageElement e) => e.copyWith(
      layers: const [],
      mask: const ImageMask(),
      retouch: const [],
      filter: ImageFilterPreset.none,
      saturation: 1,
      brightness: 1,
      blend: OverlayBlend.none,
      outline: e.outline.copyWith(width: 0),
    );

/// ImageToolHint is the pill over the canvas while a picture is being
/// edited.
class ImageToolHint extends StatelessWidget {
  final CanvasController controller;
  const ImageToolHint({required this.controller, super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          var e = controller.editingImage;
          if (e == null || controller.playing) return const SizedBox.shrink();
          var theme = ThemeNotifier.of(context);
          var tool = controller.imageTool;
          var muted = theme.colors.onSurfaceVariant;
          return Container(
            key: const ValueKey("imageToolHint"),
            padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
            decoration: BoxDecoration(
              color: theme.colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.colors.outlineVariant),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x55000000),
                    blurRadius: 14,
                    offset: Offset(0, 4)),
              ],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _CompareButton(controller: controller, element: e),
              if (tool != ImageTool.move) ...[
                Container(
                    width: 1,
                    height: 20,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    color: theme.colors.outlineVariant),
                Icon(toolIcon(tool), size: 16, color: theme.colors.primary),
                const SizedBox(width: 6),
                Text(tool.label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colors.onSurface)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(controller.maskBusy ?? toolHint(controller, tool),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted)),
                ),
                const SizedBox(width: 8),
                _Pill(
                  key: const ValueKey("imageToolDone"),
                  label: "Done · Esc",
                  onTap: () => controller.imageTool = ImageTool.move,
                ),
              ],
            ]),
          );
        },
      );
}

/// _CompareButton shows the picture as it was put in while it is pressed.
class _CompareButton extends StatefulWidget {
  final CanvasController controller;
  final ImageElement element;
  const _CompareButton({required this.controller, required this.element});

  @override
  State<_CompareButton> createState() => _CompareButtonState();
}

class _CompareButtonState extends State<_CompareButton> {
  bool _held = false;

  void _hold(bool on) {
    if (on == _held) return;
    setState(() => _held = on);
    widget.controller.tryElement(on ? original(widget.element) : null);
  }

  @override
  Widget build(BuildContext context) => _Pill(
        key: const ValueKey("imageCompare"),
        label: _held ? "Original" : "Hold to compare",
        icon: Icons.compare,
        lit: _held,
        onDown: () => _hold(true),
        onUp: () => _hold(false),
      );
}

class _Pill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool lit;
  final VoidCallback? onTap;
  final VoidCallback? onDown;
  final VoidCallback? onUp;
  const _Pill(
      {required this.label,
      this.icon,
      this.lit = false,
      this.onTap,
      this.onDown,
      this.onUp,
      super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var accent = theme.colors.primary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onTapDown: onDown == null ? null : (_) => onDown!(),
        onTapUp: onUp == null ? null : (_) => onUp!(),
        onTapCancel: onUp,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            color: lit ? accent.withValues(alpha: 0.16) : null,
            border:
                Border.all(color: lit ? accent : theme.colors.outlineVariant),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: theme.colors.onSurface),
              const SizedBox(width: 5),
            ],
            Text(label,
                style:
                    TextStyle(fontSize: 11.5, color: theme.colors.onSurface)),
          ]),
        ),
      ),
    );
  }
}
