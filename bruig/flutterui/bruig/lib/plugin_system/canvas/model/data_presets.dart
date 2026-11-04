import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:flutter/foundation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_data.dart';
import 'package:bruig/plugin_system/canvas/model/football_form.dart';

// data_presets.dart is the recipes that fill a DataSource in: the mapping
// already written for a source somebody is likely to want. The paths stay
// editable afterwards.

/// DataPreset is one named recipe.
class DataPreset {
  final String id;
  final String label;

  /// shortLabel is what a closed section's heading says, where the full label
  /// does not fit beside a title and a button.
  final String shortLabel;

  /// note says what the reader has to do for themselves, such as get a key.
  final String note;

  /// rowNames are the things this source has (the coins, say), offered while
  /// somebody types a row. Names rather than identifiers, because the name is
  /// what goes in the cell and what a refresh is matched on; see asRowKey. A
  /// short list of likely ones: anything else can still be typed.
  final List<String> rowNames;

  /// namesAddress is where the source's own list of rows can be fetched,
  /// with the identifier it files each under, since hand-written [rowIds]
  /// go stale. Empty for a preset that has no such list. Fetched only on a
  /// button press, never unasked; see CanvasRowNames.
  final String namesAddress;

  /// namesId and namesName are where the identifier and the name sit in each
  /// record of that list.
  final String namesId;
  final String namesName;

  /// rowIds is what to ask for when a row says one of those names, for the
  /// ones where the identifier differs from the name (XRP is ripple). Keyed
  /// by asRowKey of the name.
  final Map<String, String> rowIds;

  /// choiceFromRows is whether the choice is a list of things that each
  /// become a row, so the element's own rows can say what to ask for. See
  /// DataSource.fromRows.
  final bool choiceFromRows;

  /// choices are the interchangeable part of the address -- which competition,
  /// which season -- as a code and a name.
  final List<(String, String)> choices;
  final String choiceLabel;

  final String Function(String choice) address;
  final String rowsPath;

  /// matchColumn identifies a row across a refresh. See DataSource.
  final int matchColumn;

  /// hiddenHeaders are the columns whose names are kept for the mapping but
  /// not drawn, such as a league table's position and badge.
  final List<int> hiddenHeaders;

  final List<SourceColumn> columns;

  /// shape is how the response is laid out. See [DataShape].
  final DataShape shape;

  /// columnsFor is the mapping when it depends on which choice was made, as
  /// for a chain series whose value array is named and scaled per series.
  final List<SourceColumn> Function(String choice)? columnsFor;

  /// tables and charts are which elements this recipe is offered to. A chart
  /// of a table's figures links to the table instead; see [TableLink].
  final bool tables;
  final bool charts;

  /// chartCategory and chartValues are which of the columns a chart uses for
  /// its axis and its series, so choosing a preset leaves a chart drawn
  /// rather than mapped and empty.
  final int chartCategory;
  final List<int> chartValues;

  /// chartType is the drawing this recipe wants (candlesticks for OHLC), or
  /// null to leave the chart's type alone.
  final ChartType? chartType;

  /// chartPoints is how many points to keep, so years of daily figures are
  /// thinned to something legible. Zero keeps them all.
  final int chartPoints;

  /// fields is what a record is known to carry, so the mapping can offer a
  /// list before anything has been fetched.
  final List<String> fields;

  /// derived are the paths this preset fills in itself, whatever the response
  /// said, so a column mapped to one is listed as a custom field even with no
  /// template or spread.
  final List<String> derived;

  /// derive fills in what one request cannot answer: given the rows as
  /// mapped and a way to fetch more JSON, it returns the rows again. See
  /// footballFormFromResults. Null for most sources.
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
    this.choiceFromRows = false,
    this.rowNames = const [],
    this.rowIds = const {},
    this.namesAddress = "",
    this.namesId = "id",
    this.namesName = "name",
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

  /// idFor is what to ask the source for when a row says [cell]: the
  /// identifier where the name differs from it, and the name's own key
  /// otherwise. See [rowIds].
  String idFor(String cell) {
    var key = asRowKey(cell);
    return rowIds[key] ?? key;
  }

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

/// footballDataColumns is the league table in the usual published order.
/// Position comes first, so a refreshed table reads 1, 2, 3 unsorted.
const List<SourceColumn> footballDataColumns = [
  SourceColumn(header: "Pos", path: "position"),
  // Named for the mapping but hidden on the canvas (hiddenHeaders), and kept
  // so badges chosen by hand survive a refresh.
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
  // The form guide. "form" is null on the free plan, so it is worked out from
  // the results instead (football_form.dart), which allows six games rather
  // than the paid field's five.
  SourceColumn(header: "Custom form", path: "form", spread: 6, divider: "|"),
];

/// footballDataFields is every field a standings record carries, taken from
/// the published response, for the Field dropdown before a refresh has
/// shown what actually arrives.
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

/// footballData is football-data.org's standings. Its response is already a
/// league table, so a refresh is one request. The free tier rate-limits at
/// ten requests a minute.
final DataPreset footballData = DataPreset(
  id: "football-data.org",
  label: "Football league table (football-data.org)",
  shortLabel: "Football",
  note: "Needs a free key from football-data.org, which arrives by email. "
      "The key is kept on this machine and never saved into the canvas, so a "
      "canvas you send carries the table and not your key.",
  choiceLabel: "Competition",
  // The free tier's competitions, by code.
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
  // The first standing is the whole table; some competitions add home and
  // away after it.
  rowsPath: "standings.0.table",
  // The team's name.
  matchColumn: 2,
  hiddenHeaders: const [0, 1],
  fields: footballDataFields,
  derived: const ["form"],
  derive: footballFormFromResults,
  columns: footballDataColumns,
);

// ---------------------------------------------------------------------------
// The chain and market series. Their shapes were checked against the live
// APIs.

/// _DcrChart is one of dcrdata's series: the name in the address, what the
/// array of values is called, and how to make it readable.
class _DcrChart {
  final String name;
  final String label;

  /// field is the array the values are in, beside the "t" array of
  /// timestamps.
  final String field;

  /// divide brings atoms into DCR.
  final double divide;

  /// query is what the endpoint needs to answer at all: a few return nothing
  /// for bin=day and are left to the server's default.
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

/// dcrdataChart is Decred's own chain history, needing no key. The response
/// is parallel arrays; see [DataShape.columns].
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
  // Daily since 2016 is four thousand points.
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

/// _geckoCoins is the CoinGecko coins offered by id and name, Decred first:
/// a short list of likely ones out of thousands.
const List<(String, String)> _geckoCoins = [
  ("decred", "Decred"),
  ("bitcoin", "Bitcoin"),
  ("ethereum", "Ethereum"),
  ("monero", "Monero"),
  ("litecoin", "Litecoin"),
  ("zcash", "Zcash"),
  ("dash", "Dash"),
  ("solana", "Solana"),
  ("cardano", "Cardano"),
  ("polkadot", "Polkadot"),
  ("chainlink", "Chainlink"),
  ("avalanche-2", "Avalanche"),
  ("cosmos", "Cosmos Hub"),
  ("algorand", "Algorand"),
  ("tezos", "Tezos"),
  ("filecoin", "Filecoin"),
  ("stellar", "Stellar"),
  ("bitcoin-cash", "Bitcoin Cash"),
  ("ethereum-classic", "Ethereum Classic"),
  ("dogecoin", "Dogecoin"),
  ("ripple", "XRP"),
  ("binancecoin", "BNB"),
  ("tron", "TRON"),
  ("near", "NEAR Protocol"),
  ("aptos", "Aptos"),
  ("arbitrum", "Arbitrum"),
  ("optimism", "Optimism"),
  ("uniswap", "Uniswap"),
  ("aave", "Aave"),
  ("maker", "Maker"),
  ("the-graph", "The Graph"),
  ("tether", "Tether"),
  ("usd-coin", "USDC"),
  ("digibyte", "DigiByte"),
  ("ravencoin", "Ravencoin"),
  ("siacoin", "Siacoin"),
  // Filed under their old names, ZenCash and Zcoin.
  ("zencash", "Horizen"),
  ("zcoin", "Firo"),
  ("beam", "Beam"),
  ("grin", "Grin"),
  ("nervos-network", "Nervos Network"),
  ("kadena", "Kadena"),
  ("handshake", "Handshake"),
  ("vertcoin", "Vertcoin"),
  ("groestlcoin", "Groestlcoin"),
  ("nano", "Nano"),
  ("iota", "IOTA"),
  ("vechain", "VeChain"),
  ("theta-token", "Theta Network"),
  ("elrond-erd-2", "MultiversX"),
  ("hedera-hashgraph", "Hedera"),
  ("eos", "EOS"),
  ("neo", "NEO"),
  ("waves", "Waves"),
  ("qtum", "Qtum"),
  ("icon", "ICON"),
  ("zilliqa", "Zilliqa"),
  ("ontology", "Ontology"),
  ("kusama", "Kusama"),
  ("internet-computer", "Internet Computer"),
  ("flow", "Flow"),
  ("chiliz", "Chiliz"),
  ("enjincoin", "Enjin Coin"),
  ("decentraland", "Decentraland"),
  ("the-sandbox", "The Sandbox"),
  ("axie-infinity", "Axie Infinity"),
  ("gala", "GALA"),
  ("immutable-x", "Immutable"),
  ("injective-protocol", "Injective"),
  ("sei-network", "Sei"),
  ("sui", "Sui"),
  ("celestia", "Celestia"),
  ("render-token", "Render"),
  ("thorchain", "THORChain"),
  ("fantom", "Fantom"),
  ("polygon-ecosystem-token", "POL"),
  ("matic-network", "Polygon"),
  ("shiba-inu", "Shiba Inu"),
  ("pepe", "Pepe"),
  ("bonk", "Bonk"),
  ("dogwifcoin", "dogwifhat"),
  ("floki", "FLOKI"),
  ("curve-dao-token", "Curve DAO"),
  ("lido-dao", "Lido DAO"),
  ("compound-governance-token", "Compound"),
  ("synthetix-network-token", "Synthetix"),
  ("1inch", "1inch"),
  ("sushi", "Sushi"),
  ("pancakeswap-token", "PancakeSwap"),
  ("havven", "Synthetix Network"),
  ("basic-attention-token", "Basic Attention"),
  ("0x", "0x Protocol"),
  ("loopring", "Loopring"),
  ("stacks", "Stacks"),
  ("mina-protocol", "Mina Protocol"),
  ("helium", "Helium"),
  ("arweave", "Arweave"),
  ("oasis-network", "Oasis"),
  ("astar", "Astar"),
  ("moonbeam", "Moonbeam"),
  ("kava", "Kava"),
  ("osmosis", "Osmosis"),
  ("akash-network", "Akash Network"),
  ("secret", "Secret"),
  ("terra-luna-2", "Terra"),
  ("blockstack", "Stacks Token"),
  ("wrapped-bitcoin", "Wrapped Bitcoin"),
  ("staked-ether", "Lido Staked Ether"),
  ("dai", "Dai"),
  ("first-digital-usd", "First Digital USD"),
  ("blur", "Blur"),
  ("worldcoin-wld", "Worldcoin"),
  ("jupiter-exchange-solana", "Jupiter"),
  ("ethena", "Ethena"),
  ("ondo-finance", "Ondo"),
  ("bittensor", "Bittensor"),
  ("toncoin", "Toncoin"),
  ("leo-token", "LEO Token"),
  ("okb", "OKB"),
  ("cronos", "Cronos"),
  ("bitcoin-cash-sv", "Bitcoin SV"),
  ("bitcoin-gold", "Bitcoin Gold"),
];

/// geckoCoinsForTest is the list itself, so a test can check that every name
/// offered maps to an identifier the list actually has.
@visibleForTesting
List<(String, String)> get geckoCoinsForTest => _geckoCoins;

/// geckoCoinNames is the same list as the names alone, for the cell that
/// names a row. See DataPreset.rowNames.
final List<String> geckoCoinNames = [for (var (_, name) in _geckoCoins) name];

/// geckoCoinIds is what each of those names is filed under, keyed by
/// asRowKey of the name, for the handful whose id is not that key (XRP is
/// ripple). Built from the one list so the two cannot drift apart.
final Map<String, String> geckoCoinIds = {
  for (var (id, name) in _geckoCoins) asRowKey(name): id,
};

/// coinGeckoPrice is a coin's price history. (CoinMarketCap's free tier gives
/// only the latest price.) Each record is a `[when, price]` pair, so the
/// paths are the list indices "0" and "1".
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

/// coinGeckoMarkets is several coins side by side, as they stand now: a list
/// of records, offered to tables and charts alike.
final DataPreset coinGeckoMarkets = DataPreset(
  id: "coingecko.markets",
  label: "Coin comparison (CoinGecko)",
  choiceFromRows: true,
  rowNames: geckoCoinNames,
  rowIds: geckoCoinIds,
  // Every coin CoinGecko knows, with its id. No key needed.
  namesAddress: "https://api.coingecko.com/api/v3/coins/list",
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
  // Everything a markets record carries, so the series picker can offer any
  // of it before a refresh. Five are mapped as columns.
  fields: const [
    "id",
    "symbol",
    "name",
    "image",
    "current_price",
    "market_cap",
    "market_cap_rank",
    "fully_diluted_valuation",
    "total_volume",
    "high_24h",
    "low_24h",
    "price_change_24h",
    "price_change_percentage_24h",
    "market_cap_change_24h",
    "market_cap_change_percentage_24h",
    "circulating_supply",
    "total_supply",
    "max_supply",
    "ath",
    "ath_change_percentage",
    "ath_date",
    "atl",
    "atl_change_percentage",
    "atl_date",
    "last_updated",
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
/// The rows are `[when, open, high, low, close]` arrays, so the paths are
/// indices. Thirty days of four-hour candles (about 180) is thinned to 60.
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
/// A list of records, with the period's start as an ISO date. Prices are in
/// BTC: this is the DCR/BTC pair, not a dollar price.
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

/// dataPresets is every recipe.
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
