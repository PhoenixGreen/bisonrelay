import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/slots_window.dart';
import 'package:flutter/material.dart';

// cue_launches.dart is a row of cue launches over the slots beside the
// timeline's rows: the canvas shown's over its channels, and -- on a scene
// with cues of its own (Ken, 2026-11-10: per-canvas cues) -- the master's
// over its channels, in the All scenes heading. Each launches the whole
// row of its canvas from the next bar.

/// cueLaunchRow is a launch for each cue of the canvas shown -- or,
/// [master], of the master -- scrolled with the slots under it.
Widget cueLaunchRow(CanvasController controller, ColorScheme colors,
        {bool master = false}) =>
    slotsScroller(
      controller,
      Padding(
          padding: const EdgeInsets.fromLTRB(3, 2, 2, 2),
          child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < controller.slotsShown; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  SizedBox(
                    width: CanvasController.slotCellWidth,
                    height: 20,
                    child: Material(
                      color: controller.cueLaunched(master: master) == i
                          ? colors.primaryContainer
                          : colors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(3),
                      child: InkWell(
                        key: ValueKey(
                            master ? "masterCueLaunch-$i" : "cueLaunch-$i"),
                        borderRadius: BorderRadius.circular(3),
                        onTap: () => controller.launchCue(i, master: master),
                        child: Row(children: [
                          Icon(Icons.play_arrow,
                              size: 12, color: colors.onSurface),
                          Expanded(
                            child: Text(controller.cueName(i, master: master),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 10.5, color: colors.onSurface)),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ],
              ])),
    );
