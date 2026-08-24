import 'dart:typed_data';

import 'package:bruig/models/pages.dart';
import 'package:flutter/foundation.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:golib_plugin/golib_plugin.dart';

// store.dart is the seller's side of a shop: its catalogue, its order book,
// and the product being written.
//
// Its own model rather than more of PagesModel. The two were one because a
// shop and a site are hosted by the same client and switched on in the same
// place -- but that is where the overlap ends. A catalogue is not a page, an
// order is not a picture, and the only thing this needs from hosting is
// where the shop lives and whether there is one.
//
// That much it asks for rather than holding: [PagesModel] owns the hosting
// configuration, because what is being served is one question with one
// answer, and two models each keeping their own copy of it is how a shop
// comes to be served from somewhere the site does not know about.

/// ProductDraft is a product being written. See PageDraft for why it is out
/// here; the fields are strings because that is what is in the boxes, and a
/// half-typed price is not a number yet.
@immutable
class ProductDraft {
  /// original is the product being changed, or an empty one for a new
  /// product -- kept so saving can carry over anything not on the form.
  final ManagedProduct original;
  final String title;
  final String sku;
  final String description;
  final String price;
  final String tags;
  final String sendFilename;
  final bool shipping;
  final bool disabled;

  /// image names a picture in the shop's assets, or is empty for a product
  /// with none.
  final String image;

  const ProductDraft({
    required this.original,
    this.title = "",
    this.sku = "",
    this.description = "",
    this.price = "",
    this.tags = "",
    this.sendFilename = "",
    this.shipping = false,
    this.disabled = false,
    this.image = "",
  });

  factory ProductDraft.of(ManagedProduct p) => ProductDraft(
        original: p,
        title: p.title,
        sku: p.sku,
        description: p.description,
        price: p.price == 0 ? "" : p.price.toString(),
        tags: p.tags.join(", "),
        sendFilename: p.sendFilename,
        shipping: p.shipping,
        disabled: p.disabled,
        image: p.image,
      );

  bool get isNew => original.sku.isEmpty;

  ProductDraft copyWith({
    String? title,
    String? sku,
    String? description,
    String? price,
    String? tags,
    String? sendFilename,
    bool? shipping,
    bool? disabled,
    String? image,
  }) =>
      ProductDraft(
        original: original,
        title: title ?? this.title,
        sku: sku ?? this.sku,
        description: description ?? this.description,
        price: price ?? this.price,
        tags: tags ?? this.tags,
        sendFilename: sendFilename ?? this.sendFilename,
        shipping: shipping ?? this.shipping,
        disabled: disabled ?? this.disabled,
        image: image ?? this.image,
      );
}

/// PagesModel holds the Pages section's own state: which tab is open, what
/// this client hosts, and what is known about other people's sites.
///
/// Out here rather than in the screen for the same reason
/// [ManageContentNavModel] is: every screen is rebuilt from scratch by its
/// route, so anything kept in State is lost by stepping over to Chat and
/// back -- and a site check that has to be redone on every visit is a
/// message paid for twice.

/// StoreModel is the shop as its seller sees it.
class StoreModel extends ChangeNotifier {
  /// _pages answers where the shop is and whether one is being hosted at
  /// all. Nothing else is read from it.
  final PagesModel _pages;
  StoreModel(this._pages);

  ProductDraft? _productDraft;
  ProductDraft? get productDraft => _productDraft;

  void startProductDraft(ManagedProduct p) {
    _productDraft = ProductDraft.of(p);
    notifyListeners();
  }

  void updateProductDraft(ProductDraft draft) => _productDraft = draft;

  void endProductDraft() {
    _productDraft = null;
    notifyListeners();
  }

  @visibleForTesting
  Future<List<ManagedProduct>> fetchProducts() => Golib.listStoreProducts();

  @visibleForTesting
  Future<List<ManagedOrder>> fetchOrders() => Golib.listStoreOrders();

  /// addOrderComment answers a buyer on one order.
  ///
  /// The buyer has been able to write on an order since the shop was built,
  /// and the store has always been able to record a reply -- there was
  /// simply nowhere in the app to read one or write one back, so a buyer
  /// asking when something ships got silence.
  Future<void> addOrderComment(String user, int order, String comment) async {
    _orders = await Golib.addStoreOrderComment(user, order, comment);
    notifyListeners();
  }

  /// restoreStoreTemplates puts the shipped shop templates back.
  ///
  /// The shop reads its templates from disk and parses them once, so this
  /// reloads as well -- otherwise the shop goes on serving what it read at
  /// start-up and the restore looks like it did nothing.
  Future<void> restoreStoreTemplates() async {
    await Golib.restoreStoreTemplates();
    await loadStore();
  }

  /// addStoreAssetBytes writes an already-encoded picture into the shop and
  /// gives back the name a product records.
  ///
  /// The shop's own directory, not the site's: a product's picture is served
  /// by the store, and a shop hosted without a site would otherwise have
  /// nowhere to keep one.
  Future<String> addStoreAssetBytes(String name, Uint8List data) =>
      Golib.addStoreAsset(name, data);

  // ---- the store ----
  //
  // Products and orders are read on demand rather than kept in step with the
  // running store: the store reloads its catalogue from disk on every change,
  // so the files are the record and this is a view of them.

  List<ManagedProduct> _products = const [];
  List<ManagedProduct> get products => _products;

  List<ManagedOrder> _orders = const [];
  List<ManagedOrder> get orders => _orders;

  String? _storeError;
  String? get storeError => _storeError;

  bool _loadingStore = false;
  bool get loadingStore => _loadingStore;

  /// loadStore reads the catalogue and order book. A store that is not being
  /// hosted is not an error worth showing -- the UI offers to switch one on
  /// instead -- so the lists are simply left empty.
  Future<void> loadStore() async {
    await _pages.hostReady;
    if (!_pages.hostConfig.hostsStore) {
      _products = const [];
      _orders = const [];
      _storeError = null;
      notifyListeners();
      return;
    }

    _loadingStore = true;
    notifyListeners();
    try {
      _products = await fetchProducts();
      _orders = await fetchOrders();
      _storeError = null;
    } catch (exception) {
      _storeError = "$exception";
    } finally {
      _loadingStore = false;
      notifyListeners();
    }
  }

  Future<void> saveProduct(ManagedProduct product, String file) async {
    _products = await Golib.saveStoreProduct(product, file);
    notifyListeners();
  }

  Future<void> deleteProduct(String sku) async {
    _products = await Golib.deleteStoreProduct(sku);
    notifyListeners();
  }

  Future<void> setOrderStatus(String user, int order, String status) async {
    _orders = await Golib.setStoreOrderStatus(user, order, status);
    notifyListeners();
  }
}
