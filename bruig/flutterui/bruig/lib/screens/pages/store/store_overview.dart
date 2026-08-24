import 'package:bruig/components/buttons.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/config.dart';
import 'package:bruig/models/pages.dart';
import 'package:bruig/models/store.dart';
import 'package:bruig/screens/pages/store/store_orders.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/definitions.dart';

// store_overview.dart is the shop as its seller opens it: whether a shop is
// being hosted at all, the catalogue, and the order book beneath it.

class StoreOff extends StatelessWidget {
  final VoidCallback onEnable;
  final bool editable;
  final String mode;
  const StoreOff(
      {super.key, required this.onEnable, required this.editable, required this.mode});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.storefront_outlined, size: 40),
          const SizedBox(height: 12),
          const Txt.L("No store"),
          const SizedBox(height: 6),
          const Txt.S(
              "A store lists products on your site and takes orders over "
              "Lightning or on-chain, paid and delivered without anyone else "
              "in between.",
              color: TextColor.onSurfaceVariant,
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          if (editable)
            ElevatedButton.icon(
              style: raisedButtonStyle(ThemeNotifier.of(context)),
              onPressed: onEnable,
              icon: const Icon(Icons.add_business_outlined, size: 16),
              label: const Text("Set up a store"),
            )
          else
            Txt.S("Hosting is set to \"$mode\" in the config file.",
                color: TextColor.onSurfaceVariant),
        ]),
      ),
    );
  }
}

class StoreOverview extends StatelessWidget {
  final PagesModel pages;
  final StoreModel store;
  final VoidCallback onDisable;
  final VoidCallback onChooseDir;
  final VoidCallback onNew;
  final void Function(ManagedProduct) onEdit;
  final void Function(String) onDelete;
  final void Function(ManagedOrder, String) onStatus;
  final Future<void> Function(ManagedOrder, String) onReply;
  final Future<void> Function(ManagedOrder) onSendGoods;
  const StoreOverview({super.key, 
    required this.pages,
    required this.store,
    required this.onDisable,
    required this.onChooseDir,
    required this.onNew,
    required this.onEdit,
    required this.onDelete,
    required this.onStatus,
    required this.onReply,
    required this.onSendGoods,
  });

  @override
  Widget build(BuildContext context) {
    var cfg = pages.hostConfig;
    var open = store.orders
        .where((o) => o.status != "completed" && o.status != "canceled")
        .toList();

    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        const Expanded(child: Txt.L("Store")),
        OutlinedButton.icon(
          onPressed: onChooseDir,
          icon: const Icon(Icons.folder_open, size: 16),
          label: const Text("Change folder"),
        ),
        const SizedBox(width: 8),
        OutlinedButton(onPressed: onDisable, child: const Text("Turn off")),
        const SizedBox(width: 8),
        // A shop's templates are copied in when the shop is made and are
        // the seller's own from then on, so a template shipped or changed
        // later never reaches a shop that already exists. Offered rather
        // than done on start-up: these are files somebody may have spent an
        // afternoon on, and there is no undo.
        OutlinedButton.icon(
          onPressed: () => restoreTemplates(context, store),
          icon: const Icon(Icons.restart_alt, size: 16),
          label: const Text("Restore default pages"),
        ),
      ]),
      const SizedBox(height: 4),
      Txt.S("Serving from ${displayPath(cfg.storePath)}",
          color: TextColor.onSurfaceVariant),
      if (store.storeError != null) ...[
        const SizedBox(height: 8),
        Txt.S(store.storeError!, color: TextColor.onErrorContainer),
      ],
      const SizedBox(height: 20),

      // Orders first: they are the part with someone waiting on the other
      // end of it.
      Row(children: [
        const Expanded(child: Txt.L("Orders")),
        if (open.isNotEmpty)
          Txt.S("${open.length} open", color: TextColor.onSurfaceVariant),
      ]),
      const SizedBox(height: 8),
      if (store.orders.isEmpty)
        const Txt.S("No orders yet.", color: TextColor.onSurfaceVariant)
      else
        ...store.orders.map((o) => OrderRow(
              order: o,
              onStatus: (status) => onStatus(o, status),
              onReply: (text) => onReply(o, text),
              onSendGoods: () => onSendGoods(o),
            )),

      const SizedBox(height: 28),
      Row(children: [
        const Expanded(child: Txt.L("Products")),
        ElevatedButton.icon(
          style: raisedButtonStyle(ThemeNotifier.of(context)),
          onPressed: onNew,
          icon: const Icon(Icons.add, size: 16),
          label: const Text("New product"),
        ),
      ]),
      const SizedBox(height: 8),
      if (store.products.isEmpty)
        const Txt.S("Nothing on sale yet.", color: TextColor.onSurfaceVariant)
      else
        ...store.products.map((p) => _ProductRow(
              product: p,
              onEdit: () => onEdit(p),
              onDelete: () => onDelete(p.sku),
            )),
    ]);
  }
}

class _ProductRow extends StatelessWidget {
  final ManagedProduct product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _ProductRow(
      {required this.product, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    var parts = [
      "\$${product.price.toStringAsFixed(2)}",
      product.sku,
      if (product.sendFilename.isNotEmpty) "sends ${product.sendFilename}",
      if (product.shipping) "shipped",
      if (product.disabled) "not on sale",
    ];

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(product.disabled
          ? Icons.visibility_off_outlined
          : Icons.sell_outlined),
      title: Txt.M(product.title),
      subtitle: Txt.S(parts.join(" · "), color: TextColor.onSurfaceVariant),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 18),
          tooltip: "Edit ${product.title}",
          onPressed: onEdit,
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 18),
          tooltip: "Delete ${product.title}",
          onPressed: onDelete,
        ),
      ]),
      onTap: onEdit,
    );
  }
}

Future<void> restoreTemplates(BuildContext context, StoreModel store) async {
  var snackbar = SnackBarModel.of(context);
  var ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text("Restore the shop's default pages?"),
      content: const Txt.M(
          "The shop's pages -- its front, a product, the cart, the order "
          "list -- are written back as they ship, and anything you have "
          "changed in them is lost.\n\n"
          "Your products and orders are not touched."),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancel")),
        TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Restore")),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await store.restoreStoreTemplates();
    snackbar.success("The shop's pages are back to their defaults.");
  } catch (exception) {
    snackbar.error("Unable to restore the shop's pages: $exception");
  }
}
