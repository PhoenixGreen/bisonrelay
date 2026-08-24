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

/// StoreTab is the seller's side of the store: the catalogue and the order
/// book.
///
/// Buyers see none of this. They read the markdown pages the store renders,
/// which is the same catalogue seen from the other end -- so a product saved
/// here is on sale as soon as it is written, without a restart: the store
/// watches its own directory and reloads.
class StoreTab extends StatefulWidget {
  final PagesModel pages;

  /// store is the catalogue and the order book. Separate from [pages],
  /// which answers only where the shop is served from and whether one is
  /// being hosted -- see StoreModel.
  final StoreModel store;
  const StoreTab(this.pages, this.store, {super.key});

  @override
  State<StoreTab> createState() => _StoreTabState();
}

class _StoreTabState extends State<StoreTab> {
  PagesModel get pages => widget.pages;
  StoreModel get store => widget.store;

  // The product being edited, or null when the lists are showing. An empty
  // ManagedProduct is a new one.

  @override
  void initState() {
    super.initState();
    store.loadStore();
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
      await store.loadStore();
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
      await store.loadStore();
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
      await store.loadStore();
    } catch (exception) {
      snackbar.error("Unable to change the store directory: $exception");
    }
  }

  void deleteProduct(String sku) async {
    var snackbar = SnackBarModel.of(context);
    try {
      await store.deleteProduct(sku);
    } catch (exception) {
      snackbar.error("Unable to delete product: $exception");
    }
  }

  /// replyToOrder answers a buyer on one order.
  ///
  /// Rethrows after saying so, because the thread clears its box only on a
  /// reply that went -- a box emptied on a failure is a reply somebody has
  /// to type again with nothing to copy from.
  Future<void> replyToOrder(ManagedOrder order, String text) async {
    var snackbar = SnackBarModel.of(context);
    try {
      await store.addOrderComment(order.user, order.id, text);
    } catch (exception) {
      snackbar.error("Unable to reply to the buyer: $exception");
      rethrow;
    }
  }

  void setStatus(ManagedOrder order, String status) async {
    var snackbar = SnackBarModel.of(context);
    try {
      await store.setOrderStatus(order.user, order.id, status);
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
        var draft = store.productDraft;
        if (draft != null) {
          return _ProductEditor(
            // Keyed on which product is being written, so switching from
            // one to another builds a fresh editor rather than reusing the
            // first one's boxes.
            key: ValueKey(
                "product-draft-${draft.original.file}/${draft.original.sku}"),
            pages: pages,
            store: store,
            onDone: store.endProductDraft,
          );
        }
        return _StoreOverview(
          pages: pages,
          store: store,
          onDisable: disableStore,
          onChooseDir: chooseDir,
          onNew: () => store.startProductDraft(ManagedProduct.empty()),
          onEdit: store.startProductDraft,
          onDelete: deleteProduct,
          onStatus: setStatus,
          onReply: replyToOrder,
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
  final StoreModel store;
  final VoidCallback onDisable;
  final VoidCallback onChooseDir;
  final VoidCallback onNew;
  final void Function(ManagedProduct) onEdit;
  final void Function(String) onDelete;
  final void Function(ManagedOrder, String) onStatus;
  final Future<void> Function(ManagedOrder, String) onReply;
  const _StoreOverview({
    required this.pages,
    required this.store,
    required this.onDisable,
    required this.onChooseDir,
    required this.onNew,
    required this.onEdit,
    required this.onDelete,
    required this.onStatus,
    required this.onReply,
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
          onPressed: () => _restoreTemplates(context, store),
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
        ...store.orders.map((o) => _OrderRow(
              order: o,
              onStatus: (status) => onStatus(o, status),
              onReply: (text) => onReply(o, text),
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

class _OrderRow extends StatelessWidget {
  final ManagedOrder order;
  final void Function(String) onStatus;
  final Future<void> Function(String) onReply;
  const _OrderRow({
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

/// _ProductEditor writes one catalogue entry. A product with an empty SKU is
/// a new one.
class _ProductEditor extends StatefulWidget {
  final PagesModel pages;
  final StoreModel store;
  final VoidCallback onDone;
  const _ProductEditor({
    super.key,
    required this.pages,
    required this.store,
    required this.onDone,
  });

  @override
  State<_ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends State<_ProductEditor> {
  StoreModel get store => widget.store;

  late final TextEditingController titleCtrl;
  late final TextEditingController skuCtrl;
  late final TextEditingController descCtrl;
  late final TextEditingController priceCtrl;
  late final TextEditingController tagsCtrl;
  late final TextEditingController sendCtrl;
  late bool shipping;
  late bool disabled;
  bool saving = false;

  ProductDraft get draft =>
      widget.store.productDraft ?? ProductDraft.of(ManagedProduct.empty());
  bool get isNew => draft.isNew;

  @override
  void initState() {
    super.initState();
    // Seeded from the draft, not from the product: coming back to one left
    // half-written has to bring back what was typed, not what was saved.
    var d = draft;
    titleCtrl = TextEditingController(text: d.title);
    skuCtrl = TextEditingController(text: d.sku);
    descCtrl = TextEditingController(text: d.description);
    priceCtrl = TextEditingController(text: d.price);
    tagsCtrl = TextEditingController(text: d.tags);
    sendCtrl = TextEditingController(text: d.sendFilename);
    shipping = d.shipping;
    disabled = d.disabled;
    for (var c in [
      titleCtrl,
      skuCtrl,
      descCtrl,
      priceCtrl,
      tagsCtrl,
      sendCtrl
    ]) {
      c.addListener(remember);
    }
  }

  /// remember hands the boxes to the model, which outlives this screen.
  /// Deliberately not notifying -- see PagesModel's draft section.
  void remember() => widget.store.updateProductDraft(draft.copyWith(
        title: titleCtrl.text,
        sku: skuCtrl.text,
        description: descCtrl.text,
        price: priceCtrl.text,
        tags: tagsCtrl.text,
        sendFilename: sendCtrl.text,
        shipping: shipping,
        disabled: disabled,
      ));

  @override
  void dispose() {
    for (var c in [
      titleCtrl,
      skuCtrl,
      descCtrl,
      priceCtrl,
      tagsCtrl,
      sendCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// chooseImage adds a picture to the shop and records its name.
  ///
  /// The shop's own pictures, not the site's: a product's picture is served
  /// by the store, and a shop hosted without a site would otherwise have
  /// nowhere to keep one.
  void chooseImage() async {
    var snackbar = SnackBarModel.of(context);
    try {
      var path =
          await pickAndAddShopPicture(context, widget.pages, widget.store);
      if (path == null || !mounted) return;
      // The name alone. A product records "guitar.jpg" and the template
      // builds the rest, so the directory is named in one place.
      var name = path.split("/").last;
      setState(
          () => widget.store.updateProductDraft(draft.copyWith(image: name)));
    } catch (exception) {
      snackbar.error("Unable to add the picture: $exception");
    }
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
      await widget.store.saveProduct(
        draft.original.copyWith(
          title: titleCtrl.text.trim(),
          sku: skuCtrl.text.trim(),
          description: descCtrl.text,
          price: price,
          tags: tags,
          sendFilename: sendCtrl.text.trim(),
          shipping: shipping,
          disabled: disabled,
          image: draft.image,
        ),
        draft.original.file,
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
        Expanded(child: Txt.L(isNew ? "New product" : draft.original.title)),
      ]),
      const SizedBox(height: 12),
      TextField(
        controller: titleCtrl,
        decoration: const InputDecoration(
            isDense: true, labelText: "Title", border: OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      _ProductPicture(
        image: draft.image,
        onChoose: chooseImage,
        onClear: () =>
            widget.store.updateProductDraft(draft.copyWith(image: "")),
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
          // Which currency, because nothing else says. Somebody entering
          // 20 meaning 20 DCR would price their goods at a fraction of what
          // they meant and have no way to notice: the shop quotes in USD
          // and works the DCR amount out from it at checkout.
          labelText: "Price (USD)",
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
        onChanged: (v) => setState(() {
          shipping = v;
          remember();
        }),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Txt.M("Hidden"),
        subtitle: const Txt.S(
            "Kept in the catalogue, but not offered for sale.",
            color: TextColor.onSurfaceVariant),
        value: disabled,
        onChanged: (v) => setState(() {
          disabled = v;
          remember();
        }),
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

/// _ProductPicture is the product's picture, and the way to change it.
///
/// Named rather than shown: the picture is served by the shop, and this
/// screen is the seller's own -- it has no session to fetch one through. The
/// name is what a product records, so seeing it is seeing what was saved.
class _ProductPicture extends StatelessWidget {
  final String image;
  final VoidCallback onChoose;
  final VoidCallback onClear;
  const _ProductPicture({
    required this.image,
    required this.onChoose,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
        const Icon(Icons.image_outlined, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Txt.S(
            image.isEmpty ? "No picture" : image,
            overflow: TextOverflow.ellipsis,
            color: image.isEmpty ? TextColor.onSurfaceVariant : null,
          ),
        ),
        if (image.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            tooltip: "Use no picture",
            onPressed: onClear,
          ),
        OutlinedButton.icon(
          onPressed: onChoose,
          icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
          label: Text(image.isEmpty ? "Add a picture" : "Change"),
        ),
      ]);
}

/// _restoreTemplates asks before writing over a seller's own work.
///
/// The confirmation says which files go and which stay, because "restore
/// defaults" on its own does not say whether the products are about to go
/// with them -- and somebody who has to guess will not press it.
Future<void> _restoreTemplates(BuildContext context, StoreModel store) async {
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
