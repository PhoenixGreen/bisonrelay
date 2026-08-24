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
import 'package:bruig/screens/pages/store/product_editor.dart';
import 'package:bruig/screens/pages/store/store_overview.dart';
import 'package:bruig/screens/pages/store/store_orders.dart';

// store.dart is the Store section. What is in it is split by what a seller
// is doing: looking at the shop, writing a product, or answering somebody
// about an order.

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
    // Both, because this screen is drawn from both. Hosting says whether
    // there is a shop at all and where it is served from; the shop says what
    // is in it and what is being written.
    //
    // Listening to hosting alone is what splitting the model quietly broke:
    // the catalogue, the orders and the product being edited all moved, so
    // pressing Edit changed the shop and nothing on screen, and the editor
    // appeared only once something else happened to rebuild the page.
    return ListenableBuilder(
      listenable: Listenable.merge([pages, store]),
      builder: (context, _) {
        if (!pages.hostConfig.hostsStore) {
          return StoreOff(
              onEnable: enableStore,
              editable: pages.hostEditable,
              mode: pages.hostConfig.mode);
        }
        var draft = store.productDraft;
        if (draft != null) {
          return ProductEditor(
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
        return StoreOverview(
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
