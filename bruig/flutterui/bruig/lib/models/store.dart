import 'dart:async';
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

  /// _orderNtfns is the shop telling this client somebody has ordered.
  ///
  /// Listened to because the order book is read once and then sits there:
  /// an order placed while the seller has the shop open did not appear
  /// until something else happened to reload it, which in practice meant
  /// pressing an unrelated button and noticing.
  StreamSubscription<SSPlacedOrder>? _orderNtfns;

  /// [ordersPlaced] is the shop saying somebody has ordered, or null for a
  /// shop that will not be told -- which is every test, and anything built
  /// before there is a client to hear it from.
  ///
  /// Handed in rather than taken from golib. That stream allows one
  /// listener and keeps it even after a cancel, and ClientModel has been
  /// that listener since before the shop had a seller's screen -- so taking
  /// it here threw on the second listen and brought the whole Pages area
  /// down with it.
  StoreModel(this._pages, {Stream<SSPlacedOrder>? ordersPlaced}) {
    _orderNtfns = ordersPlaced?.listen((_) => loadStore());
  }

  @override
  void dispose() {
    _orderNtfns?.cancel();
    super.dispose();
  }

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

  @visibleForTesting
  Future<StoreIndexLayout> fetchIndexLayout() => Golib.storeIndexLayout();

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

  /// sendOrderGoods sends an order's files again.
  ///
  /// The files go out when payment lands; this is the same send, asked for
  /// deliberately -- for when a buyer says nothing arrived, and because it
  /// is the only way to exercise the whole path without a payment.
  Future<void> sendOrderGoods(String user, int order) =>
      Golib.sendOrderGoods(user, order);

  // ---- the shop's pictures ----

  List<StoreAsset> _assets = const [];
  List<StoreAsset> get assets => _assets;

  Future<void> loadAssets() async {
    _assets = await Golib.listStoreAssets();
    notifyListeners();
  }

  Future<void> deleteAsset(String name) async {
    _assets = await Golib.deleteStoreAsset(name);
    notifyListeners();
  }

  // ---- how the shop front lays a product out ----
  //
  // Kept in the store's own directory rather than in this client's config,
  // because it is a fact about this shop: a seller who copies the shop's
  // folder to another machine takes their front page with them. See
  // simplestore/storefront.go.

  StoreIndexLayout _indexLayout = const StoreIndexLayout();
  StoreIndexLayout get indexLayout => _indexLayout;

  Future<void> loadIndexLayout() async {
    _indexLayout = await Golib.storeIndexLayout();
    notifyListeners();
  }

  /// _indexTemplate is the front page as it stands, or empty when it could
  /// not be read.
  ///
  /// Held so the settings screen can say when a setting cannot reach the
  /// page. A shop's templates are copied in when the shop is made and are
  /// the seller's own from then on, so a front page written before a setting
  /// existed goes on drawing what it always drew -- the setting saves, shows
  /// what it saved, and changes nothing. Three rounds of "this does not
  /// work" turned out to be that, which is why the screen asks rather than
  /// stating what it assumes.
  String _indexTemplate = "";
  String get indexTemplate => _indexTemplate;

  /// frontPageMissing names the calls the shipped front page makes that this
  /// shop's front page does not, or empty for one that is up to date.
  List<String> get frontPageMissing {
    // Through the getter rather than the field, so a test can stand in a
    // front page without a golib to read one from.
    var page = indexTemplate;
    if (page.isEmpty) return const [];
    return [
      for (var call in const ["productCard", "storeGrid", "storePage"])
        if (!page.contains(call)) call
    ];
  }

  @visibleForTesting
  Future<String> fetchIndexTemplate() async {
    try {
      return await Golib.readStoreTemplate("index.tmpl");
    } catch (_) {
      // Not being able to read it is not worth an error on a screen about
      // something else: what it buys is a warning, and no warning is the
      // same as the warning not applying.
      return "";
    }
  }

  /// setIndexLayout changes what one product looks like on the shop front.
  ///
  /// What the store made of it is kept rather than what was asked for: the
  /// store decides what a setting may be, and a screen showing one thing
  /// beside a shop doing another is the hardest kind of thing to work out.
  Future<void> setIndexLayout(StoreIndexLayout layout) async {
    _indexLayout = await Golib.setStoreIndexLayout(layout);
    notifyListeners();
  }

  // ---- the pages the shop renders ----

  List<StoreTemplate> _templates = const [];
  List<StoreTemplate> get templates => _templates;

  Future<void> loadTemplates() async {
    _templates = await Golib.listStoreTemplates();
    notifyListeners();
  }

  Future<String> readTemplate(String name) => Golib.readStoreTemplate(name);

  /// writeTemplate saves one of the shop's pages.
  ///
  /// Refused by the shop if it will not render, which is the point of doing
  /// it here rather than letting somebody edit the file directly: a page
  /// with a typo in it is that page down for every visitor.
  Future<void> writeTemplate(String name, String body) async {
    await Golib.writeStoreTemplate(name, body);
    await loadTemplates();
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
  Future<String> addStoreAssetBytes(String name, Uint8List data,
      {String folder = ""}) async {
    var recorded = await Golib.addStoreAsset(name, data, folder: folder);
    // The listing is what the Pictures tab draws, so a picture added from
    // anywhere -- a product's cover, or the tab itself -- has to reach it.
    await loadAssets();
    return recorded;
  }

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
      _indexLayout = await fetchIndexLayout();
      _indexTemplate = await fetchIndexTemplate();
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
