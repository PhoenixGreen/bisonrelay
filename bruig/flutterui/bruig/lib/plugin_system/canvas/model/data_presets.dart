import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_data.dart';
import 'package:bruig/plugin_system/canvas/model/football_form.dart';

// data_presets.dart is the recipes that fill a DataSource in.
//
// A general mapping from JSON to rows is the right machinery and the wrong
// starting point: nobody opens a design tool wanting to write "standings.0.
// table" in a text field. A preset is the same mapping, already written, for a
// source somebody is likely to want -- so the ordinary path is choosing a
// league from a list, and the paths underneath stay editable for everything
// else.

/// DataPreset is one named recipe.
class DataPreset {
  final String id;
  final String label;

  /// shortLabel is what a closed section's heading says, where the full label
  /// does not fit beside a title and a button.
  final String shortLabel;

  /// note says what the reader has to do for themselves, which for every one
  /// of these is "get a key".
  final String note;

  /// choices are the interchangeable part of the address -- which competition,
  /// which season -- as a code and a name.
  final List<(String, String)> choices;
  final String choiceLabel;

  final String Function(String choice) address;
  final String rowsPath;

  /// matchColumn identifies a row across a refresh. See DataSource.
  final int matchColumn;

  /// hiddenHeaders are the columns whose names this preset wants kept but not
  /// drawn -- the position and the badge on a league table, both of which need
  /// a name for the mapping and neither of which wants one written over it.
  final List<int> hiddenHeaders;

  final List<SourceColumn> columns;

  /// shape is how the response is laid out. See [DataShape]: a league table
  /// is a list of records, a chain's history is parallel arrays.
  final DataShape shape;

  /// columnsFor is the mapping when it depends on which choice was made.
  ///
  /// A league table is the same columns whichever competition it is. A chain
  /// chart is not: the array holding the values is called "price" for one and
  /// "supply" for the next, and the number in it is in atoms for some and in
  /// blocks for others. So the choice picks the columns rather than only the
  /// address.
  final List<SourceColumn> Function(String choice)? columnsFor;

  /// tables and charts are which elements this recipe is offered to.
  ///
  /// A daily series going back to 2016 is four thousand rows, which is a
  /// chart and is not a table anybody wants on a canvas. A league table is a
  /// table, and a chart of it comes from the table beside it rather than from
  /// a second request -- see [TableLink].
  final bool tables;
  final bool charts;

  /// chartCategory and chartValues are which of the columns a chart uses for
  /// its axis and its series, so choosing a preset leaves a chart drawn
  /// rather than mapped and empty.
  final int chartCategory;
  final List<int> chartValues;

  /// chartType is the drawing this recipe wants, when it wants a particular
  /// one.
  ///
  /// An OHLC source is four columns that mean one thing, and a chart of them
  /// as four lines is not what anybody asking for it wanted. Null for every
  /// other recipe, which leaves the chart drawn however it already was.
  final ChartType? chartType;

  /// chartPoints is how many points to keep. See [ChartElement] -- four
  /// thousand daily figures on a chart eight inches wide is four thousand
  /// bars a third of a pixel apart.
  final int chartPoints;

  /// fields is what a record is known to carry, so the mapping can offer a
  /// list before anything has been fetched.
  final List<String> fields;

  /// derived are the paths this preset fills in itself, whatever the response
  /// said.
  ///
  /// So that a column mapped to one of them is known to be a custom field
  /// even when it carries no template and no spread -- which is how a column
  /// added by hand, before anybody knew the preset would take an interest in
  /// it, ends up. Without this such a column is filled in by the preset and
  /// listed nowhere that explains it, and the settings that lay it out are
  /// behind a section it does not appear in.
  final List<String> derived;

  /// derive fills in what one request cannot answer.
  ///
  /// Given the rows as mapped and a way to fetch more JSON, it returns the
  /// rows again. A preset owns its own quirks this way -- the panel knows
  /// only that some sources need a second look -- and the one that needs it
  /// needs it for a good reason: see footballFormFromResults.
  ///
  /// Null for a source that says everything it has to say in one answer,
  /// which is most of them.
  final Future<List<List<String>>> Function(
    List<List<String>> rows,
    DataSource source,
    Future<dynamic> Function(String url) get,
  )? derive;

  const DataPreset({
    required this.id,
    required this.label,
    required this.shortLabel,
    required this.note,
    required this.choices,
    required this.choiceLabel,
    required this.address,
    required this.rowsPath,
    required this.columns,
    this.matchColumn = -1,
    this.shape = DataShape.records,
    this.columnsFor,
    this.tables = true,
    this.charts = false,
    this.chartCategory = 0,
    this.chartValues = const [1],
    this.chartType,
    this.chartPoints = 0,
    this.hiddenHeaders = const [],
    this.fields = const [],
    this.derived = const [],
    this.derive,
  });

  /// columnsIn is the mapping for one choice. See [columnsFor].
  List<SourceColumn> columnsIn(String choice) =>
      columnsFor?.call(choice) ?? columns;

  /// applyTo is [source] with this recipe written into it.
  DataSource applyTo(DataSource source, String choice) => source.copyWith(
        kind: DataKind.url,
        where: address(choice),
        rowsPath: rowsPath,
        columns: columnsIn(choice),
        matchColumn: matchColumn,
        shape: shape,
        preset: id,
      );
}

/// footballDataColumns is the league table everybody recognises.
///
/// The order is the one every published table uses, and the first column is
/// deliberately the position: it is what the table's own sort pins in place,
/// and having it here means a refreshed table already reads 1, 2, 3 without
/// anybody sorting anything.
const List<SourceColumn> footballDataColumns = [
  SourceColumn(header: "Pos", path: "position"),
  // Named, and hidden on the canvas by TableElement.hiddenHeaders. A column
  // needs a name for the mapping and the order to refer to it; a column of
  // badges wants nothing written over them. Kept, so badges chosen by hand
  // survive a refresh -- see SourceColumn.keep.
  SourceColumn(header: "Badge", path: "team.crest", picture: true, keep: true),
  SourceColumn(header: "Team", path: "team.shortName"),
  SourceColumn(header: "Played", path: "playedGames"),
  SourceColumn(header: "Won", path: "won"),
  SourceColumn(header: "Drawn", path: "draw"),
  SourceColumn(header: "Lost", path: "lost"),
  SourceColumn(header: "For", path: "goalsFor"),
  SourceColumn(header: "Against", path: "goalsAgainst"),
  SourceColumn(header: "GD", path: "goalDifference"),
  SourceColumn(header: "Points", path: "points"),
  // The form guide. Called custom because on the free plan it is: the field
  // exists in the response and is null unless the subscription covers trend
  // data, so it is worked out from the results instead -- see
  // football_form.dart, and the Custom fields section of a table's Data
  // settings, which says so.
  //
  // Six games rather than the five the paid field would have sent, because
  // the results it is built from have no such limit. Padded on the left so
  // the most recent game is in the same place in every row whatever a club
  // has played, and marked off from the ones before it.
  SourceColumn(header: "Custom form", path: "form", spread: 6, divider: "|"),
];

/// footballDataFields is every field a standings record carries, for the
/// mapping's list before a refresh has discovered them.
///
/// Taken from the published response rather than guessed: position, the team
/// four ways, the games, the form, and the eight numbers. The Field dropdown
/// shows whatever actually arrived once a refresh has happened, which is the
/// authority; this is what it can offer before one has.
const List<String> footballDataFields = [
  "position",
  "team.id",
  "team.name",
  "team.shortName",
  "team.tla",
  "team.crest",
  "playedGames",
  "form",
  "won",
  "draw",
  "lost",
  "points",
  "goalsFor",
  "goalsAgainst",
  "goalDifference",
];

/// footballData is football-data.org's standings.
///
/// Recommended over the alternatives for one reason above the others: its
/// standings response is already a league table. Every column below is a field
/// on the record rather than something to be counted up or joined from a
/// second call, so the mapping is a list of names and the refresh is one
/// request. The free tier covers the competitions most people want a table of,
/// including both English divisions, and rate-limits at ten requests a minute
/// -- which for a thing a person presses is no limit at all.
final DataPreset footballData = DataPreset(
  id: "football-data.org",
  label: "Football league table (football-data.org)",
  shortLabel: "Football",
  note: "Needs a free key from football-data.org, which arrives by email. "
      "The key is kept on this machine and never saved into the canvas, so a "
      "canvas you send carries the table and not your key.",
  choiceLabel: "Competition",
  // The free tier's competitions. Codes rather than ids, because a code is
  // readable in the address bar when something is not working.
  choices: const [
    ("PL", "Premier League"),
    ("ELC", "Championship"),
    ("BL1", "Bundesliga"),
    ("SA", "Serie A"),
    ("PD", "La Liga"),
    ("FL1", "Ligue 1"),
    ("DED", "Eredivisie"),
    ("PPL", "Primeira Liga"),
    ("BSA", "Brasileirão"),
    ("CL", "Champions League"),
    ("EC", "European Championship"),
    ("WC", "World Cup"),
  ],
  address: (code) =>
      "https://api.football-data.org/v4/competitions/$code/standings",
  // The response holds a list of standings -- the whole table, then home and
  // away for some competitions -- and the first is the one anybody means.
  rowsPath: "standings.0.table",
  // Rows are identified by the team's name across a refresh, so a column the
  // reader keeps -- their own badges -- follows its club up and down the
  // table rather than staying where it was put.
  matchColumn: 2,
  hiddenHeaders: const [0, 1],
  fields: footballDataFields,
  derived: const ["form"],
  derive: footballFormFromResults,
  columns: footballDataColumns,
);

// ---------------------------------------------------------------------------
// The chain and market series.
//
// Both of these were checked against the live APIs rather than written from
// documentation, because the shape is the whole of the mapping and there is
// nothing to be gained by guessing at it.

/// _DcrChart is one of dcrdata's series: the name in the address, what the
/// array of values is called, and how to make it readable.
class _DcrChart {
  final String name;
  final String label;

  /// field is the array the values are in. Every one of these responds with a
  /// "t" of timestamps and one other array, named for what it holds.
  final String field;

  /// divide brings atoms into DCR. The chain counts money in hundred-
  /// millionths and a chart of two hundred million ticket-atoms is a chart
  /// with the wrong story on it.
  final double divide;

  /// query is what the endpoint needs to answer at all. Most of these bin by
  /// day when asked to; a few return nothing for bin=day and have to be left
  /// to the server's own default.
  final String query;

  const _DcrChart(this.name, this.label, this.field,
      {this.divide = 1, this.query = "bin=day&axis=time"});
}

const List<_DcrChart> _dcrCharts = [
  _DcrChart("coin-supply", "Coin supply (DCR)", "supply",
      divide: 1e8, query: "axis=time"),
  _DcrChart("ticket-price", "Ticket price (DCR)", "price", divide: 1e8),
  _DcrChart("pow-difficulty", "Proof-of-work difficulty", "diff"),
  _DcrChart("hashrate", "Hashrate", "rate"),
  _DcrChart("tx-count", "Transactions per day", "count", query: "axis=time"),
  _DcrChart("fees", "Fees paid (DCR)", "fees", divide: 1e8),
  _DcrChart("ticket-pool-size", "Tickets in the pool", "count",
      query: "axis=time"),
  _DcrChart("block-size", "Block size (bytes)", "size"),
  _DcrChart("duration-btw-blocks", "Seconds between blocks", "duration"),
  _DcrChart("missed-votes", "Missed votes", "missed", query: "axis=time"),
];

_DcrChart _dcrChart(String name) => _dcrCharts.firstWhere((c) => c.name == name,
    orElse: () => _dcrCharts.first);

/// dcrdataChart is Decred's own chain history.
///
/// No key, no account, and the numbers are the chain's rather than an
/// exchange's opinion of it. The response is parallel arrays -- an array of
/// timestamps and an array of values -- which is why [DataShape.columns]
/// exists.
final DataPreset dcrdataChart = DataPreset(
  id: "dcrdata.decred.org",
  label: "Decred chain history (dcrdata)",
  shortLabel: "dcrdata",
  note: "No key needed. dcrdata is Decred's own block explorer, so these are "
      "the chain's figures rather than an exchange's.",
  choiceLabel: "Series",
  choices: [for (var c in _dcrCharts) (c.name, c.label)],
  address: (name) =>
      "https://dcrdata.decred.org/api/chart/$name?${_dcrChart(name).query}",
  // The arrays are the document itself, so there is no path to the rows.
  rowsPath: "",
  shape: DataShape.columns,
  tables: false,
  charts: true,
  chartCategory: 0,
  chartValues: const [1],
  // Daily since 2016 is four thousand points. A chart is read at a glance and
  // a canvas is eight inches wide.
  chartPoints: 120,
  fields: const ["t", "supply", "price", "diff", "rate", "count", "fees"],
  columns: const [],
  columnsFor: (name) {
    var chart = _dcrChart(name);
    return [
      const SourceColumn(header: "Date", path: "t", date: "MMM yy"),
      SourceColumn(
          header: chart.label, path: chart.field, divide: chart.divide),
    ];
  },
);

/// _geckoCoins is the list offered rather than every coin there is.
///
/// CoinGecko has thousands, and a dropdown of thousands is a worse way to
/// choose one than typing its name into the address. These are the ones
/// somebody building a canvas in this app is likely to want, Decred first.
const List<(String, String)> _geckoCoins = [
  ("decred", "Decred"),
  ("bitcoin", "Bitcoin"),
  ("ethereum", "Ethereum"),
  ("monero", "Monero"),
  ("litecoin", "Litecoin"),
  ("zcash", "Zcash"),
  ("dash", "Dash"),
  ("solana", "Solana"),
];

/// coinGeckoPrice is a coin's price history.
///
/// Recommended over CoinMarketCap for the reason that decides it: the free
/// tier here answers with history, and CoinMarketCap's answers with the
/// latest price only. A chart of one point is not a chart.
///
/// The response is a list of two-element arrays -- [when, what] -- so the
/// paths into a record are "0" and "1". That falls out of the existing walker
/// rather than needing anything new: a number in a path is a list index.
final DataPreset coinGeckoPrice = DataPreset(
  id: "coingecko.price",
  label: "Coin price history (CoinGecko)",
  shortLabel: "CoinGecko",
  note: "No key needed on the free plan, which is rate-limited to a handful "
      "of requests a minute — plenty for a chart somebody presses refresh on.",
  choiceLabel: "Coin",
  choices: _geckoCoins,
  address: (coin) => "https://api.coingecko.com/api/v3/coins/$coin"
      "/market_chart?vs_currency=usd&days=365&interval=daily",
  rowsPath: "prices",
  tables: false,
  charts: true,
  chartCategory: 0,
  chartValues: const [1],
  chartPoints: 120,
  fields: const ["0", "1"],
  columns: const [
    SourceColumn(header: "Date", path: "0", date: "MMM yy"),
    SourceColumn(header: "Price (USD)", path: "1"),
  ],
);

/// coinGeckoMarkets is several coins side by side, as they stand now.
///
/// A list of records, so it maps the ordinary way, and the one preset here
/// that suits a table as readily as a chart: eight rows of name, price and
/// market cap is a table somebody would keep.
final DataPreset coinGeckoMarkets = DataPreset(
  id: "coingecko.markets",
  label: "Coin comparison (CoinGecko)",
  shortLabel: "CoinGecko",
  note: "No key needed. One row per coin, as they stand at the moment it is "
      "refreshed.",
  choiceLabel: "Coins",
  choices: const [
    ("decred,bitcoin,ethereum,monero,litecoin,zcash,dash", "A spread"),
    ("bitcoin,ethereum,solana,cardano,polkadot,chainlink", "The large ones"),
    ("decred,monero,zcash,dash,litecoin", "Privacy and proof of work"),
  ],
  address: (ids) => "https://api.coingecko.com/api/v3/coins/markets"
      "?vs_currency=usd&ids=$ids&order=market_cap_desc",
  rowsPath: "",
  tables: true,
  charts: true,
  matchColumn: 0,
  chartCategory: 0,
  chartValues: const [1],
  fields: const [
    "id",
    "symbol",
    "name",
    "image",
    "current_price",
    "market_cap",
    "market_cap_rank",
    "total_volume",
    "high_24h",
    "low_24h",
    "price_change_percentage_24h",
    "circulating_supply",
    "total_supply",
    "ath",
  ],
  columns: const [
    SourceColumn(header: "Coin", path: "name"),
    SourceColumn(header: "Price (USD)", path: "current_price"),
    SourceColumn(header: "Market cap (\$m)", path: "market_cap", divide: 1e6),
    SourceColumn(header: "Volume (\$m)", path: "total_volume", divide: 1e6),
    SourceColumn(header: "24h %", path: "price_change_percentage_24h"),
  ],
);

/// coinGeckoCandles is a coin's open, high, low and close.
///
/// The rows are arrays -- [when, open, high, low, close] -- so the paths are
/// indices, the same way the price history's are. Thirty days at four-hourly
/// candles is about a hundred and eighty, which is more than a canvas can
/// draw legibly, so it is thinned like everything else.
final DataPreset coinGeckoCandles = DataPreset(
  id: "coingecko.ohlc",
  label: "Candlesticks (CoinGecko)",
  shortLabel: "CoinGecko",
  note: "No key needed. CoinGecko decides the candle width from the range "
      "asked for: a month comes back in four-hour candles.",
  choiceLabel: "Coin",
  choices: _geckoCoins,
  address: (coin) =>
      "https://api.coingecko.com/api/v3/coins/$coin/ohlc?vs_currency=usd&days=30",
  rowsPath: "",
  tables: false,
  charts: true,
  chartCategory: 0,
  chartValues: const [1, 2, 3, 4],
  chartType: ChartType.candlestick,
  chartPoints: 60,
  fields: const ["0", "1", "2", "3", "4"],
  columns: const [
    SourceColumn(header: "Date", path: "0", date: "d MMM"),
    SourceColumn(header: "Open", path: "1"),
    SourceColumn(header: "High", path: "2"),
    SourceColumn(header: "Low", path: "3"),
    SourceColumn(header: "Close", path: "4"),
  ],
);

/// dcrdexCandles is Decred's own market, through dcrdata.
///
/// A list of records rather than arrays this time, with the period's start as
/// an ISO date. The prices are in BTC, which is what the market trades in --
/// so this is the chart of the DCR/BTC pair and not of a dollar price.
final DataPreset dcrdexCandles = DataPreset(
  id: "dcrdata.candlestick",
  label: "Decred market candlesticks (dcrdex)",
  shortLabel: "dcrdex",
  note: "No key needed. Prices are in BTC, which is the pair the market "
      "trades — for a dollar price use the CoinGecko candlesticks instead.",
  choiceLabel: "Candle",
  choices: const [
    ("1d", "One day"),
    ("1h", "One hour"),
  ],
  address: (bin) =>
      "https://dcrdata.decred.org/api/chart/market/dcrdex/candlestick/$bin",
  rowsPath: "sticks",
  tables: false,
  charts: true,
  chartCategory: 0,
  chartValues: const [1, 2, 3, 4],
  chartType: ChartType.candlestick,
  chartPoints: 60,
  fields: const ["start", "open", "high", "low", "close", "volume"],
  columns: const [
    SourceColumn(header: "Date", path: "start", date: "d MMM"),
    SourceColumn(header: "Open", path: "open"),
    SourceColumn(header: "High", path: "high"),
    SourceColumn(header: "Low", path: "low"),
    SourceColumn(header: "Close", path: "close"),
  ],
);

/// dataPresets is every recipe there is.
final List<DataPreset> dataPresets = [
  footballData,
  dcrdataChart,
  coinGeckoPrice,
  coinGeckoCandles,
  dcrdexCandles,
  coinGeckoMarkets,
];

/// presetsFor is the recipes offered to one kind of element.
List<DataPreset> presetsFor({required bool chart}) => [
      for (var p in dataPresets)
        if (chart ? p.charts : p.tables) p
    ];

DataPreset? presetById(String id) {
  for (var preset in dataPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}
