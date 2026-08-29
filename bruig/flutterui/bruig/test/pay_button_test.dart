import 'package:bruig/util.dart';
import 'package:flutter_test/flutter_test.dart';

// pay_button_test.dart covers how an amount is written on the one press that
// spends money.
//
// formatDCR gives all eight places, which is what an atom is worth and what a
// wallet's ledger should show. On a button it is noise: "Pay 0.31000000 DCR"
// is the same number as "Pay 0.31 DCR" with six characters nobody reads.

void main() {
  group("an amount on a button", () {
    test("drops the zeros nobody reads", () {
      expect(dcrLabel(0.31), "0.31 DCR");
      expect(dcrLabel(1), "1.00 DCR");
      expect(dcrLabel(0.5), "0.50 DCR");
    });

    // Nothing is rounded away: an amount is what will actually be sent.
    test("keeps every place that carries a figure", () {
      expect(dcrLabel(0.06479793), "0.06479793 DCR");
      expect(dcrLabel(0.000001), "0.000001 DCR");
      expect(dcrLabel(12.3456789), "12.3456789 DCR");
    });

    // Two places at least: "0.5 DCR" reads as a price and "0.50 DCR" reads as
    // an amount of money.
    test("never goes below two places", () {
      expect(dcrLabel(0), "0.00 DCR");
      expect(dcrLabel(2), "2.00 DCR");
    });
  });
}
