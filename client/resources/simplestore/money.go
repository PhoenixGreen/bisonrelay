package simplestore

import "fmt"

// money.go is how a price is written down.
//
// A shop quotes in USD and is paid in DCR. Those are the only two figures
// this app can stand behind: rates.Get returns USD/DCR and USD/BTC and
// nothing else, so a price shown in a buyer's own currency would have to be
// invented -- and the DCR amount they commit to at checkout is worked out
// from the USD price whatever the label said. A friendly wrong number
// misprices the goods; two true ones do not.

// Money writes an amount the way a price is written: two places, always,
// because 12.5 is a number and $12.50 is a price.
func Money(amount float64) string {
	return fmt.Sprintf("$%.2f", amount)
}

// approxDCR is what a USD amount is worth in DCR at the rate held now, or
// empty when no rate is known.
//
// Marked approximate wherever it is shown before checkout, because it is:
// the rate moves, and the binding figure is the one struck when the order is
// placed. Saying so is the difference between a helpful second number and a
// quoted price that quietly disagrees with the invoice.
//
// Empty rather than nought when there is no rate. A shop that says a thing
// costs 0 DCR is worse than one that does not mention DCR at all.
func (s *Store) approxDCR(amount float64) string {
	if s.cfg.ExchangeRateProvider == nil {
		return ""
	}
	rate := s.cfg.ExchangeRateProvider()
	if rate <= 0 {
		return ""
	}
	return fmt.Sprintf("%.4f DCR", amount/rate)
}

// approxDCRAmount is the same figure as a bare number, or empty when no rate
// is known.
//
// For the one reader that is not a person: --wallet[need=...]-- compares this
// against the wallet of whoever is looking at the page, and "0.3100 DCR" is
// not a number. Four places is what approxDCR shows and eight is what a
// wallet holds, so this writes eight -- a comparison rounded to what the
// page happened to display is one that can say a balance covers an order it
// does not.
func (s *Store) approxDCRAmount(amount float64) string {
	if s.cfg.ExchangeRateProvider == nil {
		return ""
	}
	rate := s.cfg.ExchangeRateProvider()
	if rate <= 0 {
		return ""
	}
	return fmt.Sprintf("%.8f", amount/rate)
}
