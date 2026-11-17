import 'dart:typed_data';

import 'package:bruig/components/buttons.dart';
import 'package:bruig/components/feed/embed_options.dart';
import 'package:bruig/components/feed/picture_options_controls.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// picture_options_dialog.dart decides how big a picture on a canvas is going
// to be: how wide to scale it, how hard to compress it, what to encode it as.
// The controls are the app's own, shared with a post's embedded picture and a
// site's, so the one pipeline answers the same way from every door. The width
// usually matters most: scaling 4000 pixels down to 1600 throws away most of
// the file before any compression happens.

/// showCanvasPictureOptions offers the size choices for one picture and
/// returns the bytes to store, or null if it was cancelled.
Future<Uint8List?> showCanvasPictureOptions(
  BuildContext context, {
  required Uint8List original,
  required String mime,
  required String title,
}) =>
    showDialog<Uint8List?>(
      context: context,
      builder: (context) => _PictureOptionsDialog(original, mime, title),
    );

class _PictureOptionsDialog extends StatefulWidget {
  final Uint8List original;
  final String mime;
  final String title;
  const _PictureOptionsDialog(this.original, this.mime, this.title);

  @override
  State<_PictureOptionsDialog> createState() => _PictureOptionsDialogState();
}

class _PictureOptionsDialogState extends State<_PictureOptionsDialog> {
  /// _options are remembered between pictures: a width chosen for one canvas
  /// picture is meant for them all. The default scales to 1600 wide but keeps
  /// the encoding, leaving any re-encoding for the user to choose.
  static EmbedOptions _options = const EmbedOptions(maxWidth: 1600);

  PreparedEmbed? _prepared;
  bool _preparing = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  /// _prepare applies the current options, so the size shown is the size that
  /// will be stored rather than an estimate of it.
  void _prepare() async {
    if (_preparing) {
      _again = true;
      return;
    }
    setState(() => _preparing = true);
    do {
      _again = false;
      var out = await prepareEmbed(widget.original, widget.mime, _options);
      if (!mounted) return;
      _prepared = out;
    } while (_again);
    setState(() => _preparing = false);
  }

  /// _again is whether the options changed while they were being applied.
  bool _again = false;

  void _setOptions(EmbedOptions next) {
    _options = next;
    _prepare();
  }

  Widget _sizeLine() {
    var prepared = _prepared;
    if (_preparing || prepared == null) {
      return const Txt.S("Working out the size...",
          color: TextColor.onSurfaceVariant);
    }
    var was = (widget.original.length / 1024).round();
    var now = (prepared.data.length / 1024).round();
    var size =
        prepared.width == null ? "" : "  ${prepared.width}x${prepared.height}";
    return Txt.S(now < was ? "$was KB down to $now KB$size" : "$now KB$size",
        color: TextColor.onSurfaceVariant);
  }

  @override
  Widget build(BuildContext context) {
    // Read so the dialog rebuilds with the palette, like everything else.
    ThemeNotifier.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 560,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: 220,
            child: Image.memory(_prepared?.data ?? widget.original,
                fit: BoxFit.contain, gaplessPlayback: true),
          ),
          const SizedBox(height: 12),
          PictureOptionsControls(
            options: _options,
            onChanged: _setOptions,
            onSliding: (next) => setState(() => _options = next),
            sizeLine:
                Align(alignment: Alignment.centerLeft, child: _sizeLine()),
          ),
        ]),
      ),
      actions: [
        CancelButton(onPressed: () => Navigator.of(context).pop()),
        OutlinedButton(
          // What the options make, once it is worked out: bytes from the
          // options as they were would be stored under the ones chosen.
          onPressed: _preparing
              ? null
              : () =>
                  Navigator.of(context).pop(_prepared?.data ?? widget.original),
          child: const Text("Use"),
        ),
      ],
    );
  }
}
