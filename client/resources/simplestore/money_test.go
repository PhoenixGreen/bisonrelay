package simplestore

import "testing"

// money_test.go covers how a price is written.
//
// A shop quotes in USD and is paid in DCR, and those are the only two
// figures this app can stand behind: rates.Get returns USD/DCR and USD/BTC
// and nothing else. A price shown in a buyer's own currency would have to be
// invented, and the DCR amount they commit to at checkout is worked out from
// the USD price whatever the label said -- so a friendlier wrong number
// misprices the goods.

func TestAPriceIsWrittenAsAPrice(t *testing.T) {
	for amount, want := range map[float64]string{
		12:     "$12.00",
		12.5:   "$12.50",
		0:      "$0.00",
		1234.5: "$1234.50",
		0.129:  "$0.13",
	} {
		if got := Money(amount); got != want {
			t.Errorf("%v came out %q, want %q", amount, got, want)
		}
	}
}

func TestTheDCRFigureNeedsARate(t *testing.T) {
	// Empty rather than nought. A shop saying a thing costs 0 DCR is worse
	// than one not mentioning DCR at all -- the first is a price, and it is
	// wrong.
	s := &Store{}
	if got := s.approxDCR(10); got != "" {
		t.Errorf("with no rate at all, got %q", got)
	}

	s.cfg.ExchangeRateProvider = func() float64 { return 0 }
	if got := s.approxDCR(10); got != "" {
		t.Errorf("with a rate of nought, got %q", got)
	}
}

func TestTheDCRFigureIsTheUSDOneAtTheRate(t *testing.T) {
	s := &Store{}
	s.cfg.ExchangeRateProvider = func() float64 { return 25 }
	if got := s.approxDCR(50); got != "2.0000 DCR" {
		t.Errorf("got %q, want 2.0000 DCR", got)
	}
}

func TestALineOfACartComesToPriceTimesHowMany(t *testing.T) {
	// A cart showing a unit price and a quantity but no line total leaves
	// the buyer doing the sum.
	item := &CartItem{Product: &Product{Price: 12.5}, Quantity: 3}
	if got := item.Total(); got != 37.5 {
		t.Errorf("got %v, want 37.5", got)
	}
	if got := Money(item.Total()); got != "$37.50" {
		t.Errorf("got %q", got)
	}
}
