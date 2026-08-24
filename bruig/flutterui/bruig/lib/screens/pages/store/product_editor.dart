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

// product_editor.dart writes one catalogue entry.
//
// Its own file because it is a form and the rest of the shop is a list: a
// product being written has boxes, validation and a picture to pick, none of
// which the overview has any use for.

class ProductEditor extends StatefulWidget {
  final PagesModel pages;
  final StoreModel store;
  final VoidCallback onDone;
  const ProductEditor({
    super.key,
    required this.pages,
    required this.store,
    required this.onDone,
  });

  @override
  State<ProductEditor> createState() => ProductEditorState();
}

class ProductEditorState extends State<ProductEditor> {
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

/// restoreTemplates asks before writing over a seller's own work.
///
/// The confirmation says which files go and which stay, because "restore
/// defaults" on its own does not say whether the products are about to go
/// with them -- and somebody who has to guess will not press it.
