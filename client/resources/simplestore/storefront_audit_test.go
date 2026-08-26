package simplestore

import (
	"strings"
	"testing"

	"github.com/decred/slog"
)

// storefront_audit_test.go walks every setting on the shop front and asks the
// same question of each: does turning it on change what a card is written as?
//
// One test per setting was how this started, and settings kept arriving that
// nobody wrote one for -- so three of them reached a shop where they saved,
// showed the answer they had saved, and changed nothing on the page. A shape
// that has to be filled in for each new setting is a great deal harder to
// forget than a habit of writing another test.
//
// What it cannot check is what the drawing looks like: that a plate said to
// run the full width is drawn that wide is the renderer's business, and the
// Flutter side covers it. This covers the half in between -- that the setting
// reaches the markup at all, which is where every one of those three failed.
func TestEverySettingReachesTheCard(t *testing.T) {
	product := &Product{
		Title:       "A guitar",
		SKU:         "gtr",
		Image:       "guitar.jpg",
		Price:       20,
		Description: "A lovely guitar with a spruce top.",
	}

	cases := []struct {
		name string

		// set turns the setting on, from the defaults.
		set func(*IndexLayout)

		// wants is what the card must then say, and notWants what it must
		// not -- for a setting whose whole job is to take something away.
		wants    []string
		notWants []string
	}{{
		name:  "one shape for every picture",
		set:   func(l *IndexLayout) { l.FixedImage = true },
		wants: []string{"ratio=400x400", "crop=center"},
	}, {
		name: "the shape it is drawn at",
		set: func(l *IndexLayout) {
			l.FixedImage = true
			l.ImageWidth, l.ImageHeight = 600, 400
		},
		wants: []string{"ratio=600x400"},
	}, {
		name: "which part of a picture is kept",
		set: func(l *IndexLayout) {
			l.FixedImage = true
			l.Crop = CropTopLeft
		},
		wants: []string{"crop=topleft"},
	}, {
		name:  "the picture under the writing",
		set:   func(l *IndexLayout) { l.ImagePosition = ImageBottom },
		wants: []string{"image=shopassets/guitar.jpg"},
	}, {
		name:  "the picture behind the whole card",
		set:   func(l *IndexLayout) { l.ImagePosition = ImageFull },
		wants: []string{"align=bottom", "justify=stretch"},
	}, {
		name: "where the writing sits on a picture that fills the card",
		set: func(l *IndexLayout) {
			l.ImagePosition = ImageFull
			l.TextPosition = TextTop
		},
		wants: []string{"align=top"},
	}, {
		name:  "the picture's corners",
		set:   func(l *IndexLayout) { l.ImageCornerTopLeft = 12 },
		wants: []string{"radius=12 0 0 0"},
	}, {
		name: "the picture's corners, one by one",
		set: func(l *IndexLayout) {
			l.ImageCornerTopLeft, l.ImageCornerTopRight = 12, 8
			l.ImageCornerBottomRight, l.ImageCornerBottomLeft = 4, 2
		},
		wants: []string{"radius=12 8 4 2"},
	}, {
		name:  "a plate behind the writing",
		set:   func(l *IndexLayout) { l.TextBackground = true },
		wants: []string{"fill=raised", "padding=10", "radius=8"},
	}, {
		name: "the plate's colour",
		set: func(l *IndexLayout) {
			l.TextBackground = true
			l.TextColor = "#334455"
		},
		wants: []string{"fill=#334455"},
	}, {
		name: "the room inside and around the plate",
		set: func(l *IndexLayout) {
			l.TextBackground = true
			l.TextPadding, l.TextMargin, l.TextRadius = 12, 6, 16
		},
		wants: []string{"padding=12", "margin=6", "radius=16"},
	}, {
		name: "a plate that is not the full width",
		set: func(l *IndexLayout) {
			l.TextBackground = true
			l.TextFullWidth = false
			l.TextAlign = TextRight
		},
		wants: []string{"justify=right"},
	}, {
		name: "a plate flush with the picture's edge",
		set: func(l *IndexLayout) {
			l.ImagePosition = ImageFull
			l.TextBackground = true
			l.TextFlush = true
			l.TextMargin = 10
		},
		wants:    []string{"padding=0"},
		notWants: []string{"padding=10 0"},
	}, {
		// The two settings read each other: a plate that runs the full
		// width and stands off the picture's edge stands off it at the top
		// and the bottom, because standing off at the sides is not being
		// the full width.
		name: "a full-width plate standing off the picture's edge",
		set: func(l *IndexLayout) {
			l.ImagePosition = ImageFull
			l.TextBackground = true
			l.TextFlush = false
			l.TextMargin = 10
		},
		wants: []string{"padding=10 0"},
	}, {
		name: "a plate that is neither full width nor flush",
		set: func(l *IndexLayout) {
			l.ImagePosition = ImageFull
			l.TextBackground = true
			l.TextFullWidth = false
			l.TextFlush = false
			l.TextMargin = 10
		},
		wants: []string{"padding=10,"},
	}, {
		name:  "which side the writing sits on, with no plate",
		set:   func(l *IndexLayout) { l.TextAlign = TextCenter },
		wants: []string{"text=center"},
	}, {
		name: "which side the writing sits on, with a plate",
		set: func(l *IndexLayout) {
			l.TextBackground = true
			l.TextAlign = TextRight
		},
		wants: []string{"text=right"},
	}, {
		name:     "the three rows",
		set:      func(l *IndexLayout) { l.TextLayout = TextRows },
		wants:    []string{"--listing--", "summary: A lovely guitar", "button: Buy Now"},
		notWants: []string{"--columns["},
	}, {
		name: "what the button says",
		set: func(l *IndexLayout) {
			l.TextLayout = TextRows
			l.ButtonLabel = "Add to cart"
		},
		wants: []string{"button: Add to cart"},
	}, {
		name:  "a border round the card",
		set:   func(l *IndexLayout) { l.CardBorder = true },
		wants: []string{"border=1", "color=outline"},
	}, {
		name: "what the border looks like",
		set: func(l *IndexLayout) {
			l.CardBorder = true
			l.CardBorderWidth, l.CardBorderRadius = 3, 20
			l.CardBorderColor = "#334455"
			l.CardPadding, l.CardMargin = 14, 6
		},
		wants: []string{"border=3", "color=#334455", "radius=20",
			"padding=14", "margin=6"},
	}, {
		name: "the room between one row and the next",
		set: func(l *IndexLayout) {
			l.TextLayout = TextRows
			l.RowGap = 14
		},
		wants: []string{"gap: 14"},
	}, {
		name: "the button's own colour, corners and padding",
		set: func(l *IndexLayout) {
			l.TextLayout = TextRows
			l.ButtonColor = "#334455"
			l.ButtonRadius, l.ButtonPadding = 20, 4
		},
		wants: []string{"color: #334455", "radius: 20", "padding: 4"},
	}, {
		name: "a button left as the app's own",
		set: func(l *IndexLayout) {
			l.TextLayout = TextRows
			l.ButtonColor = ""
		},
		wants:    []string{"style: primary"},
		notWants: []string{"color:"},
	}, {
		name: "which side the three rows sit on",
		set: func(l *IndexLayout) {
			l.TextLayout = TextRows
			l.TextAlign = TextCenter
		},
		wants: []string{"align: center"},
	}, {
		// Flush is about touching the picture, and a plate under a picture
		// touches its bottom edge as much as one on a full-bleed card
		// touches whichever edge it sits against. It used to be written
		// only for the full-bleed card, so the setting saved and did
		// nothing for the other two.
		name: "a plate flush with a picture above it",
		set: func(l *IndexLayout) {
			l.ImagePosition = ImageTop
			l.TextBackground = true
			l.TextFlush = true
			l.TextMargin = 8
		},
		wants: []string{"margin=0 8 8 8"},
	}, {
		name: "a plate flush with a picture below it",
		set: func(l *IndexLayout) {
			l.ImagePosition = ImageBottom
			l.TextBackground = true
			l.TextFlush = true
			l.TextMargin = 8
		},
		wants: []string{"margin=8 8 0 8"},
	}, {
		name: "a plate standing off a picture above it",
		set: func(l *IndexLayout) {
			l.ImagePosition = ImageTop
			l.TextBackground = true
			l.TextFlush = false
			l.TextMargin = 8
		},
		wants: []string{"margin=8,"},
	}, {
		name:     "the DCR figure left off",
		set:      func(l *IndexLayout) { l.ShowDCR = false },
		notWants: []string{"DCR"},
	}}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			layout := DefaultIndexLayout()
			c.set(&layout)

			s := &Store{indexPath: "/", log: slog.Disabled, layout: layout}
			// A rate, so the DCR figure is there to be left off.
			s.cfg.ExchangeRateProvider = func() float64 { return 25 }
			got := s.productCard(product)

			for _, want := range c.wants {
				if !strings.Contains(got, want) {
					t.Errorf("%q missing from:\n%s", want, got)
				}
			}
			for _, never := range c.notWants {
				if strings.Contains(got, never) {
					t.Errorf("%q is still in:\n%s", never, got)
				}
			}
		})
	}
}

// TestTheDefaultsWriteNothingExtra is the other half of the audit: a shop
// that has changed nothing renders the markup it rendered before any of these
// settings existed.
func TestTheDefaultsWriteNothingExtra(t *testing.T) {
	s := &Store{indexPath: "/", log: slog.Disabled, layout: DefaultIndexLayout()}
	got := s.productCard(&Product{Title: "A guitar", SKU: "gtr", Price: 20})

	for _, never := range []string{
		"border=", "fill=", "ratio=", "crop=", "radius=", "justify=",
		"text=", "--listing--", "align=",
	} {
		if strings.Contains(got, never) {
			t.Errorf("a shop that asked for nothing got %q:\n%s", never, got)
		}
	}
}
