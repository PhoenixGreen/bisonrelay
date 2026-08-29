import 'dart:async';

import 'package:bruig/components/feed/markdown_copy.dart';
import 'package:bruig/components/feed/markdown_qr.dart';
import 'package:bruig/components/pages/forms.dart';
import 'package:bruig/components/tooltips.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:golib_plugin/golib_plugin.dart';
import 'package:markdown/markdown.dart' as md;

// markdown_paynow.dart pays an on-chain order from the wallet in this app:
//
//   --paynow[addr=DsSomeAddress, amount=0.31000000, account=default]--
//
// The other half of the pay page is a square to point a phone at and an
// address to copy, and both are for paying from somewhere else. Bison Relay
// has a wallet of its own with coins in it, and until this existed the way to
// use it was to copy the shop's address out of the page, open the wallet
// screen, paste it in, and type the amount by hand -- inside an app that
// already knew all three.
//
// A Lightning order needs none of this: its invoice is already a button, and
// pressing it pays. This is that button for the on-chain half.
//
// It sends once. An on-chain payment cannot be taken back, and a second press
// while the first is in flight is a second transaction -- so the button is
// gone the moment it is pressed, and what replaces it says what happened.

/// PayNowRule is what one button pays.
@immutable
class PayNowRule {
  final String addr;
  final double amount;

  /// account is the wallet account the coins come out of.
  final String account;

  /// order is the page to go to once the payment has a confirmation, or
  /// empty for a button that only sends.
  ///
  /// The buyer is left on a page that says "waiting", and the thing they are
  /// waiting for happens somewhere they cannot see. Something has to notice
  /// and move them on, and the only party watching both the wallet and this
  /// page is this widget.
  final String order;

  const PayNowRule({
    this.addr = "",
    this.amount = 0,
    this.account = "default",
    this.order = "",
  });

  /// draws is whether there is a payment to make. An address with no amount
  /// is not one: this button never asks how much, so a page that does not
  /// say cannot have one.
  bool get draws => addr.isNotEmpty && amount > 0;

  static PayNowRule parse(String? attributes) {
    var fields = <String, String>{};
    for (var part in (attributes ?? "").split(",")) {
      var at = part.indexOf("=");
      if (at == -1) continue;
      fields.putIfAbsent(part.substring(0, at).trim().toLowerCase(),
          () => part.substring(at + 1).trim());
    }

    var amount = double.tryParse((fields["amount"] ?? "").trim()) ?? 0;
    var account = (fields["account"] ?? "").trim();
    return PayNowRule(
      addr: (fields["addr"] ?? "").trim(),
      amount: amount <= 0 ? 0 : amount,
      account: account.isEmpty ? "default" : account,
      order: (fields["order"] ?? "").trim(),
    );
  }
}

class PayNowBlockSyntax extends md.BlockSyntax {
  static final _open = RegExp(r'^\s*--paynow(?:\[([^\]]*)\])?--\s*$');

  @override
  RegExp get pattern => _open;

  @override
  md.Node? parse(md.BlockParser parser) {
    var attributes = _open.firstMatch(parser.current.content)?.group(1);
    parser.advance();

    var element = md.Element.text("paynow", "");
    if (attributes != null) element.attributes["attrs"] = attributes;

    // Inside a paragraph, for the reason every other block here is: this
    // renderer treats only a fixed list of tags as blocks.
    return md.Element("p", [element]);
  }
}

class PayNowMarkdownElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) =>
      MarkdownPayNow(rule: PayNowRule.parse(element.attributes["attrs"]));
}

/// _Sending is where the press has got to.
///
/// sent and confirmed are two states, not one. An on-chain payment that has
/// left the wallet has not arrived: between them is the gap the whole page is
/// about, and a button that says "Sent" and then nothing is a button that
/// stops talking exactly when the buyer starts wondering.
enum _Sending { ready, inFlight, sent, confirmed, failed }

/// MarkdownPayNow draws it.
class MarkdownPayNow extends StatefulWidget {
  final PayNowRule rule;
  const MarkdownPayNow({required this.rule, super.key});

  @override
  State<MarkdownPayNow> createState() => _MarkdownPayNowState();
}

class _MarkdownPayNowState extends State<MarkdownPayNow> {
  _Sending _state = _Sending.ready;
  String _failed = "";

  /// _txid is what was sent, once it has been.
  String _txid = "";

  /// _watch polls this wallet for the transaction's first confirmation.
  ///
  /// This wallet rather than the shop, because the shop cannot be asked: a
  /// page is fetched, it does not receive anything, and nothing here is told
  /// when an order changes. The wallet that sent the coins is watching the
  /// same chain the shop is, and it is in this app.
  Timer? _watch;

  /// _every is how often to look.
  ///
  /// A Decred block is about five minutes, so this is a slow question with a
  /// slow answer. Twenty seconds is often enough that the page moves on while
  /// somebody is still looking at it, and rare enough to be nothing at all.
  static const _every = Duration(seconds: 20);

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  Future<void> _send() async {
    if (_state != _Sending.ready) return;
    var snackbar = SnackBarModel.of(context);
    setState(() => _state = _Sending.inFlight);

    try {
      var txid = await Golib.sendOnChain(
          widget.rule.addr, widget.rule.amount, widget.rule.account);
      if (!mounted) return;
      setState(() {
        _state = _Sending.sent;
        _txid = txid;
      });
      snackbar.success("Sent ${dcrLabel(widget.rule.amount)} to the shop");
      _startWatching();
    } catch (exception) {
      if (!mounted) return;
      // Back to ready: a send that did not happen is one worth trying
      // again, and the buyer is the only one who can decide that.
      setState(() {
        _state = _Sending.failed;
        _failed = "$exception";
      });
      snackbar.error("Unable to send the payment: $exception");
    }
  }

  void _startWatching() {
    if (_txid.isEmpty) return;
    _watch?.cancel();
    _watch = Timer.periodic(_every, (_) => _look());
  }

  /// _look asks whether the transaction has made it into a block yet.
  ///
  /// Best effort. A wallet that will not answer leaves the page saying what
  /// it already says, which is true -- the payment is still waiting -- and
  /// the shop marks the order regardless of whether anybody is watching.
  Future<void> _look() async {
    try {
      var txs = await Golib.listTransactions(0, 0);
      var confirmed = txs.any((t) => t.txHash == _txid && t.blockHeight > 0);
      if (!confirmed || !mounted) return;

      _watch?.cancel();
      setState(() => _state = _Sending.confirmed);

      // On to the order, which is where the answer lives: what was bought,
      // what happens next, and the seller's own messages about it.
      if (widget.rule.order.isNotEmpty) {
        await postToPage(context, widget.rule.order, {});
      }
    } catch (exception) {
      debugPrint("Unable to check for a confirmation: $exception");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.rule.draws) return const SizedBox.shrink();

    var theme = ThemeNotifier.of(context);
    var colors = theme.colors;
    var base =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14);

    var (icon, title, under, live) = switch (_state) {
      _Sending.ready => (
          Icons.account_balance_wallet_outlined,
          "Pay with your Bison Relay wallet",
          "Sends ${dcrLabel(widget.rule.amount)} straight to the shop.",
          true,
        ),
      _Sending.inFlight => (
          Icons.hourglass_top_rounded,
          "Sending…",
          "Do not close this page until it has gone.",
          false,
        ),
      _Sending.sent => (
          Icons.hourglass_bottom_rounded,
          "Sent — waiting for 1 confirmation",
          "About five minutes. Nothing more is needed from you, and this page "
              "moves on by itself when it arrives.",
          false,
        ),
      _Sending.confirmed => (
          Icons.check_circle_outline,
          "Confirmed",
          "The network has it. Taking you to your order.",
          false,
        ),
      _Sending.failed => (
          Icons.error_outline,
          "That did not go through",
          _failed,
          true,
        ),
    };

    var accent = switch (_state) {
      _Sending.failed => colors.error,
      _ => colors.primary,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: live
            ? accent.withValues(alpha: 0.08)
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: live ? _send : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent, width: live ? 2 : 1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 34, color: accent),
                const SizedBox(height: 10),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: base.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface),
                ),
                const SizedBox(height: 6),
                Text(
                  under,
                  textAlign: TextAlign.center,
                  style: base.copyWith(
                      fontSize: 12, color: colors.onSurfaceVariant),
                ),
                // The transaction, as soon as there is one.
                //
                // It is the only thing the buyer can check for themselves
                // while they wait. Without it the page says "waiting" and
                // offers nothing to look at, which is the whole of what makes
                // that gap uncomfortable.
                if (_txid.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  MarkdownCopy(
                    data: _txid,
                    rule: const CopyRule(label: "Transaction — press to copy"),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------------
// The two ways to pay one on-chain order, side by side:
//
//   --payways[addr=DsSomeAddress, amount=0.31000000]--
//
// Left, a square to point a phone at with the address under it, for a wallet
// somewhere else. Right, the wallet in this app. Both are ways of sending the
// same coins to the same place, so they are one block rather than two: they
// are the same height because a choice whose halves are different sizes reads
// as one option and one afterthought, and neither can say that about itself.
//
// It was a run of columns for one commit. Stretching them looked like the
// answer and was not: a column stretches what it is given, and what it is
// given is a whole document rendered as a block that is as tall as its own
// content. The height had to belong to whatever draws both halves.

/// payWaysExternal and payWaysInternal name the two halves, so a test can
/// hold each to the promise the block makes about them: that they are the
/// same height.
const Key payWaysExternal = Key("payways-external");
const Key payWaysInternal = Key("payways-internal");

/// PayWaysRule is one on-chain order's pay area.
@immutable
class PayWaysRule {
  final PayNowRule pay;

  /// help is what each half keeps behind a question mark.
  ///
  /// "The shop watches for your payment and marks the order as soon as the
  /// network confirms it" is true of both halves and read every time by
  /// everybody who already knows it -- and it was a paragraph under the two
  /// of them, which is where a reader looking at a square to scan is not.
  final String help;

  /// dcr is the amount as the page writes it, for the sentence under the
  /// square -- "0.3100 DCR" rather than the eight places the coins move in.
  final String dcr;

  const PayWaysRule({
    this.pay = const PayNowRule(),
    this.dcr = "",
    this.help = "",
  });

  bool get draws => pay.draws;

  /// uri is what the square encodes: the address and the amount together, in
  /// the form Decrediton and Cake Wallet both read. An address on its own
  /// leaves the amount to be typed in by hand, and an order is paid by
  /// sending exactly what it was quoted.
  String get uri =>
      "decred:${pay.addr}?amount=${pay.amount.toStringAsFixed(8)}";
}

class PayWaysBlockSyntax extends md.BlockSyntax {
  static final _open = RegExp(r'^\s*--payways(?:\[([^\]]*)\])?--\s*$');

  @override
  RegExp get pattern => _open;

  @override
  md.Node? parse(md.BlockParser parser) {
    var attributes = _open.firstMatch(parser.current.content)?.group(1);
    parser.advance();

    var element = md.Element.text("payways", "");
    if (attributes != null) element.attributes["attrs"] = attributes;
    return md.Element("p", [element]);
  }
}

class PayWaysMarkdownElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    // key=value pairs, and a fragment with no key of its own carries on the
    // value before it -- so a setting can hold a sentence, and a sentence
    // has commas in it.
    var fields = <String, String>{};
    String? last;
    for (var part in (element.attributes["attrs"] ?? "").split(",")) {
      var at = part.indexOf("=");
      if (at == -1) {
        if (last != null) fields[last] = "${fields[last]},$part";
        continue;
      }
      var key = part.substring(0, at).trim().toLowerCase();
      fields.putIfAbsent(key, () => part.substring(at + 1).trim());
      last = key;
    }

    return MarkdownPayWays(
      rule: PayWaysRule(
        pay: PayNowRule.parse(element.attributes["attrs"]),
        dcr: fields["dcr"] ?? "",
        help: fields["help"] ?? "",
      ),
    );
  }
}

/// MarkdownPayWays draws both halves.
class MarkdownPayWays extends StatelessWidget {
  final PayWaysRule rule;
  const MarkdownPayWays({required this.rule, super.key});

  /// _stackBelow is the room the pair needs before one goes under the other.
  ///
  /// A square is 180 points and does not shrink usefully, so half of a
  /// chat-width window is a code with an address squeezed beside it.
  static const double _stackBelow = 520;
  static const double _gap = 12;

  /// _qrSize is how large the square is drawn, and _qrBox is what
  /// [MarkdownQr] adds around it: eight points of padding and a hairline on
  /// each side.
  static const double _qrSize = 170;
  static const double _qrBox = 18;

  @override
  Widget build(BuildContext context) {
    if (!rule.draws) return const SizedBox.shrink();
    var theme = ThemeNotifier.of(context);
    var colors = theme.colors;
    var base =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14);

    // The question mark in each half's corner, over whatever is in it.
    Widget asked(Widget half) {
      if (rule.help.isEmpty) return half;
      return Stack(
        children: [
          half,
          Positioned(
            top: 0,
            right: 0,
            child: HelpTooltip(
              message: rule.help,
              triggerMode: TooltipTriggerMode.tap,
              showDuration: const Duration(seconds: 8),
              constraints: const BoxConstraints(maxWidth: 260),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(Icons.help_outline,
                    size: 16, color: colors.onSurfaceVariant),
              ),
            ),
          ),
        ],
      );
    }

    var external = Container(
      key: payWaysExternal,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Pay with an external Decred wallet",
            textAlign: TextAlign.center,
            style: base.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          // Boxed to a height it is told rather than one it works out.
          //
          // The row below measures its halves so they can match, and the
          // package that draws the square lays itself out inside a
          // LayoutBuilder -- which cannot be asked for an intrinsic height at
          // all. A tight height is answered by the box itself without the
          // question ever reaching the square.
          SizedBox(
            height: _qrSize + _qrBox,
            child: MarkdownQr(
              data: rule.uri,
              rule: const QrRule(size: _qrSize, align: Alignment.center),
            ),
          ),
          const SizedBox(height: 8),
          MarkdownCopy(
            data: rule.pay.addr,
            rule: const CopyRule(label: "Press to copy the address"),
          ),
          const SizedBox(height: 6),
          Text(
            rule.dcr.isEmpty
                ? "Scanning the code fills in the address and the amount."
                : "Send exactly ${rule.dcr}. Scanning the code fills in both.",
            textAlign: TextAlign.center,
            style: base.copyWith(fontSize: 12, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );

    var internal = MarkdownPayNow(key: payWaysInternal, rule: rule.pay);

    // The full width of the page: a block is sized to its content by the
    // column the page is built from, and two halves that are only as wide as
    // what is in them are not halves of anything.
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth.isFinite &&
              constraints.maxWidth < _stackBelow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                asked(external),
                const SizedBox(height: _gap),
                asked(internal),
              ],
            );
          }

          // IntrinsicHeight is what makes the halves match: the taller one sets
          // the height and the other stretches to it.
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: asked(external)),
                const SizedBox(width: _gap),
                Expanded(child: asked(internal)),
              ],
            ),
          );
        }),
      ),
    );
  }
}
