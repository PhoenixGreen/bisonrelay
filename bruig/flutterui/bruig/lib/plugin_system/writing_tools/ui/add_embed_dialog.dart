import 'dart:convert';
import 'dart:typed_data';

import 'package:bruig/components/feed/embed_options.dart';
import 'package:bruig/components/feed/picture_options_controls.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/feed.dart';
import 'package:bruig/plugin_system/writing_tools/post_library/embed_store.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// add_embed_dialog.dart is the sheet that puts a picture into a post: how
// large it should be stored, how hard it should be compressed, and what it
// says for anyone who cannot see it.
//
// Its own file because it is its own decision. It shares nothing with the
// composer screen but the post being written and the field to write into,
// and it was two hundred lines in the middle of a file about something else.

void showAltTextModal(BuildContext context, String mime, String data,
    NewPostModel post, TextEditingController contentCtrl) {
  showModalBottomSheet(
    context: context,
    builder: (BuildContext context) =>
        AddAltText(mime, data, post, contentCtrl),
  );
}

class AddAltText extends StatefulWidget {
  final String mime;
  final String data;
  final TextEditingController contentCtrl;
  final NewPostModel post;
  const AddAltText(this.mime, this.data, this.post, this.contentCtrl,
      {super.key});

  @override
  State<AddAltText> createState() => _AddAltTextState();
}

class _AddAltTextState extends State<AddAltText> {
  final TextEditingController embedAlt = TextEditingController();

  String get mime => widget.mime;
  TextEditingController get contentCtrl => widget.contentCtrl;

  /// _options are remembered between embeds, because somebody who has
  /// decided their posts should hold 1000-pixel pictures has decided it for
  /// all of them, not for this one.
  static EmbedOptions _options =
      const EmbedOptions(maxWidth: 1600, quality: 80);

  /// _prepared is the picture as it will be stored, and _preparing guards
  /// against a second run starting while one is going.
  PreparedEmbed? _prepared;
  bool _preparing = false;

  /// _original is widget.data decoded once. It arrives as base64 -- that is
  /// the form the post text carries -- and decoding it on every change of
  /// the slider would be work for nothing.
  late final Uint8List _original = base64Decode(widget.data);

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    embedAlt.dispose();
    super.dispose();
  }

  /// _prepare applies the current options, so the size shown is the size
  /// that will be stored rather than an estimate of it.
  void _prepare() async {
    if (_preparing) return;
    setState(() => _preparing = true);
    var out = await prepareEmbed(_original, mime, _options);
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

  void _addEmbed() async {
    // Whatever the options produced, falling back to the original if the
    // work has not finished -- the writer pressing Add is not a reason to
    // make them wait, and the original is always valid.
    var ready = _prepared ?? PreparedEmbed(_original, mime);

    List<String> embed = [];
    if (ready.mime != "") {
      embed.add("type=${ready.mime}");
    }
    if (embedAlt.text != "") {
      embed.add("alt=${Uri.encodeComponent(embedAlt.text)}");
    }

    var id = widget.post.trackEmbed(base64Encode(ready.data));
    if (id != "") {
      embed.add("data=[content $id]");
      // Written now rather than when the draft is saved. The text carries
      // only the reference, so a picture that is not on disk by the time the
      // app closes is a picture the draft comes back without -- which is
      // exactly what used to happen to every one of them.
      await EmbedStore.save(id, base64Encode(ready.data));
    }
    var embedText = "--embed[${embed.join(",")}]--";

    var insertPos = contentCtrl.selection.start;
    if (insertPos > -1 && insertPos < contentCtrl.text.length) {
      contentCtrl.text = contentCtrl.text.substring(0, insertPos) +
          embedText +
          contentCtrl.text.substring(insertPos);
    } else {
      contentCtrl.text += "\n$embedText\n";
    }

    // Checked because the save above is awaited: the dialog can be dismissed
    // while a large picture is still being written.
    if (!mounted) return;
    Navigator.pop(context);
  }

  /// _sizeLine says what the picture will cost, and what it costs now.
  ///
  /// The number that matters is the stored one, so it is measured rather
  /// than estimated: the options are actually applied and the result
  /// weighed. Anything else would be advertising a saving that might not
  /// arrive.
  Widget _sizeLine() {
    var prepared = _prepared;
    if (_preparing || prepared == null) {
      return const Txt.S("Working out the size...",
          color: TextColor.onSurfaceVariant);
    }
    // Base64 is what the post carries, and it is a third larger than the
    // bytes -- so that is the figure quoted, being the one that lands in
    // the post's size limit.
    var was = (widget.data.length / 1024).round();
    var now = (base64Encode(prepared.data).length / 1024).round();
    var size =
        prepared.width == null ? "" : "  ${prepared.width}x${prepared.height}";
    return Txt.S(now < was ? "$was KB down to $now KB$size" : "$now KB$size",
        color: TextColor.onSurfaceVariant);
  }

  @override
  Widget build(BuildContext context) {
    var isImage = mime.startsWith("image/");
    return Container(
      padding: const EdgeInsets.all(30),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (isImage) ...[
          PictureOptionsControls(
            options: _options,
            onChanged: _setOptions,
            onSliding: (next) => setState(() => _options = next),
            sizeLine:
                Align(alignment: Alignment.centerLeft, child: _sizeLine()),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            const Text("Alt Text: "),
            const SizedBox(width: 5),
            Expanded(
                child: TextField(
              onSubmitted: (_) {
                _addEmbed();
              },
              controller: embedAlt,
              autofocus: true,
            )),
            const SizedBox(width: 30),
            TextButton(
              onPressed: () => _addEmbed(),
              child: const Text("No alt text"),
            ),
            const SizedBox(width: 10),
            OutlinedButton(onPressed: _addEmbed, child: const Text("Add")),
          ],
        ),
      ]),
    );
  }
}
