import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:golib_plugin/golib_plugin.dart';

// ExchangeRateModel surfaces the USD prices the client already tracks (see
// rates.Rates on the Go side) to the UI, and remembers the previous value of
// each so a direction -- up, down, or not yet known -- can be shown beside
// it.
//
// The direction has to be derived here because nothing else keeps it: the
// client's rate tracker holds only the latest pair, so without a previous
// value to compare against there's nothing to point an arrow at.
//
// Polling, not pushing: the Go side has no rate notification, and its
// tracker refreshes on its own schedule regardless of who's asking, so a
// read here is a cheap cached lookup rather than a network request.
class ExchangeRateModel extends ChangeNotifier {
  static const _pollInterval = Duration(minutes: 1);

  double _dcrPrice = 0;
  double _btcPrice = 0;
  int _dcrDirection = 0;
  int _btcDirection = 0;
  Timer? _timer;
  bool _loggedError = false;

  double get dcrPrice => _dcrPrice;
  double get btcPrice => _btcPrice;

  // 1 up, -1 down, 0 unchanged or not yet known.
  int get dcrDirection => _dcrDirection;
  int get btcDirection => _btcDirection;

  bool get hasRates => _dcrPrice > 0 || _btcPrice > 0;

  ExchangeRateModel() {
    _refresh();
    _timer = Timer.periodic(_pollInterval, (_) => _refresh());
  }

  Future<void> _refresh() async {
    try {
      var rate = await Golib.getExchangeRate();
      // A zero means the tracker hasn't fetched yet; keep the last real
      // price rather than flashing "$0.00" and inventing a crash downward.
      if (rate.dcrPrice <= 0 && rate.btcPrice <= 0) return;

      var dcrDir = _directionOf(_dcrPrice, rate.dcrPrice);
      var btcDir = _directionOf(_btcPrice, rate.btcPrice);
      if (rate.dcrPrice == _dcrPrice &&
          rate.btcPrice == _btcPrice &&
          dcrDir == _dcrDirection &&
          btcDir == _btcDirection) {
        return;
      }

      _dcrPrice = rate.dcrPrice;
      _btcPrice = rate.btcPrice;
      _dcrDirection = dcrDir;
      _btcDirection = btcDir;
      notifyListeners();
    } catch (exception) {
      // A failed read leaves the last known prices in place: the nav bar
      // showing a slightly stale price beats it blanking out. Logged once
      // rather than every minute -- a persistent failure (an out-of-date
      // golib build, say) shows up as no price rows at all, which is
      // otherwise indistinguishable from the setting being switched off.
      if (!_loggedError) {
        _loggedError = true;
        debugPrint("Unable to read exchange rate: $exception");
      }
    }
  }

  // The first reading has nothing to compare against, so it has no
  // direction -- 0 rather than a guess.
  int _directionOf(double previous, double next) {
    if (previous <= 0 || next == previous) return 0;
    return next > previous ? 1 : -1;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
