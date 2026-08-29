import 'dart:async';
import 'dart:ui';

import 'package:bruig/components/pages/forms.dart';
import 'package:bruig/theming_system/model/button_style.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

// markdown_countdown.dart is a price with a clock on it:
//
//   --countdown[seconds=1260, link=/reorder/00000001, label=Order it again]--
//
// A shop quotes an amount in DCR at the rate it struck when the order was
// placed, and holds it for a while. The page said how long in words -- "the
// amount holds for another 21 minutes" -- and then went on saying it. Twenty
// minutes later it still said twenty-one, because a page is fetched once and
// nothing tells it the time.
//
// So the number is counted here, where there is a clock. Seconds remaining
// rather than the moment it runs out: the page is drawn by the shop and read
// by somebody else, and an absolute time would be compared against the
// reader's own clock -- two machines a few minutes apart disagreeing about an
// order neither of them is wrong about.
//
// At nought it stops being a warning and becomes what happened. The shop
// calls a lapsed order off on its own and puts the stock back, so what the
// reader needs at that point is not a countdown at nought: it is that nothing
// was charged, and one press to start again at today's rate.

/// CountdownRule is one clock.
@immutable
class CountdownRule {
  /// seconds is how long was left when the page was drawn.
  final int seconds;

  /// link is where "start again" goes, or empty for a clock with nothing to
  /// offer when it runs out.
  final String link;
  final String label;

  const CountdownRule({
    this.seconds = 0,
    this.link = "",
    this.label = "Order it again",
  });

  bool get draws => seconds > 0 || link.isNotEmpty;

  static CountdownRule parse(String? attributes) {
    var fields = <String, String>{};
    for (var part in (attributes ?? "").split(",")) {
      var at = part.indexOf("=");
      if (at == -1) continue;
      fields.putIfAbsent(part.substring(0, at).trim().toLowerCase(),
          () => part.substring(at + 1).trim());
    }

    var seconds = int.tryParse((fields["seconds"] ?? "").trim()) ?? 0;
    var label = (fields["label"] ?? "").trim();
    return CountdownRule(
      seconds: seconds < 0 ? 0 : seconds,
      link: (fields["link"] ?? "").trim(),
      label: label.isEmpty ? "Order it again" : label,
    );
  }
}

class CountdownBlockSyntax extends md.BlockSyntax {
  static final _open = RegExp(r'^\s*--countdown(?:\[([^\]]*)\])?--\s*$');

  @override
  RegExp get pattern => _open;

  @override
  md.Node? parse(md.BlockParser parser) {
    var attributes = _open.firstMatch(parser.current.content)?.group(1);
    parser.advance();

    var element = md.Element.text("countdown", "");
    if (attributes != null) element.attributes["attrs"] = attributes;

    // Inside a paragraph, for the reason every other block here is: this
    // renderer treats only a fixed list of tags as blocks.
    return md.Element("p", [element]);
  }
}

class CountdownMarkdownElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) =>
      MarkdownCountdown(rule: CountdownRule.parse(element.attributes["attrs"]));
}

/// leftOnAClock is how much time is left, as a clock reads it.
///
/// Digits rather than words, and this is the whole of why the first version
/// looked broken. "Another 21 minutes" is a true and useful sentence that
/// changes once a minute -- so somebody who looks at it to see whether it is
/// counting watches nothing happen for up to sixty seconds and concludes it
/// is not. A second hand is the only part of a clock that answers that.
///
/// Hours only when there are any: an amount held for a quarter of an hour
/// reading "0:14:32" is a clock pretending it might be needed for longer.
String leftOnAClock(int seconds) {
  if (seconds <= 0) return "0:00";
  var m = (seconds ~/ 60) % 60;
  var s = seconds % 60;
  var h = seconds ~/ 3600;
  var mm = h > 0 ? m.toString().padLeft(2, "0") : m.toString();
  return "${h > 0 ? "$h:" : ""}$mm:${s.toString().padLeft(2, "0")}";
}

/// MarkdownCountdown draws it.
class MarkdownCountdown extends StatefulWidget {
  final CountdownRule rule;
  const MarkdownCountdown({required this.rule, super.key});

  @override
  State<MarkdownCountdown> createState() => _MarkdownCountdownState();
}

class _MarkdownCountdownState extends State<MarkdownCountdown> {
  late int _left = widget.rule.seconds;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    if (_left > 0) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _left -= 1;
          if (_left <= 0) {
            _left = 0;
            _tick?.cancel();
          }
        });
      });
    }
  }

  @override
  void didUpdateWidget(MarkdownCountdown old) {
    super.didUpdateWidget(old);
    // A fresh page is a fresh answer: fetching the order again is how the
    // reader gets a true number, and this must take it rather than carry on
    // from where the last one had got to.
    if (widget.rule.seconds != old.rule.seconds) {
      _left = widget.rule.seconds;
      _tick?.cancel();
      if (_left > 0) {
        _tick = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(() {
            _left -= 1;
            if (_left <= 0) {
              _left = 0;
              _tick?.cancel();
            }
          });
        });
      }
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.rule.draws) return const SizedBox.shrink();
    var theme = ThemeNotifier.of(context);
    var colors = theme.colors;
    var base =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14);

    var lapsed = _left <= 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.error),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            lapsed
                ? Text(
                    "The quoted amount has lapsed. Nothing has been charged, "
                    "and the shop calls an order off when its price runs out.",
                    style: base,
                  )
                : Text.rich(
                    TextSpan(children: [
                      const TextSpan(text: "The amount holds for another "),
                      TextSpan(
                        text: leftOnAClock(_left),
                        style: base.copyWith(
                          fontWeight: FontWeight.w700,
                          // Even digits, so the line does not shuffle
                          // sideways every time a 1 becomes a 4.
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const TextSpan(
                          text: ", after which the rate is worked out again."),
                    ]),
                    style: base,
                  ),
            if (lapsed && widget.rule.link.isNotEmpty) ...[
              const SizedBox(height: 10),
              ElevatedButton(
                style: theme.buttonStyle(ButtonRole.primary),
                onPressed: () =>
                    postToPage(context, widget.rule.link, const {}),
                child: Text(widget.rule.label),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
