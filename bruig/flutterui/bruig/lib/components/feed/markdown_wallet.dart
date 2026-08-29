import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:golib_plugin/golib_plugin.dart';
import 'package:golib_plugin/util.dart';
import 'package:markdown/markdown.dart' as md;

// markdown_wallet.dart is what the reader's own wallet can do, said on a page
// the reader did not write:
//
//   --wallet[need=0.31000000, show=ln onchain]--
//
// A shop cannot know this. The balance belongs to whoever is looking at the
// page, it is never sent anywhere, and the whole of what this block does is
// read it here and put it beside a number the page already showed.
//
// It exists because of what the checkout is for. A buyer choosing between
// Lightning and on-chain is choosing with one fact missing -- whether either
// of them will actually go through -- and the way they used to find out was
// to place the order, press pay, and read a failure about routing. That tells
// nobody whose end was short. The answer was always one number away.
//
// Nothing here refuses anything. It is a figure and a sentence next to a
// choice, and a buyer who wants to try anyway still can: the balance can be
// out of date by the time they pay, a payment that cannot be split may still
// fail inside a figure that says it fits, and an on-chain payment can come
// from a wallet this app has never seen.

/// WalletRule is what one of these asked for.
@immutable
class WalletRule {
  /// need is the amount this order comes to, in DCR, or null for a page that
  /// only wants the figures shown.
  final double? need;

  /// showLN and showOnChain are which halves to draw, so a shop that takes
  /// one kind of payment does not report on the other.
  final bool showLN;
  final bool showOnChain;

  const WalletRule({this.need, this.showLN = true, this.showOnChain = true});

  static WalletRule parse(String? attributes) {
    var fields = <String, String>{};
    for (var part in (attributes ?? "").split(",")) {
      var at = part.indexOf("=");
      if (at == -1) continue;
      fields.putIfAbsent(part.substring(0, at).trim().toLowerCase(),
          () => part.substring(at + 1).trim());
    }

    var show = (fields["show"] ?? "ln onchain").toLowerCase();
    var need = double.tryParse((fields["need"] ?? "").trim());
    return WalletRule(
      need: need == null || need <= 0 ? null : need,
      showLN: show.contains("ln"),
      showOnChain: show.contains("onchain"),
    );
  }

  bool get draws => showLN || showOnChain;
}

class WalletBlockSyntax extends md.BlockSyntax {
  static final _open = RegExp(r'^\s*--wallet(?:\[([^\]]*)\])?--\s*$');

  @override
  RegExp get pattern => _open;

  @override
  md.Node? parse(md.BlockParser parser) {
    var attributes = _open.firstMatch(parser.current.content)?.group(1);
    parser.advance();

    var element = md.Element.text("wallet", "");
    if (attributes != null) element.attributes["attrs"] = attributes;

    // Inside a paragraph, for the reason every other block here is: this
    // renderer treats only a fixed list of tags as blocks.
    return md.Element("p", [element]);
  }
}

class WalletMarkdownElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) =>
      MarkdownWallet(rule: WalletRule.parse(element.attributes["attrs"]));
}

/// MarkdownWallet draws it.
class MarkdownWallet extends StatefulWidget {
  final WalletRule rule;
  const MarkdownWallet({required this.rule, super.key});

  @override
  State<MarkdownWallet> createState() => _MarkdownWalletState();
}

class _MarkdownWalletState extends State<MarkdownWallet> {
  /// _sendable is the most this wallet can send over Lightning, in DCR, and
  /// _onChain is what is confirmed in the on-chain wallet. Null while nobody
  /// has answered yet.
  double? _sendable;
  double? _onChain;

  /// _asked is whether the wallet has answered at all, either way.
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      var balances = await Golib.lnGetBalances();
      if (!mounted) return;
      setState(() {
        // Atoms, both of them. dcrlnd's max outbound is what the channels
        // can send between them once their reserves are set aside, summed --
        // reading it as milli-atoms is what once made every wallet in the
        // app look as though it held a thousandth of what it does.
        _sendable = atomsToDCR(balances.channel.maxOutboundAmount);
        _onChain = atomsToDCR(balances.wallet.confirmedBalance);
        _asked = true;
      });
    } catch (exception) {
      // A wallet that will not answer is not a wallet that cannot pay. The
      // block draws nothing rather than saying something it does not know:
      // "we could not read your balance" on a checkout page reads as a
      // problem with the shop.
      debugPrint("Unable to read wallet balances: $exception");
      if (mounted) setState(() => _asked = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.rule.draws) return const SizedBox.shrink();
    if (!_asked || (_sendable == null && _onChain == null)) {
      return const SizedBox.shrink();
    }

    var theme = ThemeNotifier.of(context);
    var colors = theme.colors;
    var base = Theme.of(context).textTheme.bodyMedium ??
        const TextStyle(fontSize: 14);
    var quiet = base.copyWith(color: colors.onSurfaceVariant, fontSize: 12);

    var need = widget.rule.need;
    var lnCovers = need == null || (_sendable ?? 0) >= need;
    var chainCovers = need == null || (_onChain ?? 0) >= need;

    // Whether anything the shop offers can cover it. A shop taking only one
    // kind of payment is judged on that one: an on-chain balance is no
    // comfort to a buyer whose only route is a channel that is short.
    var covered = (widget.rule.showLN && lnCovers) ||
        (widget.rule.showOnChain && chainCovers);

    var rows = <Widget>[
      if (widget.rule.showLN)
        _line(
          context: context,
          label: "Lightning",
          amount: _sendable,
          suffix: "sendable",
          ok: lnCovers,
          judge: need != null,
        ),
      if (widget.rule.showOnChain)
        _line(
          context: context,
          label: "On-chain wallet",
          amount: _onChain,
          suffix: "confirmed",
          ok: chainCovers,
          judge: need != null,
        ),
    ];

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Your wallet", style: quiet),
          const SizedBox(height: 6),
          ...rows,
          if (need != null && !covered) ...[
            const SizedBox(height: 6),
            Text(
              "That is less than this order comes to. You can top up your "
              "wallet, or pay from another Decred wallet if this shop takes "
              "on-chain payments.",
              style: quiet.copyWith(color: colors.error),
            ),
          ],
          if (widget.rule.showOnChain) ...[
            const SizedBox(height: 6),
            Text(
              "An on-chain payment can come from any Decred wallet, not only "
              "this one.",
              style: quiet,
            ),
          ],
        ],
      ),
    );
  }

  /// _line is one balance and what it means for this order.
  Widget _line({
    required BuildContext context,
    required String label,
    required double? amount,
    required String suffix,
    required bool ok,
    required bool judge,
  }) {
    var theme = ThemeNotifier.of(context);
    var colors = theme.colors;
    var base = Theme.of(context).textTheme.bodyMedium ??
        const TextStyle(fontSize: 14);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (judge) ...[
            Icon(
              ok ? Icons.check_circle_outline : Icons.remove_circle_outline,
              size: 15,
              color: ok ? colors.primary : colors.error,
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              "$label — ${formatDCR(amount ?? 0)} $suffix",
              style: base.copyWith(fontSize: 13),
            ),
          ),
          if (judge)
            Text(
              ok ? "enough" : "not enough",
              style: base.copyWith(
                fontSize: 12,
                color: ok ? colors.onSurfaceVariant : colors.error,
              ),
            ),
        ],
      ),
    );
  }
}
