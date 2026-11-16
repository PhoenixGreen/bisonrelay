// tile_maps.dart is where places sit on the tile map (chart_extra.dart):
// the US states, Europe's countries and the UK's nations and regions, a
// square each, roughly as they lie. Here, not with the painter, so the
// gallery can tell which map a sheet's places are on (chart_presets.dart).

/// europeCountries is where each European country's tile sits, by its
/// two-letter code (GB and UK, GR and EL alike), roughly as the continent
/// lies (Ken, 2026-11-17, the improvements report's tenth item).
const Map<String, (int, int)> europeCountries = {
  "IS": (0, 0), "NO": (5, 0), "SE": (6, 0), "FI": (7, 0), //
  "IE": (1, 1), "GB": (2, 1), "UK": (2, 1), "DK": (5, 1), "LV": (7, 1),
  "EE": (8, 1), //
  "BE": (2, 2), "NL": (3, 2), "DE": (4, 2), "PL": (5, 2), "LT": (6, 2),
  "BY": (7, 2), //
  "FR": (2, 3), "LU": (3, 3), "CZ": (4, 3), "SK": (5, 3), "UA": (6, 3),
  "MD": (7, 3), //
  "PT": (0, 4), "ES": (1, 4), "CH": (3, 4), "AT": (4, 4), "HU": (5, 4),
  "RO": (6, 4), //
  "AD": (1, 5), "MC": (2, 5), "IT": (3, 5), "SI": (4, 5), "HR": (5, 5),
  "RS": (6, 5), "BG": (7, 5), //
  "MT": (3, 6), "BA": (5, 6), "ME": (6, 6), "MK": (7, 6), "TR": (8, 6), //
  "AL": (6, 7), "GR": (7, 7), "EL": (7, 7), "CY": (9, 7),
};

/// ukRegions is where each of the UK's twelve nations and regions (ITL1)
/// sits: by its short code, or its name.
const Map<String, (int, int)> ukRegions = {
  "SCO": (2, 0),
  "NI": (0, 1),
  "NE": (3, 1),
  "NW": (2, 2),
  "YH": (3, 2),
  "WAL": (1, 3),
  "WM": (2, 3),
  "EM": (3, 3),
  "EE": (4, 3),
  "SW": (1, 4),
  "SE": (2, 4),
  "LDN": (3, 4),
};

const _ukNames = {
  "SCOTLAND": "SCO",
  "NORTHERN IRELAND": "NI",
  "NORTH EAST": "NE",
  "NORTH WEST": "NW",
  "YORKSHIRE AND THE HUMBER": "YH",
  "YORKSHIRE": "YH",
  "WALES": "WAL",
  "WEST MIDLANDS": "WM",
  "EAST MIDLANDS": "EM",
  "EAST OF ENGLAND": "EE",
  "EAST": "EE",
  "SOUTH WEST": "SW",
  "SOUTH EAST": "SE",
  "LONDON": "LDN",
};

/// tileMapOf is the map [codes] are of -- the US states, Europe's
/// countries, or the UK's nations and regions, whichever most of them are
/// -- each code as that map has it; null where most are on none.
(Map<String, (int, int)>, List<String>)? tileMapOf(List<String> codes) {
  var best = 0;
  (Map<String, (int, int)>, List<String>)? out;
  for (var map in [usStates, europeCountries, ukRegions]) {
    var named = [
      for (var c in codes) map == ukRegions ? (_ukNames[c] ?? c) : c,
    ];
    var known = named.where(map.containsKey).length;
    if (known * 2 > codes.length && known > best) {
      best = known;
      out = (map, named);
    }
  }
  return out;
}

/// usStates is where each US state's tile sits, column then row: the
/// layout the tile-map maps of NPR and the like share.
const Map<String, (int, int)> usStates = {
  "AK": (0, 0),
  "ME": (11, 0),
  "VT": (10, 1),
  "NH": (11, 1),
  "WA": (1, 2),
  "ID": (2, 2),
  "MT": (3, 2),
  "ND": (4, 2),
  "MN": (5, 2),
  "IL": (6, 2),
  "WI": (7, 2),
  "MI": (8, 2),
  "NY": (9, 2),
  "RI": (10, 2),
  "MA": (11, 2),
  "OR": (1, 3),
  "NV": (2, 3),
  "WY": (3, 3),
  "SD": (4, 3),
  "IA": (5, 3),
  "IN": (6, 3),
  "OH": (7, 3),
  "PA": (8, 3),
  "NJ": (9, 3),
  "CT": (10, 3),
  "CA": (1, 4),
  "UT": (2, 4),
  "CO": (3, 4),
  "NE": (4, 4),
  "MO": (5, 4),
  "KY": (6, 4),
  "WV": (7, 4),
  "VA": (8, 4),
  "MD": (9, 4),
  "DE": (10, 4),
  "AZ": (2, 5),
  "NM": (3, 5),
  "KS": (4, 5),
  "AR": (5, 5),
  "TN": (6, 5),
  "NC": (7, 5),
  "SC": (8, 5),
  "DC": (9, 5),
  "OK": (4, 6),
  "LA": (5, 6),
  "MS": (6, 6),
  "AL": (7, 6),
  "GA": (8, 6),
  "HI": (0, 7),
  "TX": (4, 7),
  "FL": (9, 7),
};
