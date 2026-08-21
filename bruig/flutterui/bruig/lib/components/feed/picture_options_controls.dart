import 'package:bruig/components/feed/embed_options.dart';
import 'package:flutter/material.dart';

// picture_options_controls.dart is the row of controls that decides how big
// a picture is going to be: how wide to scale it, how hard to compress it,
// and what to encode it as.
//
// One widget, used by both the sheet that puts a picture into a post and the
// one that adds a picture to a site. The two ask the same question of the
// same pipeline, and when they each had their own controls the answer to
// "why is this one bigger" depended on which door you came in through.

/// PictureOptionsControls edits an [EmbedOptions].
///
/// Two callbacks rather than one, because a slider being dragged and a
/// slider let go are different events. Re-encoding on every pixel of drag
/// would make a large picture unusable, so the drag only moves the label and
/// the release does the work.
class PictureOptionsControls extends StatelessWidget {
  final EmbedOptions options;

  /// onChanged is a setting the person has finished choosing. Re-encode here.
  final ValueChanged<EmbedOptions> onChanged;

  /// onSliding is the slider mid-drag. Update the label and nothing else.
  final ValueChanged<EmbedOptions> onSliding;

  /// sizeLine says what the result weighs. Supplied rather than built here:
  /// a post counts the base64 it carries and a site counts the file on
  /// disk, and quoting the wrong one is how a limit gets missed.
  final Widget sizeLine;

  const PictureOptionsControls({
    required this.options,
    required this.onChanged,
    required this.onSliding,
    required this.sizeLine,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 20,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Text("Maximum width: "),
                const SizedBox(width: 5),
                DropdownButton<int?>(
                  value: options.maxWidth,
                  items: const [
                    DropdownMenuItem(value: null, child: Text("Original")),
                    DropdownMenuItem(value: 2000, child: Text("2000 px")),
                    DropdownMenuItem(value: 1600, child: Text("1600 px")),
                    DropdownMenuItem(value: 1200, child: Text("1200 px")),
                    DropdownMenuItem(value: 1000, child: Text("1000 px")),
                    DropdownMenuItem(value: 800, child: Text("800 px")),
                    DropdownMenuItem(value: 600, child: Text("600 px")),
                  ],
                  onChanged: (v) => onChanged(
                      options.copyWith(maxWidth: v, clearMaxWidth: v == null)),
                ),
              ]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Text("Format: "),
                const SizedBox(width: 5),
                DropdownButton<EmbedFormat>(
                  value: options.format,
                  items: const [
                    DropdownMenuItem(
                        value: EmbedFormat.keep, child: Text("Automatic")),
                    DropdownMenuItem(
                        value: EmbedFormat.jpeg, child: Text("JPEG")),
                    DropdownMenuItem(
                        value: EmbedFormat.png, child: Text("PNG")),
                  ],
                  onChanged: (v) =>
                      onChanged(options.copyWith(format: v ?? options.format)),
                ),
              ]),
            ],
          ),
          Row(children: [
            const Text("Quality: "),
            Expanded(
              child: Slider(
                value: options.quality.toDouble(),
                min: 10,
                max: 100,
                divisions: 18,
                // 100 with no format chosen is not a quality setting but a
                // decision to leave the original encoding alone, so it is
                // labelled as one. With a format chosen it is a quality
                // again, because the picture is being re-encoded either way.
                label: options.quality == 100 && options.format == EmbedFormat.keep
                    ? "Original"
                    : "${options.quality}",
                onChanged: (v) =>
                    onSliding(options.copyWith(quality: v.round())),
                onChangeEnd: (v) =>
                    onChanged(options.copyWith(quality: v.round())),
              ),
            ),
          ]),
          sizeLine,
          if (options.format == EmbedFormat.png)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                "PNG keeps every pixel and anything see-through, and is much "
                "larger than JPEG for a photograph.",
                style: TextStyle(fontSize: 12),
              ),
            ),
        ],
      );
}
