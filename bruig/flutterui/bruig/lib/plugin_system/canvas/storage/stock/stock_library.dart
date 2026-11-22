import 'package:bruig/plugin_system/canvas/storage/stock/stock_sources.dart';

// stock_library.dart is what the Stock panel can show: a library searched
// over the network (StockSource), or one of the libraries browsed instead
// (StockBrowser). One value for either, so the panel's choice and the saved
// preference cannot hold a string that is neither.

/// StockBrowser is a library browsed rather than searched: Kenney's free
/// sprites, the characters drawn here, or KayKit's characters to download.
/// None needs a key.
enum StockBrowser {
  kenney("Kenney's sprites"),
  characters("Drawn characters"),
  kayKit("KayKit 3D characters");

  /// label is what the Library dropdown calls it.
  final String label;
  const StockBrowser(this.label);
}

/// StockLibrary is the library the Stock panel shows: a source to search, or
/// a browser.
sealed class StockLibrary {
  const StockLibrary();

  /// StockLibrary.initial is the library shown before another is chosen.
  static const StockLibrary initial =
      StockSourceLibrary(StockSource.pixabayPictures);

  /// StockLibrary.all is every library, in the order the dropdown lists
  /// them: the sources, then the browsers.
  static final List<StockLibrary> all = List.unmodifiable([
    for (var s in StockSource.values) StockSourceLibrary(s),
    for (var b in StockBrowser.values) StockBrowserLibrary(b),
  ]);

  /// _browserPrefix is put before a browser's name when it is saved. The
  /// sources and the browsers name themselves independently, so a source
  /// added one day as "characters" would otherwise be read back as the
  /// browser, or the browser as it.
  static const _browserPrefix = "browser:";

  /// name is how the library is saved, which [fromName] reads.
  String get name;

  /// label is what the Library dropdown calls it.
  String get label;

  /// fromName is the library saved as [name], or [initial] for anything it
  /// does not know: a source or browser since taken out, or nothing saved.
  static StockLibrary fromName(Object? name) {
    if (name is! String) return initial;
    if (name.startsWith(_browserPrefix)) {
      var browser = StockBrowser.values
          .asNameMap()[name.substring(_browserPrefix.length)];
      return browser == null ? initial : StockBrowserLibrary(browser);
    }
    var source = StockSource.values.asNameMap()[name];
    return source == null ? initial : StockSourceLibrary(source);
  }
}

/// StockSourceLibrary is a library searched over the network.
final class StockSourceLibrary extends StockLibrary {
  final StockSource source;
  const StockSourceLibrary(this.source);

  @override
  String get name => source.name;

  @override
  String get label => source.label;

  @override
  bool operator ==(Object other) =>
      other is StockSourceLibrary && other.source == source;

  @override
  int get hashCode => source.hashCode;
}

/// StockBrowserLibrary is a library browsed in the panel, not searched.
final class StockBrowserLibrary extends StockLibrary {
  final StockBrowser browser;
  const StockBrowserLibrary(this.browser);

  @override
  String get name => "${StockLibrary._browserPrefix}${browser.name}";

  @override
  String get label => browser.label;

  @override
  bool operator ==(Object other) =>
      other is StockBrowserLibrary && other.browser == browser;

  @override
  int get hashCode => browser.hashCode;
}
