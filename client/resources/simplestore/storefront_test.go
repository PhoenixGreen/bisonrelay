package simplestore

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/decred/slog"
)

// storefront_test.go covers the settings that decide what one card on the
// shop front looks like.
//
// The settings are read at start-up and written by the seller's own UI, so
// what matters here is that a shop with no settings renders as it always did,
// that each setting reaches the card, and that a setting that cannot mean
// anything is corrected rather than taken.

func cardFor(t *testing.T, layout IndexLayout, p *Product) string {
	t.Helper()
	s := &Store{indexPath: "/", log: slog.Disabled, layout: layout}
	return s.productCard(p)
}

func TestAShopWithNoSettingsRendersAsItAlwaysDid(t *testing.T) {
	got := cardFor(t, IndexLayout{}, &Product{Title: "A guitar", SKU: "gtr",
		Image: "guitar.jpg", Price: 20})

	// The picture first, then the link, then the price.
	image := strings.Index(got, "image=shopassets/guitar.jpg")
	link := strings.Index(got, "**[A guitar](product/gtr)**")
	price := strings.Index(got, "$20.00")
	if image == -1 || link == -1 || price == -1 {
		t.Fatalf("a card is missing a part of itself:\n%s", got)
	}
	if !(image < link && link < price) {
		t.Errorf("a default card is not picture, link, price:\n%s", got)
	}
	if strings.Contains(got, "ratio=") {
		t.Errorf("a shop nobody has set a picture size for got one:\n%s", got)
	}
	if strings.Contains(got, "fill=") {
		t.Errorf("a shop nobody asked for a text plate got one:\n%s", got)
	}
}

func TestAFixedPictureSizeReachesTheCard(t *testing.T) {
	layout := DefaultIndexLayout()
	layout.FixedImage = true
	layout.ImageWidth, layout.ImageHeight = 600, 400
	layout.Crop = CropTopLeft

	got := cardFor(t, layout, &Product{Title: "A guitar", SKU: "gtr"})
	for _, want := range []string{"ratio=600x400", "crop=topleft"} {
		if !strings.Contains(got, want) {
			t.Errorf("%q missing from:\n%s", want, got)
		}
	}
}

func TestThePictureGoesWhereItIsAsked(t *testing.T) {
	product := &Product{Title: "A guitar", SKU: "gtr", Image: "guitar.jpg"}

	layout := DefaultIndexLayout()
	layout.ImagePosition = ImageBottom
	got := cardFor(t, layout, product)
	if strings.Index(got, "image=") < strings.Index(got, "**[A guitar]") {
		t.Errorf("the picture is still above the writing:\n%s", got)
	}

	// Filling the card is not stacking at all: the writing is inside the
	// panel the picture is drawn in, which is what puts it over the picture.
	layout.ImagePosition = ImageFull
	layout.TextPosition = TextCenter
	got = cardFor(t, layout, product)
	if !strings.Contains(got, "align=center") {
		t.Errorf("the writing is not placed on the picture:\n%s", got)
	}
	writing := strings.Index(got, "**[A guitar]")
	closed := strings.Index(got, "--/panel--")
	if writing == -1 || closed == -1 || writing > closed {
		t.Errorf("the writing is not inside the picture's panel:\n%s", got)
	}
}

func TestThePlateBehindTheWritingIsASetting(t *testing.T) {
	layout := DefaultIndexLayout()
	layout.TextBackground = true
	layout.TextColor = "#101820"
	layout.TextPadding, layout.TextMargin, layout.TextRadius = 12, 4, 16

	got := cardFor(t, layout, &Product{Title: "A guitar", SKU: "gtr"})
	for _, want := range []string{
		"fill=#101820", "padding=12", "margin=4", "radius=16",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("%q missing from:\n%s", want, got)
		}
	}
}

func TestTheDCRFigureCanBeLeftOffTheShopFront(t *testing.T) {
	s := &Store{indexPath: "/", log: slog.Disabled}
	s.cfg.ExchangeRateProvider = func() float64 { return 25 }

	s.layout = DefaultIndexLayout()
	if got := s.productCard(&Product{Title: "A record", SKU: "r1", Price: 50}); !strings.Contains(got, "2.0000 DCR") {
		t.Errorf("the DCR figure is missing by default:\n%s", got)
	}

	s.layout.ShowDCR = false
	got := s.productCard(&Product{Title: "A record", SKU: "r1", Price: 50})
	if strings.Contains(got, "DCR") {
		t.Errorf("the DCR figure is still on a card that turned it off:\n%s", got)
	}
	if !strings.Contains(got, "$50.00") {
		t.Errorf("the price went with it:\n%s", got)
	}
}

// TestASettingThatCannotMeanAnythingIsCorrected covers the file being one a
// seller can open in an editor.
//
// Every field falls back on its own: refusing the whole file would take the
// shop front down over one misspelled word, and it is read at start-up where
// nobody is watching for an error.
func TestASettingThatCannotMeanAnythingIsCorrected(t *testing.T) {
	def := DefaultIndexLayout()
	got := IndexLayout{
		FixedImage:    true,
		ImageWidth:    -5,
		ImageHeight:   99999,
		Crop:          "sideways",
		ImagePosition: "diagonal",
		TextPosition:  "floating",
		TextColor:     "red, padding=999",
		TextPadding:   -1,
		TextRadius:    100000,
	}.normalize()

	if got.ImageWidth != def.ImageWidth || got.ImageHeight != def.ImageHeight {
		t.Errorf("a picture size out of range was taken: %+v", got)
	}
	if got.Crop != def.Crop || got.ImagePosition != def.ImagePosition ||
		got.TextPosition != def.TextPosition {
		t.Errorf("a word that is not one of the choices was taken: %+v", got)
	}
	if got.TextColor != def.TextColor {
		t.Error("a colour holding a comma was taken, which would have ended " +
			"the setting early in the markup the card is written as")
	}
	if got.TextPadding != def.TextPadding || got.TextRadius != def.TextRadius {
		t.Errorf("a length out of range was taken: %+v", got)
	}
}

func TestTheSettingsSurviveARestart(t *testing.T) {
	root := t.TempDir()
	want := DefaultIndexLayout()
	want.FixedImage = true
	want.ImageWidth, want.ImageHeight = 600, 400
	want.Crop = CropTop
	want.ImagePosition = ImageFull
	want.ShowDCR = false

	if err := writeIndexLayout(root, want); err != nil {
		t.Fatal(err)
	}
	got, err := readIndexLayout(root)
	if err != nil {
		t.Fatal(err)
	}
	if got != want {
		t.Fatalf("got %+v, want %+v", got, want)
	}
}

// TestAFileFromAnOlderVersionKeepsItsDefaults covers a setting added after a
// shop's file was written.
//
// Read into a blank struct, a line that is not there would be that field's
// zero value -- so adding a setting would turn it off in every shop that
// already had a file, silently.
func TestAFileFromAnOlderVersionKeepsItsDefaults(t *testing.T) {
	root := t.TempDir()
	err := os.WriteFile(filepath.Join(root, storefrontFile),
		[]byte("image_position = \"bottom\"\n"), 0o600)
	if err != nil {
		t.Fatal(err)
	}

	got, err := readIndexLayout(root)
	if err != nil {
		t.Fatal(err)
	}
	if got.ImagePosition != ImageBottom {
		t.Errorf("the one setting in the file was not read: %+v", got)
	}
	if !got.ShowDCR {
		t.Error("a setting the file predates was turned off rather than left " +
			"at its default")
	}
	if got.ImageWidth != DefaultIndexLayout().ImageWidth {
		t.Errorf("a size the file predates came back as nought: %+v", got)
	}
}

// TestTheShopFrontDoesNotWedgeItself covers the lock a card is read under.
//
// A template is executed with the store's own lock held -- handleIndex takes
// it to read the catalogue and does not let go until the page is rendered --
// and the template calls productCard. So a card that asks the store for its
// settings under that lock asks for a lock the same goroutine is already
// holding, and sync.Mutex is not reentrant.
//
// What that looked like was not a crash. The shop front request never
// returned, every later request queued behind it, the directory watcher
// stopped reloading, and saving a setting wrote the file and then hung -- so
// the switch that saved it sprang back. Nothing was logged, because nothing
// failed: it simply stopped.
func TestTheShopFrontDoesNotWedgeItself(t *testing.T) {
	s := &Store{indexPath: "/", log: slog.Disabled, layout: DefaultIndexLayout()}

	done := make(chan string, 1)
	go func() {
		// Exactly what handleIndex does: the lock is held across the whole
		// of the render.
		s.mtx.Lock()
		defer s.mtx.Unlock()
		done <- s.productCard(&Product{Title: "A guitar", SKU: "gtr"})
	}()

	select {
	case card := <-done:
		if !strings.Contains(card, "A guitar") {
			t.Fatalf("got %q", card)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("the shop front wedged itself: a card read the store's " +
			"settings under the lock the render already holds")
	}
}

func TestAShopWithNoFileReadsTheDefaults(t *testing.T) {
	got, err := readIndexLayout(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	if got != DefaultIndexLayout() {
		t.Fatalf("got %+v", got)
	}
}
