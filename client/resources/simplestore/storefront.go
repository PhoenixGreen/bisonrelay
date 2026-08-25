package simplestore

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/pelletier/go-toml"
)

// storefront.go is how the shop front lays a product out.
//
// The front page is a grid of products, and until now what one looked like
// was written into index.tmpl: a picture, a link, a price. Changing it meant
// editing a template -- and a seller who wanted their pictures to line up had
// to know that a grid cell is as tall as what is in it, so a shop front of
// pictures at six different shapes is a ragged page with no setting to blame.
//
// So the shape of a card is a setting rather than a line in a template. The
// template calls productCard and this decides what that is, which means the
// seller changes their shop front from the Store setup tab and every card
// changes together.
//
// Kept in the store's own directory rather than in the client's config, for
// the same reason the products are: it is a fact about this shop, it travels
// with the shop's folder, and a seller who copies the folder to another
// machine takes their front page with them.

// storefrontFile is where the settings are kept, inside the store.
const storefrontFile = "storefront.toml"

// Image positions on a card.
const (
	// ImageTop is the picture above the writing, which is what a shop front
	// looked like before any of this was a setting.
	ImageTop = "top"

	// ImageFull is the picture behind the whole card, with the writing over
	// it.
	ImageFull = "full"

	// ImageBottom is the picture under the writing.
	ImageBottom = "bottom"
)

// Where a picture is cropped from when it does not fit the shape asked for.
//
// Named by the part of the picture that is kept, because that is the decision
// being made: a photograph of a person crops from the top, a photograph of a
// room from the middle.
const (
	CropTopLeft  = "topleft"
	CropTop      = "top"
	CropTopRight = "topright"
	CropLeft     = "left"
	CropCenter   = "center"
	CropRight    = "right"
	CropBottom   = "bottom"
)

// Where the writing sits on a card whose picture fills it.
const (
	TextTop    = "top"
	TextCenter = "center"
	TextBottom = "bottom"
)

// IndexLayout is what one product looks like on the shop front.
//
// Every field has a zero value that is either the old behaviour or is
// corrected on load, so a shop with no storefront.toml -- which is every shop
// that existed before this -- renders exactly as it did.
type IndexLayout struct {
	// FixedImage is whether every picture is drawn at the same shape.
	//
	// Off, a picture is drawn at whatever shape it is, which is the ragged
	// front page. On, ImageWidth and ImageHeight say what shape, and a
	// picture that is not that shape is cropped to it.
	FixedImage  bool `json:"fixed_image" toml:"fixed_image"`
	ImageWidth  int  `json:"image_width" toml:"image_width"`
	ImageHeight int  `json:"image_height" toml:"image_height"`

	// Crop is which part of a picture is kept when it is cropped.
	Crop string `json:"crop" toml:"crop"`

	// ImagePosition is where the picture sits on the card: above the
	// writing, below it, or behind all of it.
	ImagePosition string `json:"image_position" toml:"image_position"`

	// TextBackground is whether the writing sits on a panel of its own,
	// and what that panel looks like.
	//
	// Off by default: a card on the page's own background is what a shop
	// front was, and a plate behind the writing is only needed when there
	// is a picture behind it -- which is the ImageFull card.
	TextBackground bool   `json:"text_background" toml:"text_background"`
	TextColor      string `json:"text_color" toml:"text_color"`
	TextPadding    int    `json:"text_padding" toml:"text_padding"`
	TextMargin     int    `json:"text_margin" toml:"text_margin"`
	TextRadius     int    `json:"text_radius" toml:"text_radius"`

	// TextPosition is where the writing sits on a card whose picture fills
	// it. Read only for ImageFull: on the other two the picture and the
	// writing are stacked, and where the writing is is which of them.
	TextPosition string `json:"text_position" toml:"text_position"`

	// ShowDCR is whether a card shows what its price comes to in DCR as
	// well as in dollars.
	//
	// Both are true and both are useful -- see approxDCR -- but a shop
	// front is a page of prices at a glance, and two numbers on every card
	// is a busier page than some sellers want. The product's own page always
	// shows both: that is where somebody is deciding what they will pay.
	ShowDCR bool `json:"show_dcr" toml:"show_dcr"`
}

// DefaultIndexLayout is the shop front as it was before any of this was a
// setting: a picture at its own shape, the link and price under it, and the
// DCR figure beside the dollar one.
func DefaultIndexLayout() IndexLayout {
	return IndexLayout{
		FixedImage:    false,
		ImageWidth:    400,
		ImageHeight:   400,
		Crop:          CropCenter,
		ImagePosition: ImageTop,
		TextColor:     "raised",
		TextPadding:   10,
		TextMargin:    0,
		TextRadius:    8,
		TextPosition:  TextBottom,
		ShowDCR:       true,
	}
}

// maxCardLength is as large as any of the card's lengths may be, in the
// units the settings are written in.
//
// A guard rather than a preference. These numbers reach a renderer as a
// picture's shape and a panel's padding, and a card asking for a padding of
// ten thousand is a shop front nobody can read -- including the seller who
// typed it and now cannot find the field to fix it.
const maxCardLength = 2000

// normalize corrects anything the settings cannot mean.
//
// Every field falls back to the default rather than the whole file being
// refused: this is read at start-up, and a shop that will not serve its front
// page because one word in it is misspelled is a worse answer than a shop
// that draws that one thing the ordinary way.
func (l IndexLayout) normalize() IndexLayout {
	def := DefaultIndexLayout()

	// Nothing set at all is a layout nobody has chosen, not a shop front
	// with every setting turned off: a seller who turns a setting off still
	// leaves a picture size and a crop behind. So the wholly empty struct
	// is the defaults, which is what a Store built without reading a file
	// holds.
	if l == (IndexLayout{}) {
		return def
	}

	if l.ImageWidth <= 0 || l.ImageWidth > maxCardLength {
		l.ImageWidth = def.ImageWidth
	}
	if l.ImageHeight <= 0 || l.ImageHeight > maxCardLength {
		l.ImageHeight = def.ImageHeight
	}
	if !oneOf(l.Crop, CropTopLeft, CropTop, CropTopRight, CropLeft,
		CropCenter, CropRight, CropBottom) {
		l.Crop = def.Crop
	}
	if !oneOf(l.ImagePosition, ImageTop, ImageFull, ImageBottom) {
		l.ImagePosition = def.ImagePosition
	}
	if !oneOf(l.TextPosition, TextTop, TextCenter, TextBottom) {
		l.TextPosition = def.TextPosition
	}
	if l.TextColor == "" || strings.ContainsAny(l.TextColor, ",]=\n") {
		// Anything with a comma or a bracket in it would end the setting
		// early in the markup the card is written as, so it is not a colour
		// this can pass on.
		l.TextColor = def.TextColor
	}
	l.TextPadding = clampLength(l.TextPadding, def.TextPadding)
	l.TextMargin = clampLength(l.TextMargin, 0)
	l.TextRadius = clampLength(l.TextRadius, def.TextRadius)
	return l
}

func oneOf(value string, allowed ...string) bool {
	for _, a := range allowed {
		if value == a {
			return true
		}
	}
	return false
}

func clampLength(value, fallback int) int {
	if value < 0 || value > maxCardLength {
		return fallback
	}
	return value
}

// readIndexLayout is the settings a store's directory holds, or the defaults
// for a store that has never had any.
func readIndexLayout(root string) (IndexLayout, error) {
	if root == "" {
		return DefaultIndexLayout(), nil
	}
	data, err := os.ReadFile(filepath.Join(root, storefrontFile))
	if os.IsNotExist(err) {
		return DefaultIndexLayout(), nil
	} else if err != nil {
		return DefaultIndexLayout(), err
	}

	// Read over the defaults rather than into a blank, so a file written by
	// an older version -- one that has no line for a setting added since --
	// gets that setting's default instead of its zero value.
	layout := DefaultIndexLayout()
	if err := toml.Unmarshal(data, &layout); err != nil {
		return DefaultIndexLayout(), fmt.Errorf("unable to read %s: %w",
			storefrontFile, err)
	}
	return layout.normalize(), nil
}

// writeIndexLayout saves the settings into the store's directory.
func writeIndexLayout(root string, layout IndexLayout) error {
	if root == "" {
		return fmt.Errorf("no store to save the shop front of")
	}
	data, err := toml.Marshal(layout.normalize())
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(root, storefrontFile), data, 0o644)
}

// IndexLayout is what the shop front currently lays its products out as.
//
// Under layoutMtx, never the store's own mtx: this is read from inside a
// template, and a template runs with mtx already held. See the field.
func (s *Store) IndexLayout() IndexLayout {
	s.layoutMtx.Lock()
	defer s.layoutMtx.Unlock()
	return s.layout.normalize()
}

// SetIndexLayout changes how the shop front lays its products out, and saves
// it.
//
// Saved before it takes effect: a change that is live and not written down is
// one that undoes itself at the next restart, with nothing to say why.
func (s *Store) SetIndexLayout(layout IndexLayout) (IndexLayout, error) {
	layout = layout.normalize()
	if err := writeIndexLayout(s.root, layout); err != nil {
		return IndexLayout{}, err
	}
	s.layoutMtx.Lock()
	s.layout = layout
	s.layoutMtx.Unlock()
	return layout, nil
}

// productCard is one product as it appears on the shop front.
//
// Markup rather than a widget, because the shop front is a page: it is
// rendered by whoever is reading it, in their own theme, and the only thing
// that crosses the wire is what is written here. The blocks it uses -- a
// panel with a picture in it, a cell marker -- are the page markup any page
// of a site may use, so nothing here is special to a store except the
// decision about which of them to write.
func (s *Store) productCard(p *Product) string {
	if p == nil {
		return ""
	}
	layout := s.IndexLayout()
	link := "product/" + p.SKU

	image := ProductImagePath(p.Image)
	if image == "" {
		// The placeholder is load-bearing rather than decorative: a card
		// with no picture at all in the ImageFull layout is a card with
		// nothing to put the writing on.
		image = ProductImagePath(placeholderImage)
	}

	var text strings.Builder
	fmt.Fprintf(&text, "**[%s](%s)**\n", p.Title, link)
	text.WriteString(Money(p.Price))
	if layout.ShowDCR {
		if approx := s.approxDCR(p.Price); approx != "" {
			fmt.Fprintf(&text, " · ≈ %s", approx)
		}
	}
	text.WriteString("\n")

	writing := text.String()
	if layout.TextBackground {
		writing = fmt.Sprintf("--panel[fill=%s, padding=%d, margin=%d, radius=%d]--\n%s--/panel--\n",
			layout.TextColor, layout.TextPadding, layout.TextMargin,
			layout.TextRadius, writing)
	}

	picture := s.cardPicture(layout, image, link)

	switch layout.ImagePosition {
	case ImageBottom:
		return writing + picture
	case ImageFull:
		// One panel: the picture is the card, and the writing sits on it
		// wherever the seller asked for.
		return fmt.Sprintf("--panel[image=%s, %s, link=%s, align=%s, padding=%d]--\n%s--/panel--\n",
			image, s.cardShape(layout), link, layout.TextPosition,
			layout.TextPadding, writing)
	default:
		return picture + writing
	}
}

// cardPicture is the picture on a card that has the writing beside it rather
// than on it.
//
// A panel rather than a plain Markdown image, so that the picture is part of
// the link to the product. Somebody looking at a shop front and tapping the
// picture of the thing they want has said what they want; before this that
// tap did nothing and only the title underneath was a link.
func (s *Store) cardPicture(layout IndexLayout, image, link string) string {
	shape := s.cardShape(layout)
	if shape != "" {
		shape = ", " + shape
	}
	return fmt.Sprintf("--panel[image=%s%s, link=%s]--\n--/panel--\n",
		image, shape, link)
}

// cardShape is the settings that say what shape a picture is drawn at, or
// nothing at all when the seller has not asked for one.
func (s *Store) cardShape(layout IndexLayout) string {
	if !layout.FixedImage {
		return ""
	}
	return fmt.Sprintf("ratio=%dx%d, crop=%s", layout.ImageWidth,
		layout.ImageHeight, layout.Crop)
}
