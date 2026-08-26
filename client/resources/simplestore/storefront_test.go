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

func TestABorderIsDrawnRoundTheWholeCard(t *testing.T) {
	layout := DefaultIndexLayout()
	got := cardFor(t, layout, &Product{Title: "A guitar", SKU: "gtr"})
	if strings.Contains(got, "border=") {
		t.Errorf("a shop that asked for no border got one:\n%s", got)
	}

	layout.CardBorder = true
	layout.CardBorderWidth, layout.CardBorderRadius = 2, 16
	layout.CardBorderColor = "#334455"
	layout.CardPadding, layout.CardMargin = 12, 4
	got = cardFor(t, layout, &Product{Title: "A guitar", SKU: "gtr"})

	for _, want := range []string{
		"border=2", "color=#334455", "radius=16", "padding=12", "margin=4",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("%q missing from:\n%s", want, got)
		}
	}
	// Round the whole card: the picture and the writing are both inside it.
	if !strings.HasPrefix(strings.TrimSpace(got), "--panel[border=") {
		t.Errorf("the border is not the outermost part of the card:\n%s", got)
	}
}

func TestThePicturesCornersAreSetOneByOne(t *testing.T) {
	layout := DefaultIndexLayout()
	if got := cardFor(t, layout, &Product{SKU: "gtr"}); strings.Contains(got, "radius=") {
		t.Errorf("a picture nobody rounded came out rounded:\n%s", got)
	}

	// Rounded at the top, square where the writing meets it.
	layout.ImageCornerTopLeft, layout.ImageCornerTopRight = 12, 12
	got := cardFor(t, layout, &Product{SKU: "gtr"})
	if !strings.Contains(got, "radius=12 12 0 0") {
		t.Errorf("the corners are not as asked:\n%s", got)
	}
}

func TestThePlateIsPlacedAndSized(t *testing.T) {
	layout := DefaultIndexLayout()
	layout.TextBackground = true
	layout.ImagePosition = ImageFull
	layout.TextAlign = TextRight
	layout.TextMargin = 6

	// Full width: the plate runs the width of the picture, and stands off
	// its edge by the margin.
	got := cardFor(t, layout, &Product{Title: "A guitar", SKU: "gtr"})
	if !strings.Contains(got, "justify=stretch") {
		t.Errorf("a full-width plate is not full width:\n%s", got)
	}
	if !strings.Contains(got, "padding=6") {
		t.Errorf("the plate does not stand off the edge:\n%s", got)
	}
	if !strings.Contains(got, "text=right") {
		t.Errorf("the writing is not on the side asked for:\n%s", got)
	}

	// Flush and hugging the writing: no room at the edge, and only as wide
	// as what is on it.
	layout.TextFullWidth = false
	layout.TextFlush = true
	got = cardFor(t, layout, &Product{Title: "A guitar", SKU: "gtr"})
	if !strings.Contains(got, "justify=right") {
		t.Errorf("the plate still runs the whole width:\n%s", got)
	}
	if !strings.Contains(got, "padding=0") {
		t.Errorf("a plate asked to sit flush is still standing off:\n%s", got)
	}
}

// TestWhichSideTheWritingSitsOnReachesTheCard covers the setting with no
// plate behind it.
//
// Which side the writing sits on is a fact about the writing, but it was
// written only into the plate -- so a shop that had not turned the plate on
// had a setting that saved, showed the answer it had saved, and changed
// nothing at all on the page.
func TestWhichSideTheWritingSitsOnReachesTheCard(t *testing.T) {
	layout := DefaultIndexLayout()
	layout.TextAlign = TextCenter

	got := cardFor(t, layout, &Product{Title: "A guitar", SKU: "gtr"})
	if !strings.Contains(got, "text=center") {
		t.Errorf("a card with no plate is not aligned:\n%s", got)
	}

	// The left is what a card has always been, so it writes nothing: a shop
	// that never touched this setting renders the markup it did before it
	// existed.
	layout.TextAlign = TextLeft
	if got := cardFor(t, layout, &Product{SKU: "gtr"}); strings.Contains(got, "text=") {
		t.Errorf("the default writes a setting nobody asked for:\n%s", got)
	}
}

// TestAPlateThatIsNotFullWidthIsToldWhatToBe covers the second half of the
// same setting.
//
// A block of a page is the width of the page. A plate that is not the full
// width has to be told what to be instead and where to sit -- and on a card
// whose picture is above or below the writing there is no other panel to do
// it, so turning the setting off did nothing.
func TestAPlateThatIsNotFullWidthIsToldWhatToBe(t *testing.T) {
	layout := DefaultIndexLayout()
	layout.TextBackground = true
	layout.TextFullWidth = false
	layout.TextAlign = TextRight

	got := cardFor(t, layout, &Product{Title: "A guitar", SKU: "gtr"})
	if !strings.Contains(got, "justify=right") {
		t.Errorf("the plate still runs the width of the card:\n%s", got)
	}

	// Full width is the plain block, and writes nothing extra.
	layout.TextFullWidth = true
	got = cardFor(t, layout, &Product{Title: "A guitar", SKU: "gtr"})
	if strings.Contains(got, "justify=") {
		t.Errorf("a full-width plate was wrapped in a panel for nothing:\n%s", got)
	}
}

func TestTheThreeRowLayoutSaysWhatItSells(t *testing.T) {
	layout := DefaultIndexLayout()
	layout.TextLayout = TextRows
	layout.ButtonLabel = "Buy Now"

	got := cardFor(t, layout, &Product{Title: "A guitar", SKU: "gtr",
		Price: 20, Description: "A lovely guitar with a spruce top."})

	title := strings.Index(got, "title: A guitar")
	summary := strings.Index(got, "summary: A lovely guitar")
	price := strings.Index(got, "meta: $20.00")
	button := strings.Index(got, "button: Buy Now")
	if title == -1 || summary == -1 || price == -1 || button == -1 {
		t.Fatalf("a row is missing:\n%s", got)
	}
	if !(title < summary && summary < price && price < button) {
		t.Errorf("the rows are not title, description, price and button:\n%s", got)
	}

	// One block rather than three. Three blocks carry three blocks' worth of
	// the reader's paragraph spacing, wrap the description to the card's
	// width, and stack the last row when the card is narrow.
	if !strings.Contains(got, "--listing--") {
		t.Errorf("the rows are not one composition:\n%s", got)
	}
	if strings.Contains(got, "--columns[") {
		t.Errorf("the price and the button are in a run of columns, which "+
			"stacks on a narrow card and draws a rule between them:\n%s", got)
	}
	if !strings.Contains(got, "link: product/gtr") {
		t.Errorf("the card does not open the product:\n%s", got)
	}
}

// TestWhatASellerWroteCannotEndAField covers the block whose fields are one
// per line.
//
// A title with a newline in it would end its own field, and the line after it
// -- if it holds a colon -- would be read as another field entirely.
func TestWhatASellerWroteCannotEndAField(t *testing.T) {
	layout := DefaultIndexLayout()
	layout.TextLayout = TextRows

	got := cardFor(t, layout, &Product{
		Title: "A guitar\nbutton: Free",
		SKU:   "gtr",
	})
	// Not "does the text appear" -- it does, flattened into the title. What
	// must not happen is a *line* of its own, which is what a field is.
	for _, line := range strings.Split(got, "\n") {
		if strings.HasPrefix(strings.TrimSpace(line), "button: Free") {
			t.Errorf("a title wrote a field of its own:\n%s", got)
		}
	}
	if !strings.Contains(got, "title: A guitar button: Free") {
		t.Errorf("the title was lost rather than flattened:\n%s", got)
	}
}

func TestACardCarriesTheOpeningOfADescription(t *testing.T) {
	// A description is written for the product's own page, where there is
	// room for a list of features. A card carrying all of it is as tall as
	// the page, and a row of them is a page nothing can be compared on.
	if got := cardSummary("First para.\n\n- One\n- Two"); got != "First para." {
		t.Errorf("got %q, want the first paragraph alone", got)
	}
	if got := cardSummary("A line\nwrapped in the source"); got != "A line wrapped in the source" {
		t.Errorf("got %q, want one line", got)
	}
	if got := cardSummary("   "); got != "" {
		t.Errorf("got %q, want nothing at all", got)
	}

	long := cardSummary(strings.Repeat("word ", 100))
	if len([]rune(long)) > 145 {
		t.Errorf("a long description was not cut: %d runes", len([]rune(long)))
	}
	if !strings.HasSuffix(long, "…") {
		t.Errorf("a description was cut without saying so: %q", long)
	}
	if strings.HasSuffix(strings.TrimSuffix(long, "…"), " ") {
		t.Errorf("cut mid-space: %q", long)
	}
}

func TestASettingHoldingACommaCannotBreakTheCard(t *testing.T) {
	// A card is markup whose settings are separated by commas and closed by
	// a bracket. Nothing here is a security boundary -- these are the
	// seller's own settings -- but a shop front should not be breakable by
	// typing a comma into a colour box.
	layout := DefaultIndexLayout()
	layout.TextColor = "red, padding=99"
	layout.CardBorderColor = "blue]--"
	layout.ButtonLabel = "Buy, now"
	got := layout.normalize()

	def := DefaultIndexLayout()
	if got.TextColor != def.TextColor || got.CardBorderColor != def.CardBorderColor ||
		got.ButtonLabel != def.ButtonLabel {
		t.Errorf("a setting that would end the markup early was taken: %+v", got)
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
