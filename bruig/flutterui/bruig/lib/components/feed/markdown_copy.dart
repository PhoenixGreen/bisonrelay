import 'package:bruig/components/copyable.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

// markdown_copy.dart is something you press to put on the clipboard:
//
//   --copy[label=Payment address]--
//   DsExampleAddressGoesHere
//   --/copy--
//
// A payment address printed as a line of text is a line of text: the buyer
// has to select it, and a selection that takes one character too few is a
// payment to nobody. Every wallet in Decred puts a copy button next to one
// for that reason.
//
// The whole box is the button, not an icon at the end of it. The thing
// somebody reaches for is the address itself -- they are already pointing at
// it -- so that is what answers. The icon is there to say that pressing does
// something, since a box of text that copies when tapped and does not look
// like it would is a feature nobody finds.
//
// What is copied is exactly what is between the markers. This does not know
// what a Decred address looks like, and a block that tidied up what it was
// given would be a block that copies something the buyer never saw.

/// CopyRule is what one box asked for.
@immutable
class CopyRule {
  /// label is the quiet word above the text, or empty for a box that is
  /// obvious from where it sits.
  final String label;

  const CopyRule({this.label = ""});

  static CopyRule parse(String? attributes) {
    var fields = <String, String>{};
    for (var part in (attributes ?? "").split(",")) {
      var at = part.indexOf("=");
      if (at == -1) continue;
      fields.putIfAbsent(part.substring(0, at).trim().toLowerCase(),
          () => part.substring(at + 1).trim());
    }
    return CopyRule(label: fields["label"] ?? "");
  }
}

class CopyBlockSyntax extends md.BlockSyntax {
  static final _open = RegExp(r'^\s*--copy(?:\[([^\]]*)\])?--\s*$');
  static final _close = RegExp(r'^\s*--/copy--\s*$');

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

    var element = md.Element.text("copy", "");
    element.attributes["data"] = lines.join().trim();
    if (attributes != null) element.attributes["attrs"] = attributes;

    // Inside a paragraph, for the reason every other block here is: this
    // renderer treats only a fixed list of tags as blocks.
    return md.Element("p", [element]);
  }
}

class CopyMarkdownElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) =>
      MarkdownCopy(
        data: element.attributes["data"] ?? "",
        rule: CopyRule.parse(element.attributes["attrs"]),
      );
}

/// MarkdownCopy draws it.
class MarkdownCopy extends StatelessWidget {
  final String data;
  final CopyRule rule;
  const MarkdownCopy({required this.data, required this.rule, super.key});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();
    var theme = ThemeNotifier.of(context);
    var colors = theme.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Copyable(
        data,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (rule.label.isNotEmpty) ...[
                      Text(rule.label,
                          style: TextStyle(
                              fontSize: 11, color: colors.onSurfaceVariant)),
                      const SizedBox(height: 2),
                    ],
                    // Wrapped rather than ellipsised: an address cut short
                    // with a "..." is one a buyer cannot check against what
                    // their wallet is about to send to.
                    SelectionContainer.disabled(
                      child: Text(
                        data,
                        style: TextStyle(
                          fontFamily: "RobotoMono",
                          fontSize: 13,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.copy_rounded, size: 18, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
