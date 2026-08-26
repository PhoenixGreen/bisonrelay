import 'package:bruig/components/md_elements.dart';
import 'package:bruig/theming_system/model/button_style.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

// markdown_button.dart is a link drawn as a button:
//
//   --button[label=Buy Now, link=product/gtr, style=primary, align=right]--
//
// A link is the right thing for going somewhere and the wrong thing for the
// one action a page is for. A shop front's card ends in "buy this", and a
// line of blue text among other lines of blue text is not that -- it reads
// as one more thing to consider rather than the thing to press.
//
// Deliberately not a form. A form submits: it carries fields, it changes
// something, and the shop answers with a new page. This goes where a link
// goes and does what a link does, which is why it takes a link rather than
// an action. What separates them is what happens afterwards, and that is
// exactly what a reader deciding whether to press it wants to know.
//
// The style names one of the theme's button roles, so a page's button is the
// app's button in the reader's own theme rather than a colour the page
// picked. A page that names none gets the ordinary one.

/// ButtonRule is what one button asked for.
@immutable
class ButtonRule {
  final String label;
  final String link;

  /// role is which of the app's buttons this is drawn as, or null for the
  /// ordinary one.
  final ButtonRole? role;

  /// align is which side of the block it sits on.
  final Alignment align;

  const ButtonRule({
    this.label = "",
    this.link = "",
    this.role,
    this.align = Alignment.centerLeft,
  });

  /// draws is whether there is anything to draw. A button with no label is
  /// not a button; one with no link is not one either, since going somewhere
  /// is the whole of what it does.
  bool get draws => label.isNotEmpty && link.isNotEmpty;

  static ButtonRule parse(String? attributes) {
    var fields = <String, String>{};
    for (var part in (attributes ?? "").split(",")) {
      var at = part.indexOf("=");
      if (at == -1) continue;
      fields.putIfAbsent(part.substring(0, at).trim().toLowerCase(),
          () => part.substring(at + 1).trim());
    }

    ButtonRole? role;
    for (var r in ButtonRole.values) {
      if (r.name == fields["style"]?.toLowerCase()) role = r;
    }

    return ButtonRule(
      label: fields["label"] ?? "",
      link: fields["link"] ?? "",
      role: role,
      align: switch (fields["align"]?.toLowerCase()) {
        "center" || "centre" || "middle" => Alignment.center,
        "right" || "end" => Alignment.centerRight,
        _ => Alignment.centerLeft,
      },
    );
  }
}

class ButtonBlockSyntax extends md.BlockSyntax {
  static final _open = RegExp(r'^\s*--button(?:\[([^\]]*)\])?--\s*$');

  @override
  RegExp get pattern => _open;

  @override
  md.Node? parse(md.BlockParser parser) {
    var attributes = _open.firstMatch(parser.current.content)?.group(1);
    parser.advance();

    var element = md.Element.text("button", "");
    if (attributes != null) element.attributes["attrs"] = attributes;

    // Inside a paragraph, for the reason every other block here is: this
    // renderer treats only a fixed list of tags as blocks and handles
    // anything else as though it were already inside one.
    return md.Element("p", [element]);
  }
}

class ButtonMarkdownElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) =>
      MarkdownButton(rule: ButtonRule.parse(element.attributes["attrs"]));
}

/// MarkdownButton draws it.
class MarkdownButton extends StatelessWidget {
  final ButtonRule rule;
  const MarkdownButton({required this.rule, super.key});

  @override
  Widget build(BuildContext context) {
    if (!rule.draws) return const SizedBox.shrink();
    var theme = ThemeNotifier.of(context);

    return Align(
      alignment: rule.align,
      child: ElevatedButton(
        style: rule.role == null ? null : theme.buttonStyle(rule.role!),
        onPressed: () => followMarkdownLink(context, rule.link),
        child: Text(rule.label),
      ),
    );
  }
}
