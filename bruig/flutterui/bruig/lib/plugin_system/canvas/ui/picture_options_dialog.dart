import 'dart:typed_data';

import 'package:bruig/components/buttons.dart';
import 'package:bruig/components/feed/embed_options.dart';
import 'package:bruig/components/feed/picture_options_controls.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// picture_options_dialog.dart decides how big a picture on a canvas is going
// to be: how wide to scale it, how hard to compress it, what to encode it as.
//
// The controls are the app's own -- the same widget a post's embedded picture
// and a site's picture use -- rather than a second set written for here. They
// ask the same question of the same pipeline, and when two doors into one
// pipeline have their own controls, the answer to "why is this one bigger"
// depends on which door you came in through.
//
// It replaces showCompressScreen, which the canvas used and which offers a
// single quality slider and no say over the width or the format. The width is
// usually the setting that matters: scaling a 4000-pixel photograph down to
// 1600 throws away most of the file before any compression happens, and
// compressing without it spends effort on detail nobody will see.

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
  /// _options are remembered between pictures, for the same reason the site's
  /// are: somebody who has decided their canvases' pictures should be 1600
  /// wide has decided it for their canvases, not for this one file.
  ///
  /// The default keeps the encoding alone. A canvas may be exported at four
  /// thousand pixels for a poster, so the picture in it is not obviously too
  /// big for anything -- and quietly re-encoding what somebody has just chosen
  /// is a decision this is here to hand back to them.
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
    if (_preparing) return;
    setState(() => _preparing = true);
    var out = await prepareEmbed(widget.original, widget.mime, _options);
    if (!mounted) return;
    setState(() {
      _prepared = out;
      _preparing = false;
    });
  }

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
          // Whatever the options produced, falling back to the original if
          // the work has not finished: pressing Use is not a reason to be
          // made to wait, and the original is always valid.
          onPressed: () => Navigator.of(context)
              .pop(_prepared?.data ?? widget.original),
          child: const Text("Use"),
        ),
      ],
    );
  }
}
