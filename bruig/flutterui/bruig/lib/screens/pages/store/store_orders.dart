import 'package:bruig/components/pages/add_picture_dialog.dart';
import 'package:bruig/components/buttons.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/config.dart';
import 'package:bruig/models/pages.dart';
import 'package:bruig/models/store.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:golib_plugin/definitions.dart';

// store_orders.dart is the order book: one order at a glance, and what has
// been said about it.
//
// The thread is the half that was missing for a long time. A buyer could
// write on an order and the store could record a reply, but there was
// nowhere in the app to read one or write one back.

class OrderRow extends StatelessWidget {
  final ManagedOrder order;
  final void Function(String) onStatus;
  final Future<void> Function(String) onReply;
  const OrderRow({
    required this.order,
    required this.onStatus,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    var who = order.userNick.isNotEmpty ? order.userNick : order.user;
    var items = order.cart.items.fold<int>(0, (n, i) => n + i.quantity);
    var unanswered =
        order.comments.isNotEmpty && !order.comments.last.fromAdmin;

    // An order that has been written on and not answered says so on its
    // face. A seller should not have to open every order to find the one
    // with a question in it -- which, with nowhere to read a comment at
    // all, is what they had to do, by looking somewhere else entirely.
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      leading: const Icon(Icons.receipt_long_outlined),
      title: Row(children: [
        Flexible(child: Txt.M("#${order.id} · $who")),
        if (unanswered) ...[
          const SizedBox(width: 8),
          const Icon(Icons.mark_chat_unread_outlined, size: 15),
        ],
      ]),
      subtitle: Txt.S(
          "$items item${items == 1 ? "" : "s"} · "
          "\$${order.total.toStringAsFixed(2)}"
          "${order.comments.isEmpty ? "" : " · ${order.comments.length} "
              "message${order.comments.length == 1 ? "" : "s"}"}",
          color: TextColor.onSurfaceVariant),
      trailing: DropdownButton<String>(
        value: ssOrderStatuses.contains(order.status) ? order.status : null,
        hint: Txt.S(order.status),
        underline: const SizedBox.shrink(),
        items: ssOrderStatuses
            .map((s) => DropdownMenuItem(value: s, child: Txt.S(s)))
            .toList(),
        onChanged: (v) => v == null ? null : onStatus(v),
      ),
      children: [OrderThread(order: order, onReply: onReply)],
    );
  }
}

/// _OrderThread is what has been said about one order, and a way to say
/// something back.
///
/// Both halves of this have been built since the shop was: a buyer can write
/// on an order and the store records a reply. There was nowhere in the app
/// to read one or write one, so a buyer asking when something ships got
/// silence, and the seller never knew they had asked.
class OrderThread extends StatefulWidget {
  final ManagedOrder order;
  final Future<void> Function(String) onReply;
  const OrderThread({super.key, required this.order, required this.onReply});

  @override
  State<OrderThread> createState() => _OrderThreadState();
}

class _OrderThreadState extends State<OrderThread> {
  final _reply = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    var text = _reply.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.onReply(text);
      // Cleared only once it is sent. A box emptied on a failure is a
      // reply somebody has to type again with nothing to copy from.
      _reply.clear();
    } catch (_) {
      // Said by whoever asked us to send. The box keeps what was typed.
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.order.comments.isEmpty)
        const Txt.S("Nothing has been said about this order.",
            color: TextColor.onSurfaceVariant)
      else
        for (var c in widget.order.comments)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Txt.S(
                    "${c.fromAdmin ? "You" : (widget.order.userNick.isNotEmpty ? widget.order.userNick : "The buyer")} · "
                    "${DateFormat("d MMM, HH:mm").format(c.timestamp)}",
                    color: TextColor.onSurfaceVariant),
                const SizedBox(height: 2),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: c.fromAdmin
                        ? theme.colors.surfaceContainerHighest
                        : theme.colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Txt.M(c.comment),
                ),
              ],
            ),
          ),
      const SizedBox(height: 4),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _reply,
            decoration: const InputDecoration(
              hintText: "Reply to the buyer",
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _send(),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: _sending ? null : _send,
          child: Txt.S(_sending ? "Sending…" : "Send"),
        ),
      ]),
    ]);
  }
}

/// ProductEditor writes one catalogue entry. A product with an empty SKU is
/// a new one.
