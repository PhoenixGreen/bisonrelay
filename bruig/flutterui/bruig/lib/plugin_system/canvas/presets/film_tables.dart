import 'package:bruig/plugin_system/canvas/model/colour_cube.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// film_tables.dart is the colour tables that come with the app: film looks
// from the HaldCLUT collection by Pat David, Juan Melara and Marc Roovers
// (CC BY-SA 4.0; see assets/canvas/luts/SOURCES.md), named by look rather
// than by the film each approximates.

const filmTablesAsset = "assets/canvas/luts/film_tables.bin.gz";

/// filmTablesCredit is said wherever the tables are offered.
const filmTablesCredit = "Film tables by Pat David, Juan Melara and Marc "
    "Roovers (CC BY-SA 4.0): approximations of each look, made by no film "
    "maker.";

/// FilmTable is one of the tables, as the panel offers it.
class FilmTable {
  final String id;
  final String name;
  final String group;
  const FilmTable(this.id, this.name, this.group);
}

const filmTables = [
  FilmTable("portrait-warm", "Portrait, warm", "Colour negative"),
  FilmTable("portrait-cool", "Portrait, cool", "Colour negative"),
  FilmTable("portrait-fast", "Portrait, fast", "Colour negative"),
  FilmTable("everyday", "Everyday", "Colour negative"),
  FilmTable("everyday-punchy", "Everyday, punchy", "Colour negative"),
  FilmTable("night", "Night, grainy", "Colour negative"),
  FilmTable("redscale", "Redscale", "Colour negative"),
  FilmTable("slide-vivid", "Slide, vivid", "Slide"),
  FilmTable("slide-warm", "Slide, warm classic", "Slide"),
  FilmTable("slide-soft", "Slide, soft", "Slide"),
  FilmTable("slide-saturated", "Slide, saturated", "Slide"),
  FilmTable("cross-process", "Cross-processed", "Slide"),
  FilmTable("cinema-warm", "Cinema print, warm", "Cinema"),
  FilmTable("cinema-cool", "Cinema print, cool", "Cinema"),
  FilmTable("instant-warm", "Instant, warm", "Instant"),
  FilmTable("instant-cold", "Instant, cold", "Instant"),
  FilmTable("instant-slide", "Instant, colour slide", "Instant"),
  FilmTable("summer-heat", "Summer heat", "Toned"),
  FilmTable("sepia", "Sepia colour", "Toned"),
  FilmTable("antique", "Antique", "Toned"),
  FilmTable("bw-press", "Black and white, press", "Black and white"),
  FilmTable("bw-fine", "Black and white, fine", "Black and white"),
  FilmTable("bw-fast", "Black and white, fast", "Black and white"),
  FilmTable("bw-ortho", "Black and white, ortho", "Black and white"),
  FilmTable("bw-infrared", "Black and white, infrared", "Black and white"),
  FilmTable("bw-instant", "Black and white, instant", "Black and white"),
];

/// FilmTables holds the tables once read; until then a table draws as no
/// table, and [ready] says when they arrive.
class FilmTables {
  FilmTables._();

  static Map<String, ColourCube> _tables = const {};
  static Future<void>? _loading;
  static final ValueNotifier<bool> ready = ValueNotifier(false);

  static ColourCube? of(String id) => _tables[id];

  static String nameOf(String id) =>
      filmTables.where((t) => t.id == id).firstOrNull?.name ?? id;

  static Future<void> load() => _loading ??= _read();

  static Future<void> _read() async {
    try {
      var data = await rootBundle.load(filmTablesAsset);
      _tables = readFilmTables(data.buffer.asUint8List());
      ready.value = true;
    } catch (exception) {
      debugPrint("The film tables did not load: $exception");
      // Asked again next time, not left empty for the run.
      _loading = null;
    }
  }
}
