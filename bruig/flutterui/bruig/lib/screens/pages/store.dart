import 'package:bruig/components/buttons.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/pages.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/definitions.dart';

/// StoreTab is the seller's side of the store: the catalogue and the order
/// book.
///
/// Buyers see none of this. They read the markdown pages the store renders,
/// which is the same catalogue seen from the other end -- so a product saved
/// here is on sale as soon as it is written, without a restart: the store
/// watches its own directory and reloads.
class StoreTab extends StatefulWidget {
  final PagesModel pages;
  const StoreTab(this.pages, {super.key});

  @override
  State<StoreTab> createState() => _StoreTabState();
}

class _StoreTabState extends State<StoreTab> {
  PagesModel get pages => widget.pages;

  // The product being edited, or null when the lists are showing. An empty
  // ManagedProduct is a new one.
  ManagedProduct? editing;

  @override
  void initState() {
    super.initState();
    pages.loadStore();
  }

  void enableStore() async {
    var snackbar = SnackBarModel.of(context);
    var cfg = pages.hostConfig;
    var path = cfg.storePath.isNotEmpty
        ? cfg.storePath
        : (pages.host?.defaultStorePath ?? "");
    if (path.isEmpty) {
      snackbar.error("No directory to keep the store in.");
      return;
    }

    try {
      await pages.setHost(cfg.copyWith(
        mode: cfg.hostsPages ? pagesHostModeBoth : pagesHostModeStore,
        storePath: path,
      ));
      await pages.loadStore();
    } catch (exception) {
      snackbar.error("Unable to start the store: $exception");
    }
  }

  void disableStore() async {
    var snackbar = SnackBarModel.of(context);
    var cfg = pages.hostConfig;
    try {
      await pages.setHost(cfg.copyWith(
          mode: cfg.hostsPages ? pagesHostModePages : pagesHostModeOff));
      await pages.loadStore();
    } catch (exception) {
      snackbar.error("Unable to stop the store: $exception");
    }
  }

  void chooseDir() async {
    var snackbar = SnackBarModel.of(context);
    var dir = await FilePicker.platform
        .getDirectoryPath(dialogTitle: "Directory to keep the store in");
    if (dir == null) return;
    var cfg = pages.hostConfig;
    try {
      await pages.setHost(cfg.copyWith(
        mode: cfg.hostsPages ? pagesHostModeBoth : pagesHostModeStore,
        storePath: dir,
      ));
      await pages.loadStore();
    } catch (exception) {
      snackbar.error("Unable to change the store directory: $exception");
    }
  }

  void deleteProduct(String sku) async {
    var snackbar = SnackBarModel.of(context);
    try {
      await pages.deleteProduct(sku);
    } catch (exception) {
      snackbar.error("Unable to delete product: $exception");
    }
  }

  void setStatus(ManagedOrder order, String status) async {
    var snackbar = SnackBarModel.of(context);
    try {
      await pages.setOrderStatus(order.user, order.id, status);
    } catch (exception) {
      snackbar.error("Unable to change order status: $exception");
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: pages,
      builder: (context, _) {
        if (!pages.hostConfig.hostsStore) {
          return _StoreOff(
              onEnable: enableStore,
              editable: pages.hostEditable,
              mode: pages.hostConfig.mode);
        }
        if (editing != null) {
          return _ProductEditor(
            pages: pages,
            product: editing!,
            onDone: () => setState(() => editing = null),
          );
        }
        return _StoreOverview(
          pages: pages,
          onDisable: disableStore,
          onChooseDir: chooseDir,
          onNew: () => setState(() => editing = ManagedProduct.empty()),
          onEdit: (p) => setState(() => editing = p),
          onDelete: deleteProduct,
          onStatus: setStatus,
        );
      },
    );
  }
}

class _StoreOff extends StatelessWidget {
  final VoidCallback onEnable;
  final bool editable;
  final String mode;
  const _StoreOff(
      {required this.onEnable, required this.editable, required this.mode});

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

class _StoreOverview extends StatelessWidget {
  final PagesModel pages;
  final VoidCallback onDisable;
  final VoidCallback onChooseDir;
  final VoidCallback onNew;
  final void Function(ManagedProduct) onEdit;
  final void Function(String) onDelete;
  final void Function(ManagedOrder, String) onStatus;
  const _StoreOverview({
    required this.pages,
    required this.onDisable,
    required this.onChooseDir,
    required this.onNew,
    required this.onEdit,
    required this.onDelete,
    required this.onStatus,
  });

  @override
  Widget build(BuildContext context) {
    var cfg = pages.hostConfig;
    var open = pages.orders
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
      ]),
      const SizedBox(height: 4),
      Txt.S("Serving from ${cfg.storePath}",
          color: TextColor.onSurfaceVariant),
      if (pages.storeError != null) ...[
        const SizedBox(height: 8),
        Txt.S(pages.storeError!, color: TextColor.onErrorContainer),
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
      if (pages.orders.isEmpty)
        const Txt.S("No orders yet.", color: TextColor.onSurfaceVariant)
      else
        ...pages.orders.map((o) => _OrderRow(
            order: o, onStatus: (status) => onStatus(o, status))),

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
      if (pages.products.isEmpty)
        const Txt.S("Nothing on sale yet.", color: TextColor.onSurfaceVariant)
      else
        ...pages.products.map((p) => _ProductRow(
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

class _OrderRow extends StatelessWidget {
  final ManagedOrder order;
  final void Function(String) onStatus;
  const _OrderRow({required this.order, required this.onStatus});

  @override
  Widget build(BuildContext context) {
    var who = order.userNick.isNotEmpty ? order.userNick : order.user;
    var items = order.cart.items.fold<int>(0, (n, i) => n + i.quantity);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.receipt_long_outlined),
      title: Txt.M("#${order.id} · $who"),
      subtitle: Txt.S(
          "$items item${items == 1 ? "" : "s"} · "
          "\$${order.total.toStringAsFixed(2)}",
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
    );
  }
}

/// _ProductEditor writes one catalogue entry. A product with an empty SKU is
/// a new one.
class _ProductEditor extends StatefulWidget {
  final PagesModel pages;
  final ManagedProduct product;
  final VoidCallback onDone;
  const _ProductEditor(
      {required this.pages, required this.product, required this.onDone});

  @override
  State<_ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends State<_ProductEditor> {
  late final TextEditingController titleCtrl;
  late final TextEditingController skuCtrl;
  late final TextEditingController descCtrl;
  late final TextEditingController priceCtrl;
  late final TextEditingController tagsCtrl;
  late final TextEditingController sendCtrl;
  late bool shipping;
  late bool disabled;
  bool saving = false;

  bool get isNew => widget.product.sku.isEmpty;

  @override
  void initState() {
    super.initState();
    var p = widget.product;
    titleCtrl = TextEditingController(text: p.title);
    skuCtrl = TextEditingController(text: p.sku);
    descCtrl = TextEditingController(text: p.description);
    priceCtrl =
        TextEditingController(text: p.price == 0 ? "" : p.price.toString());
    tagsCtrl = TextEditingController(text: p.tags.join(", "));
    sendCtrl = TextEditingController(text: p.sendFilename);
    shipping = p.shipping;
    disabled = p.disabled;
  }

  @override
  void dispose() {
    for (var c in [titleCtrl, skuCtrl, descCtrl, priceCtrl, tagsCtrl, sendCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  void save() async {
    var snackbar = SnackBarModel.of(context);
    var price = double.tryParse(priceCtrl.text.trim());
    if (price == null || price < 0) {
      snackbar.error("The price must be a number, and not negative.");
      return;
    }

    var tags = tagsCtrl.text
        .split(",")
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    setState(() => saving = true);
    try {
      await widget.pages.saveProduct(
        widget.product.copyWith(
          title: titleCtrl.text.trim(),
          sku: skuCtrl.text.trim(),
          description: descCtrl.text,
          price: price,
          tags: tags,
          sendFilename: sendCtrl.text.trim(),
          shipping: shipping,
          disabled: disabled,
        ),
        widget.product.file,
      );
      widget.onDone();
    } catch (exception) {
      snackbar.error("Unable to save product: $exception");
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        IconButton(
          icon: const Icon(Icons.arrow_back, size: 18),
          tooltip: "Back to the store",
          onPressed: widget.onDone,
        ),
        Expanded(
            child: Txt.L(isNew ? "New product" : widget.product.title)),
      ]),
      const SizedBox(height: 12),
      TextField(
        controller: titleCtrl,
        decoration: const InputDecoration(
            isDense: true, labelText: "Title", border: OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: skuCtrl,
        decoration: const InputDecoration(
          isDense: true,
          labelText: "SKU",
          helperText: "Identifies this product. Buyers see it in the link.",
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: priceCtrl,
        decoration: const InputDecoration(
          isDense: true,
          labelText: "Price",
          helperText: "In USD; converted to DCR at checkout.",
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: descCtrl,
        maxLines: 4,
        decoration: const InputDecoration(
            isDense: true,
            labelText: "Description",
            alignLabelWithHint: true,
            border: OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: tagsCtrl,
        decoration: const InputDecoration(
            isDense: true,
            labelText: "Tags",
            helperText: "Comma separated",
            border: OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: sendCtrl,
        decoration: const InputDecoration(
          isDense: true,
          labelText: "File to send on payment",
          helperText: "For a digital product. A file in the store folder; "
              "it is sent automatically once the order is paid.",
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 4),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Txt.M("Needs shipping"),
        subtitle: const Txt.S("Asks the buyer for an address at checkout.",
            color: TextColor.onSurfaceVariant),
        value: shipping,
        onChanged: (v) => setState(() => shipping = v),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Txt.M("Hidden"),
        subtitle: const Txt.S("Kept in the catalogue, but not offered for sale.",
            color: TextColor.onSurfaceVariant),
        value: disabled,
        onChanged: (v) => setState(() => disabled = v),
      ),
      const SizedBox(height: 12),
      Row(children: [
        ElevatedButton(
          style: raisedButtonStyle(ThemeNotifier.of(context)),
          onPressed: saving ? null : save,
          child: Text(saving ? "Saving…" : "Save"),
        ),
        const SizedBox(width: 8),
        OutlinedButton(onPressed: widget.onDone, child: const Text("Cancel")),
      ]),
    ]);
  }
}
