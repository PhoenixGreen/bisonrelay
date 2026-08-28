import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:qr_flutter/qr_flutter.dart';

// markdown_qr.dart is a square somebody points a phone at:
//
//   --qr[size=200, align=center]--
//   decred:DsAddr?amount=1.6
//   --/qr--
//
// A shop asking to be paid on-chain is the reason it exists. The address is
// there to copy, which works when the wallet paying is on the same machine
// and is the wrong shape entirely when it is a phone in your hand -- and a
// mistyped address is a payment to nobody.
//
// What is encoded is whatever is between the two lines, unchanged. This draws
// a square; it does not know what a Decred address looks like, and a block
// that quietly rewrote what it was given would be a block that pays somebody
// else.

/// maxQrSize is as large as one may be drawn.
const double maxQrSize = 400;

/// QrRule is what one square asked for.
@immutable
class QrRule {
  final double size;
  final Alignment align;
  const QrRule({this.size = 180, this.align = Alignment.centerLeft});

  static QrRule parse(String? attributes) {
    var fields = <String, String>{};
    for (var part in (attributes ?? "").split(",")) {
      var at = part.indexOf("=");
      if (at == -1) continue;
      fields.putIfAbsent(part.substring(0, at).trim().toLowerCase(),
          () => part.substring(at + 1).trim());
    }

    var size = double.tryParse(fields["size"] ?? "");
    return QrRule(
      size: size == null || size < 40 || size > maxQrSize ? 180 : size,
      align: switch (fields["align"]?.toLowerCase()) {
        "center" || "centre" || "middle" => Alignment.center,
        "right" || "end" => Alignment.centerRight,
        _ => Alignment.centerLeft,
      },
    );
  }
}

class QrBlockSyntax extends md.BlockSyntax {
  static final _open = RegExp(r'^\s*--qr(?:\[([^\]]*)\])?--\s*$');
  static final _close = RegExp(r'^\s*--/qr--\s*$');

  @override
  RegExp get pattern => _open;

  @override
  md.Node? parse(md.BlockParser parser) {
    var attributes = _open.firstMatch(parser.current.content)?.group(1);
    parser.advance();

    var lines = <String>[];
    while (!parser.isDone) {
      if (_close.hasMatch(parser.current.content)) {
        parser.advance();
        break;
      }
      lines.add(parser.current.content.trim());
      parser.advance();
    }

    var element = md.Element.text("qr", "");
    element.attributes["data"] = lines.join().trim();
    if (attributes != null) element.attributes["attrs"] = attributes;

    // Inside a paragraph, for the reason every other block here is: this
    // renderer treats only a fixed list of tags as blocks.
    return md.Element("p", [element]);
  }
}

class QrMarkdownElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) =>
      MarkdownQr(
        data: element.attributes["data"] ?? "",
        rule: QrRule.parse(element.attributes["attrs"]),
      );
}

/// MarkdownQr draws it.
class MarkdownQr extends StatelessWidget {
  final String data;
  final QrRule rule;
  const MarkdownQr({required this.data, required this.rule, super.key});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();
    var theme = ThemeNotifier.of(context);

    // On white, always. A code is read by a camera looking for dark on light,
    // and one drawn in a dark theme's own colours is a square a phone will
    // not see -- which is the one failure this block cannot afford, since
    // there is nothing on screen to say it went wrong.
    return Align(
      alignment: rule.align,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colors.outlineVariant),
        ),
        child: QrImageView(
          data: data,
          size: rule.size,
          backgroundColor: Colors.white,
          // A payment address is worth carrying more of the error correction
          // budget: the square is being read off a screen, at an angle, by
          // whatever camera somebody has.
          errorCorrectionLevel: QrErrorCorrectLevel.M,
        ),
      ),
    );
  }
}
