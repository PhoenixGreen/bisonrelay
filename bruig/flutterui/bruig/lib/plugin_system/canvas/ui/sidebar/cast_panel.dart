import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// cast_panel.dart is the Cast in the sidebar (Ken, 2026-11-10): the
// document's elements kept once -- a game's hero -- each with linked copies
// in its scenes. The element picked can be added to it, linking it and its
// copies in every other scene; a copy picked says what it is linked to, and
// can be let go. A member clicked is a copy of it placed on the canvas. See
// model/cast.dart for what a copy shares and what is its own.

/// CastPanel lists the Cast, for a click to place a linked copy, with the
/// picked element's link above it.
class CastPanel extends StatelessWidget {
  final CanvasController controller;
  const CastPanel({required this.controller, super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          var colors = ThemeNotifier.of(context).colors;
          var muted = TextStyle(fontSize: 12, color: colors.onSurfaceVariant);
          var picked = controller.selection.length == 1
              ? controller.document.elementById(controller.selection.single)
              : null;
          var member = picked == null ? null : controller.castOf(picked.id);
          return SingleChildScrollView(
            key: const ValueKey("castPanelScroll"),
            padding: const EdgeInsets.all(8),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (picked != null && member != null) ...[
                Text(
                    "${picked.name} is a copy of ${member.name} in the "
                    "Cast: its place, size and what it does here are "
                    "its own; the rest is every copy's.",
                    key: const ValueKey("castLinkedNote"),
                    style: muted),
                const SizedBox(height: 4),
                TextButton.icon(
                  key: const ValueKey("castUnlink"),
                  onPressed: () => controller.unlinkFromCast(picked.id),
                  icon: const Icon(Icons.link_off, size: 16),
                  label: const Text("Unlink this copy"),
                ),
              ] else if (picked != null)
                TextButton.icon(
                  key: const ValueKey("castAdd"),
                  onPressed: () => controller.addToCast(picked.id),
                  icon: const Icon(Icons.group_add_outlined, size: 16),
                  label: Text("Add ${picked.name} to the Cast"),
                )
              else
                Text(
                    "Pick an element -- a game's hero -- to add it to "
                    "the Cast: it and its copies in the other scenes "
                    "are linked, each keeping its own place and size.",
                    style: muted),
              const SizedBox(height: 8),
              if (controller.cast.isEmpty)
                Text("Nobody in the Cast yet.",
                    key: const ValueKey("castEmpty"), style: muted)
              else
                for (var m in controller.cast)
                  _CastRow(controller: controller, member: m),
            ]),
          );
        },
      );
}

/// _CastRow is one member: its name and how many copies it has, clicked to
/// place a copy, with a way to take it out of the Cast.
class _CastRow extends StatelessWidget {
  final CanvasController controller;
  final CanvasElement member;
  const _CastRow({required this.controller, required this.member});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var copies = controller.castCopiesOf(member.id);
    return InkWell(
      key: ValueKey("castMember-${member.id}"),
      onTap: () => controller.placeFromCast(member.id),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(children: [
          Icon(Icons.person_outline, size: 18, color: colors.onSurface),
          const SizedBox(width: 8),
          Expanded(
            child: Text(member.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: colors.onSurface)),
          ),
          Text(copies == 1 ? "1 copy" : "$copies copies",
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
          IconButton(
            key: ValueKey("castRemove-${member.id}"),
            tooltip: "Take out of the Cast: every copy kept, as it is",
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            onPressed: () => controller.removeFromCast(member.id),
            icon: const Icon(Icons.close),
          ),
        ]),
      ),
    );
  }
}
