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

// Which side the writing sits on.
const (
	TextLeft  = "left"
	TextRight = "right"
	// TextCenter is shared with the list above: a plate in the middle of a
	// card is in the middle whichever way you are reading it.
)

// Where the shop's links go.
const (
	// NavOwn is a bar of the shop's own, above every page it renders. What
	// a shop hosted without a site has, since there is no other bar to be
	// in.
	NavOwn = "own"

	// NavLinks puts them at the right-hand end of the site's own bar, as
	// words, with what is waiting behind each -- the cart's count -- drawn
	// over it.
	NavLinks = "links"

	// NavIcons is the same, as icons, with the words kept as what each is
	// called when hovered.
	NavIcons = "icons"
)

// What a card's writing is made of.
const (
	// TextPlain is the title and the price, which is what a shop front card
	// was before it was a setting.
	TextPlain = "plain"

	// TextRows is three rows: the title, the description, and the price
	// beside a button.
	TextRows = "rows"
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

	// The plate's padding per side, or below nought for whichever sides are
	// content with TextPadding.
	//
	// A base and four exceptions rather than four numbers, so that a shop
	// which has only ever set one padding keeps one padding -- in its file,
	// in its markup and in the control it set it with. Writing on a plate is
	// usually inset the same all round; the side that wants a different
	// answer is a caption that has to clear the bottom of a photograph, and
	// that is one side rather than four.
	TextPaddingTop    int `json:"text_padding_top" toml:"text_padding_top"`
	TextPaddingRight  int `json:"text_padding_right" toml:"text_padding_right"`
	TextPaddingBottom int `json:"text_padding_bottom" toml:"text_padding_bottom"`
	TextPaddingLeft   int `json:"text_padding_left" toml:"text_padding_left"`

	// TextPosition is where the writing sits on a card whose picture fills
	// it. Read only for ImageFull: on the other two the picture and the
	// writing are stacked, and where the writing is is which of them.
	TextPosition string `json:"text_position" toml:"text_position"`

	// TextFullWidth is whether the plate runs the whole width of the card
	// or only as wide as the writing on it.
	//
	// Read whether or not there is a plate: it is where the writing sits as
	// much as how wide its background is, and a card with no plate still
	// puts its title somewhere.
	TextFullWidth bool `json:"text_full_width" toml:"text_full_width"`

	// TextFlush is whether the plate touches the edge of the picture it
	// sits against, rather than standing off it by TextMargin.
	//
	// Only means anything at the top and the bottom. A band across the foot
	// of a photograph is a common way to caption one, and a band a few
	// pixels short of the foot is that with a mistake in it.
	TextFlush bool `json:"text_flush" toml:"text_flush"`

	// TextAlign is which side the writing sits on: left, center or right.
	TextAlign string `json:"text_align" toml:"text_align"`

	// TextLayout is what the writing is made of: the title and the price, or
	// three rows with the description and a button.
	TextLayout string `json:"text_layout" toml:"text_layout"`

	// ButtonLabel is what the three-row layout's button says, and the rest
	// is what it looks like.
	//
	// A colour of its own rather than only one of the theme's button roles.
	// The roles are what the app's own buttons are, and they are the right
	// answer for a page -- but the button on a shop's card is the one thing
	// on that card somebody is meant to press, and a seller with a brand
	// colour wants it in that colour.
	ButtonLabel string `json:"button_label" toml:"button_label"`

	// SoldOutLabel is the ribbon a card carries when a buyer cannot have
	// what is on it.
	//
	// One word for two reasons -- the shop has run out, or the shop cannot
	// take the money for it -- because from the buyer's side they are the
	// same fact, and a card is not the place to explain the difference. The
	// product's own page says which.
	//
	// The seller's own words, because shops say this differently: "Sold
	// out", "All gone", "Back soon".
	SoldOutLabel string `json:"sold_out_label" toml:"sold_out_label"`

	// SoldOutColor is what the ribbon is drawn in, or empty for the theme's
	// own error colour.
	//
	// Empty by default, and that default is the point: a thing nobody can
	// buy is the one state on a shop front that is genuinely bad news, and
	// every theme already has a colour for that. A colour picked here is
	// that colour for every reader, in whatever theme they are using.
	SoldOutColor string `json:"sold_out_color" toml:"sold_out_color"`

	// LowStockAt is the count at or below which a card says how many are
	// left, or nought for a shop that would rather not.
	//
	// A different message from the ribbon above, and worth keeping apart.
	// One says you cannot have this; the other says you can, and to get on
	// with it. Off by default, because "2 left" is a nudge and a shop that
	// has not asked for one should not be making it.
	LowStockAt int `json:"low_stock_at" toml:"low_stock_at"`

	// LowStockColor is what that one is drawn in.
	//
	// Its own setting rather than the sold-out colour, because they are not
	// the same news. Plain by default: the count is information, and a
	// warning colour on "2 left" is a shop shouting about its own stock.
	LowStockColor string `json:"low_stock_color" toml:"low_stock_color"`
	ButtonColor   string `json:"button_color" toml:"button_color"`
	ButtonRadius  int    `json:"button_radius" toml:"button_radius"`
	ButtonPadding int    `json:"button_padding" toml:"button_padding"`

	// RowGap is the room between the title and the description, and
	// MetaGap the room above the price-and-button row.
	//
	// Two, because they are not the same join: the description belongs to
	// the title above it and sits close under it, while the last row is the
	// end of the card and usually wants air above it. The seller's UI offers
	// to move them together, which is what most cards want.
	RowGap  int `json:"row_gap" toml:"row_gap"`
	MetaGap int `json:"meta_gap" toml:"meta_gap"`

	// TitleOneLine keeps a product's name to one line, cutting it with an
	// ellipsis the way the description is cut.
	//
	// Off by default: losing the end of a name is worse than a card an
	// extra line tall, unless the seller says otherwise -- and a shop whose
	// names are long is a shop that would rather they lined up.
	TitleOneLine bool `json:"title_one_line" toml:"title_one_line"`

	// StoreNav is where the shop's links go: a bar of its own, or the
	// right-hand end of the site's.
	//
	// A shop inside a site has two bars otherwise -- the site's pages and
	// the shop's -- stacked one above the other, which is two rows of chrome
	// each saying half of where you can go. A shop hosted on its own has no
	// site bar to join, so it keeps its own whatever this says.
	StoreNav string `json:"store_nav" toml:"store_nav"`

	// NavPlain drops the box the site's bar draws round each of its links,
	// for the shop's links only.
	//
	// A row of icons in pills is a row of buttons, which is a different
	// thing from a row of icons -- and a bar often wants the site's half as
	// the first and the shop's as the second.
	NavPlain bool `json:"nav_plain" toml:"nav_plain"`

	// NavGap is the room between the shop's links, or below nought to keep
	// whatever the bar keeps between the site's own.
	//
	// Its own setting because icons want to sit closer together than words
	// do, and the shop's half of the bar is the half that is usually icons.
	NavGap int `json:"nav_gap" toml:"nav_gap"`

	// NavIconSize is how large the shop's icons are drawn, or below nought
	// for the ordinary size. NavInset is the room kept at the end of the
	// bar, so the last of them is not pressed against the edge -- which is
	// also where a cart's count needs somewhere to sit.
	NavIconSize int `json:"nav_icon_size" toml:"nav_icon_size"`
	NavInset    int `json:"nav_inset" toml:"nav_inset"`

	// NavShop is whether the shop's links include the one to its front page.
	//
	// Off is the ordinary answer for a site whose own bar already has a link
	// to the shop -- which is how a visitor got there in the first place. Two
	// links to one page in one bar is one of them wasted, and the room it
	// takes is room the cart and the orders could have.
	NavShop bool `json:"nav_shop" toml:"nav_shop"`

	// NavAdmin is whether the shop's links include the one to the admin
	// pages.
	//
	// The seller's own link and nobody else's -- a buyer is never shown it
	// and cannot reach those pages -- so this is about the seller's own bar
	// being tidy. The pages themselves stay where they are: a link that is
	// not drawn is not a route that is gone, and a bookmark keeps working.
	NavAdmin bool `json:"nav_admin" toml:"nav_admin"`

	// GridGap is the room between one product and the next, or below nought
	// to leave it to whatever the reader's own guide keeps.
	//
	// The reader's by default, and that default is the point: most of what
	// looks like space between two products is the cards' own margins, and a
	// shop that has not asked for anything here should be laid out the way
	// its reader lays out a gallery.
	GridGap int `json:"grid_gap" toml:"grid_gap"`

	// GridMargin is the room down either side of the whole grid.
	//
	// The app's own to begin with. A page keeps a margin so its writing does
	// not run into the edge of the window; a grid of cards is already a set
	// of boxes with room of their own, so a shop front is somewhere a seller
	// may reasonably want less of it -- on a phone it can be the difference
	// between three cards across and two.
	GridMargin int `json:"grid_margin" toml:"grid_margin"`

	// CardBorder is whether a line is drawn round the whole card, and what
	// that line and the room around it look like.
	//
	// Round the card rather than round the picture: a border is what makes a
	// card a card on a page that has no other division between one product
	// and the next.
	CardBorder       bool   `json:"card_border" toml:"card_border"`
	CardBorderWidth  int    `json:"card_border_width" toml:"card_border_width"`
	CardBorderColor  string `json:"card_border_color" toml:"card_border_color"`
	CardBorderRadius int    `json:"card_border_radius" toml:"card_border_radius"`
	CardPadding      int    `json:"card_padding" toml:"card_padding"`
	CardMargin       int    `json:"card_margin" toml:"card_margin"`

	// The card's padding per side, or below nought for whichever sides are
	// content with CardPadding -- the same bargain the plate's padding
	// makes, for the same reason.
	CardPaddingTop    int `json:"card_padding_top" toml:"card_padding_top"`
	CardPaddingRight  int `json:"card_padding_right" toml:"card_padding_right"`
	CardPaddingBottom int `json:"card_padding_bottom" toml:"card_padding_bottom"`
	CardPaddingLeft   int `json:"card_padding_left" toml:"card_padding_left"`

	// The picture's own corners, one by one.
	//
	// One by one because a picture at the top of a card is rounded at the
	// top and square where the writing meets it. The seller's UI offers to
	// set all four together, which is what most shops want; the four numbers
	// are what makes the other answer possible at all.
	ImageCornerTopLeft     int `json:"image_corner_top_left" toml:"image_corner_top_left"`
	ImageCornerTopRight    int `json:"image_corner_top_right" toml:"image_corner_top_right"`
	ImageCornerBottomRight int `json:"image_corner_bottom_right" toml:"image_corner_bottom_right"`
	ImageCornerBottomLeft  int `json:"image_corner_bottom_left" toml:"image_corner_bottom_left"`

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
		FixedImage:        false,
		ImageWidth:        400,
		ImageHeight:       400,
		Crop:              CropCenter,
		ImagePosition:     ImageTop,
		TextColor:         "raised",
		TextPadding:       10,
		TextPaddingTop:    padSideUnset,
		TextPaddingRight:  padSideUnset,
		TextPaddingBottom: padSideUnset,
		TextPaddingLeft:   padSideUnset,
		TextMargin:        0,
		TextRadius:        8,
		TextPosition:      TextBottom,
		TextFullWidth:     true,
		TextAlign:         TextLeft,
		TextLayout:        TextPlain,
		ButtonLabel:       "Buy Now",
		SoldOutLabel:      "Currently unavailable",
		SoldOutColor:      "",
		LowStockAt:        0,
		LowStockColor:     "text",
		ButtonColor:       "",
		ButtonRadius:      8,
		ButtonPadding:     12,
		RowGap:            4,
		MetaGap:           8,
		StoreNav:          NavOwn,
		NavGap:            navGapTheirs,
		NavIconSize:       navGapTheirs,
		NavInset:          0,
		NavShop:           true,
		NavAdmin:          true,
		GridGap:           gridGapTheirs,
		GridMargin:        defaultPageEdge,

		CardBorderWidth:   1,
		CardBorderColor:   "outline",
		CardBorderRadius:  8,
		CardPadding:       10,
		CardMargin:        0,
		CardPaddingTop:    padSideUnset,
		CardPaddingRight:  padSideUnset,
		CardPaddingBottom: padSideUnset,
		CardPaddingLeft:   padSideUnset,

		ShowDCR: true,
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
	if !oneOf(l.TextAlign, TextLeft, TextCenter, TextRight) {
		l.TextAlign = def.TextAlign
	}
	if !oneOf(l.TextLayout, TextPlain, TextRows) {
		l.TextLayout = def.TextLayout
	}
	if !oneOf(l.StoreNav, NavOwn, NavLinks, NavIcons) {
		l.StoreNav = def.StoreNav
	}
	if l.NavGap < 0 {
		l.NavGap = navGapTheirs
	} else {
		l.NavGap = clampLength(l.NavGap, 0)
	}
	if l.NavIconSize < 0 {
		l.NavIconSize = navGapTheirs
	} else {
		l.NavIconSize = clampLength(l.NavIconSize, 0)
	}
	l.NavInset = clampLength(l.NavInset, def.NavInset)
	l.TextColor = safeSetting(l.TextColor, def.TextColor)
	l.CardBorderColor = safeSetting(l.CardBorderColor, def.CardBorderColor)
	l.ButtonLabel = safeSetting(l.ButtonLabel, def.ButtonLabel)
	l.SoldOutLabel = safeSetting(l.SoldOutLabel, def.SoldOutLabel)
	// Not through safeSetting: empty is a real answer for both of these --
	// the theme's own colour -- and safeSetting exists to replace an empty
	// setting with its default.
	l.SoldOutColor = strings.TrimSpace(l.SoldOutColor)
	l.LowStockColor = strings.TrimSpace(l.LowStockColor)
	if l.LowStockAt < 0 {
		l.LowStockAt = 0
	} else if l.LowStockAt > 99 {
		l.LowStockAt = 99
	}

	// The button's colour is the one setting allowed to be empty, which
	// means "whatever the app's own button is". So it is only corrected
	// when it holds something that cannot be passed on.
	if l.ButtonColor != "" {
		l.ButtonColor = safeSetting(l.ButtonColor, "")
	}
	l.ButtonRadius = clampLength(l.ButtonRadius, def.ButtonRadius)
	l.ButtonPadding = clampLength(l.ButtonPadding, def.ButtonPadding)
	l.RowGap = clampLength(l.RowGap, def.RowGap)
	l.MetaGap = clampLength(l.MetaGap, def.MetaGap)
	// Anything below nought is "the reader's own", which is one answer
	// however it is written.
	if l.GridGap < 0 {
		l.GridGap = gridGapTheirs
	} else {
		l.GridGap = clampLength(l.GridGap, 0)
	}
	l.GridMargin = clampLength(l.GridMargin, def.GridMargin)

	l.CardBorderWidth = clampLength(l.CardBorderWidth, def.CardBorderWidth)
	l.CardBorderRadius = clampLength(l.CardBorderRadius, def.CardBorderRadius)
	l.CardPadding = clampLength(l.CardPadding, def.CardPadding)
	l.CardPaddingTop = clampSide(l.CardPaddingTop)
	l.CardPaddingRight = clampSide(l.CardPaddingRight)
	l.CardPaddingBottom = clampSide(l.CardPaddingBottom)
	l.CardPaddingLeft = clampSide(l.CardPaddingLeft)
	l.CardMargin = clampLength(l.CardMargin, def.CardMargin)

	l.ImageCornerTopLeft = clampLength(l.ImageCornerTopLeft, 0)
	l.ImageCornerTopRight = clampLength(l.ImageCornerTopRight, 0)
	l.ImageCornerBottomRight = clampLength(l.ImageCornerBottomRight, 0)
	l.ImageCornerBottomLeft = clampLength(l.ImageCornerBottomLeft, 0)
	l.TextPadding = clampLength(l.TextPadding, def.TextPadding)
	l.TextPaddingTop = clampSide(l.TextPaddingTop)
	l.TextPaddingRight = clampSide(l.TextPaddingRight)
	l.TextPaddingBottom = clampSide(l.TextPaddingBottom)
	l.TextPaddingLeft = clampSide(l.TextPaddingLeft)
	l.TextMargin = clampLength(l.TextMargin, 0)
	l.TextRadius = clampLength(l.TextRadius, def.TextRadius)
	return l
}

// safeSetting is a written setting that can be passed on as it is, or the
// default in place of one that cannot.
//
// A card is written as markup whose settings are separated by commas and
// closed by a bracket, so a value holding either ends the setting early and
// takes the rest of the card's markup with it. Nothing here is a security
// boundary -- these are the seller's own settings, written by the seller's
// own UI -- it is that a shop front should not be breakable by typing a
// comma into a colour box.
func safeSetting(value, fallback string) string {
	value = strings.TrimSpace(value)
	if value == "" || strings.ContainsAny(value, ",[]=\n\r") {
		return fallback
	}
	return value
}

func oneOf(value string, allowed ...string) bool {
	for _, a := range allowed {
		if value == a {
			return true
		}
	}
	return false
}

// padSideUnset is the per-side padding meaning "whatever the plate's own
// padding is".
const padSideUnset = -1

// clampSide keeps a per-side length to something drawable, or leaves it
// unset. Anything below nought is one answer however it is written.
func clampSide(value int) int {
	if value < 0 {
		return padSideUnset
	}
	return clampLength(value, padSideUnset)
}

// sidedLength is a length written as one number when every side agrees and
// as four -- top, right, bottom, left -- when they do not.
//
// One number where one number will do, so that a shop which has never opened
// the per-side controls renders the markup it always did, and its settings
// file keeps the one line it had.
func sidedLength(base, top, right, bottom, left int) string {
	side := func(v int) int {
		if v < 0 {
			return base
		}
		return v
	}
	t, r := side(top), side(right)
	b, l := side(bottom), side(left)

	if t == r && t == b && t == l {
		return fmt.Sprintf("%d", t)
	}
	return fmt.Sprintf("%d %d %d %d", t, r, b, l)
}

// platePadding is the room inside the plate.
func platePadding(l IndexLayout) string {
	return sidedLength(l.TextPadding, l.TextPaddingTop, l.TextPaddingRight,
		l.TextPaddingBottom, l.TextPaddingLeft)
}

// cardPadding is the room between the card's border and what is inside it.
func cardPadding(l IndexLayout) string {
	return sidedLength(l.CardPadding, l.CardPaddingTop, l.CardPaddingRight,
		l.CardPaddingBottom, l.CardPaddingLeft)
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

// storePage is what room the shop front keeps around itself.
//
// The room round a shop front is not the room round a page of writing. A page
// keeps a margin so its text does not run into the edge of the window; a grid
// of cards is already a set of boxes with room of their own, and on a phone
// that margin is the difference between three cards across and two. So the
// sides are the seller's, and the top and bottom keep what a page keeps.
func (s *Store) storePage() string {
	return fmt.Sprintf("--page--\nmargin: %d %d\n--/page--",
		defaultPageEdge, s.IndexLayout().GridMargin)
}

// navGapTheirs is the gap setting meaning "whatever the bar keeps between
// the site's own links", which is what a shop that has not asked gets.
const navGapTheirs = -1

// gridGapTheirs is the gap setting meaning "whatever the reader's own guide
// keeps", which is what a shop that has not asked gets.
const gridGapTheirs = -1

// storeGrid opens the grid the products are laid out in.
//
// A bare grid unless the seller has asked for a gap of their own, so that a
// shop nobody has touched is laid out the way its reader lays out a gallery
// -- and so the markup is the markup this wrote before the gap was a
// setting at all.
func (s *Store) storeGrid() string {
	gap := s.IndexLayout().GridGap
	if gap < 0 {
		return "--grid[3]--"
	}
	return fmt.Sprintf("--grid[3, gap=%d]--", gap)
}

// defaultPageEdge is the room above and below a page, which the shop front
// leaves alone: it is the app's own, and a shop front pressed against the
// bar of links above it is not what anybody asked for.
const defaultPageEdge = 16

// productCard is one product as it appears on the shop front.
//
// Markup rather than a widget, because the shop front is a page: it is
// rendered by whoever is reading it, in their own theme, and the only thing
// that crosses the wire is what is written here. The blocks it uses -- a
// panel with a picture in it, a cell marker, a link drawn as a button -- are
// the page markup any page of a site may use, so nothing here is special to a
// store except the decision about which of them to write.
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

	writing := s.cardWriting(layout, p, link)
	picture := s.cardPicture(layout, image, link)

	var card string
	switch layout.ImagePosition {
	case ImageBottom:
		card = cardStack(layout, writing+picture)
	case ImageFull:
		// One panel: the picture is the card, and the writing sits on it
		// wherever the seller asked for.
		//
		card = fmt.Sprintf("--panel[image=%s%s%s, link=%s, align=%s, justify=%s, padding=%s]--\n%s--/panel--\n",
			image, prefixed(s.cardShape(layout)),
			prefixed(cardCorners(layout)), link, layout.TextPosition,
			s.cardJustify(layout), plateRoom(layout), writing)
	default:
		card = cardStack(layout, picture+writing)
	}

	return s.cardFrame(layout, s.cardRibbon(layout, p, card))
}

// cardRibbon is the word pinned to a card whose product cannot be bought.
//
// Wrapped round the card rather than written into it: it is a fact about the
// whole card and not a line inside it, it has to sit over a picture as well
// as over a background, and it must not push anything else about the card
// around -- a shop front where the sold-out card is a different height from
// the ones beside it is a shop front that looks broken rather than one that
// looks out of stock.
func (s *Store) cardRibbon(layout IndexLayout, p *Product, card string) string {
	label, ink := s.ribbonFor(layout, p)
	if label == "" {
		return card
	}
	if ink == "" {
		return fmt.Sprintf("--panel[badge=%s]--\n%s--/panel--\n",
			oneLine(label), card)
	}
	return fmt.Sprintf("--panel[badge=%s, badgeink=%s]--\n%s--/panel--\n",
		oneLine(label), ink, card)
}

// ribbonFor is what a card's ribbon says and what it is drawn in, or empty
// for a card that does not carry one.
//
// Unavailable wins. A shop with one of something left that it cannot take
// payment for should say so rather than urging somebody towards it -- "1
// left" on a thing nobody can buy is the worst sentence on the page.
func (s *Store) ribbonFor(layout IndexLayout, p *Product) (string, string) {
	if s.Unavailable(p) {
		return layout.SoldOutLabel, layout.SoldOutColor
	}
	if layout.LowStockAt > 0 && p.Counted() && p.Left() > 0 &&
		p.Left() <= layout.LowStockAt {
		return stockLeft(p), layout.LowStockColor
	}
	return "", ""
}

// cardStack is the picture and the writing held together, with the room
// between them set.
//
// The one piece of spacing neither of them can state. A margin of nought on
// both still leaves the renderer's own spacing between two blocks, so a plate
// told to sit flush against the picture sat a fixed gap away from it however
// firmly it was asked not to -- the setting saved, and both answers drew the
// same card.
//
// Written only when the seller has asked for something. A shop that has
// touched neither setting renders what it always did, down to the markup.
func cardStack(layout IndexLayout, body string) string {
	if !layout.TextFlush && layout.TextMargin == 0 {
		return body
	}
	gap := layout.TextMargin
	if layout.TextFlush {
		gap = 0
	}
	return fmt.Sprintf("--panel[gap=%d]--\n%s--/panel--\n", gap, body)
}

// cardFrame is the line drawn round a whole card, and the room inside and
// outside it.
//
// Nothing at all when the seller has not asked for one, rather than a panel
// with every setting at nought: an empty panel is still a block, and a shop
// front that never asked for borders should render exactly the markup it
// rendered before borders existed.
func (s *Store) cardFrame(layout IndexLayout, card string) string {
	if !layout.CardBorder {
		return card
	}
	return fmt.Sprintf("--panel[border=%d, color=%s, radius=%d, padding=%s, margin=%d]--\n%s--/panel--\n",
		layout.CardBorderWidth, layout.CardBorderColor,
		layout.CardBorderRadius, cardPadding(layout), layout.CardMargin, card)
}

// cardWriting is what a card says: the title and the price, or the three
// rows -- title, description, and the price beside a button.
func (s *Store) cardWriting(layout IndexLayout, p *Product, link string) string {
	var text strings.Builder
	fmt.Fprintf(&text, "**[%s](%s)**\n", oneLine(p.Title), link)

	price := Money(p.Price)
	if layout.ShowDCR {
		if approx := s.approxDCR(p.Price); approx != "" {
			price += " · ≈ " + approx
		}
	}

	var writing string
	if layout.TextLayout == TextRows {
		// One block rather than three, and that is the whole reason the
		// block exists. A title, a paragraph and a row of two written as
		// ordinary blocks carry three blocks' worth of the reader's own
		// paragraph spacing, wrap the description to whatever the card's
		// width allows, and stack that last row when the card is narrow --
		// each of which is right for a page and wrong for a card.
		//
		// The description is the seller's own writing, and the product's own
		// page shows all of it. Here it is one line: a card as tall as
		// however much somebody wrote is a row of cards nothing can be
		// compared in.
		writing = fmt.Sprintf("--listing--\ntitle: %s\nlink: %s\n",
			oneLine(p.Title), link)
		if summary := cardSummary(p.Description); summary != "" {
			writing += "summary: " + summary + "\n"
		}
		if layout.TitleOneLine {
			writing += "titlelines: 1\n"
		}
		writing += fmt.Sprintf("meta: %s\nbutton: %s\nstyle: primary\n"+
			"align: %s\ngap: %d\nmetagap: %d\nradius: %d\npadding: %d\n",
			price, oneLine(layout.ButtonLabel), layout.TextAlign,
			layout.RowGap, layout.MetaGap, layout.ButtonRadius,
			layout.ButtonPadding)
		if layout.ButtonColor != "" {
			writing += "color: " + layout.ButtonColor + "\n"
		}
		writing += "--/listing--\n"
	} else {
		text.WriteString(price + "\n")
		writing = text.String()
	}

	if !layout.TextBackground {
		// No plate, and still a side to sit on: which side the writing sits
		// on is a fact about the writing rather than about its background,
		// so a card with no plate is aligned by a panel that does nothing
		// else. The three-row block places its own writing and needs
		// neither.
		if layout.TextAlign == TextLeft || layout.TextLayout == TextRows {
			return writing
		}
		return fmt.Sprintf("--panel[text=%s, justify=%s]--\n%s--/panel--\n",
			layout.TextAlign, s.cardJustify(layout), writing)
	}

	// The plate keeps no margin of its own. The room between it and the
	// picture belongs to whatever holds both of them -- the panel with the
	// picture behind it, or the stack -- and room at the plate's sides is
	// not the plate standing off anything, it is the plate not being the
	// width it was told to be. Writing it here as well was what made "run it
	// the full width" come out a few pixels short at each end, which reads
	// as the setting not working.
	margin := "0"
	plate := fmt.Sprintf("--panel[fill=%s, padding=%s, margin=%s, radius=%d, text=%s]--\n%s--/panel--\n",
		layout.TextColor, platePadding(layout), margin, layout.TextRadius,
		layout.TextAlign, writing)

	// A plate that is not the full width has to be told what to be instead,
	// and where to sit. On a card whose picture fills it, the panel holding
	// the picture does that; on one where the picture is above or below, the
	// plate is a block of its own and nothing else is going to.
	if !layout.TextFullWidth && layout.ImagePosition != ImageFull {
		plate = fmt.Sprintf("--panel[justify=%s]--\n%s--/panel--\n",
			layout.TextAlign, plate)
	}
	return plate
}

// oneLine is a piece of the seller's own writing, safe to write as one field
// of a block whose fields are one per line.
//
// A title with a newline in it would end its field, and the line after it --
// if it holds a colon -- would be read as another field entirely.
func oneLine(text string) string {
	return strings.Join(strings.Fields(text), " ")
}

// cardSummary is as much of a product's description as belongs on a card.
//
// The first paragraph, and not much of it. A description is written for the
// product's own page, where there is room for a list of features; a card
// carrying all of that is a card as tall as the page, and a row of them is a
// page nobody can compare anything on.
func cardSummary(description string) string {
	text := strings.TrimSpace(description)
	if text == "" {
		return ""
	}

	// The first paragraph only, and every line of it joined: a bullet list
	// or a hard-wrapped line reaching a card as several lines would be
	// several rows where the layout has one.
	if at := strings.Index(text, "\n\n"); at != -1 {
		text = text[:at]
	}
	text = strings.Join(strings.Fields(text), " ")

	const most = 140
	if len(text) <= most {
		return text
	}
	// Cut at a word rather than through one, and say that it was cut.
	cut := text[:most]
	if at := strings.LastIndex(cut, " "); at > most/2 {
		cut = cut[:at]
	}
	return strings.TrimRight(cut, " ,.;:-") + "…"
}

// cardPicture is the picture on a card that has the writing beside it rather
// than on it.
//
// A panel rather than a plain Markdown image, so that the picture is part of
// the link to the product. Somebody looking at a shop front and tapping the
// picture of the thing they want has said what they want; before this that
// tap did nothing and only the title underneath was a link.
func (s *Store) cardPicture(layout IndexLayout, image, link string) string {
	return fmt.Sprintf("--panel[image=%s%s%s, link=%s]--\n--/panel--\n",
		image, prefixed(s.cardShape(layout)),
		prefixed(cardCorners(layout)), link)
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

// cardCorners is how round the picture's corners are, or nothing at all when
// all four are square -- which is what a picture on a page has always been.
func cardCorners(layout IndexLayout) string {
	if layout.ImageCornerTopLeft == 0 && layout.ImageCornerTopRight == 0 &&
		layout.ImageCornerBottomRight == 0 && layout.ImageCornerBottomLeft == 0 {
		return ""
	}
	return fmt.Sprintf("radius=%d %d %d %d", layout.ImageCornerTopLeft,
		layout.ImageCornerTopRight, layout.ImageCornerBottomRight,
		layout.ImageCornerBottomLeft)
}

// plateRoom is the room between the plate and the edge of the picture it
// sits on, written as the padding of the panel holding the picture: there is
// nowhere else that room can come from once the plate itself is the thing
// being placed.
//
// Nothing at all when the plate sits flush. Top and bottom only when it runs
// the full width -- which is what full width means, and reading it any other
// way is what made the two settings appear to fight. Turning off "sits flush"
// inset the plate on all four sides, so a plate that was the full width of
// the picture stopped touching either end of it, and the width setting looked
// as though it had been turned off along with the flush one.
func plateRoom(layout IndexLayout) string {
	if layout.TextFlush {
		return "0"
	}
	if layout.TextFullWidth {
		return fmt.Sprintf("%d 0", layout.TextMargin)
	}
	return fmt.Sprintf("%d", layout.TextMargin)
}

// cardJustify is how wide the plate is drawn: the width of the card, or the
// width of the writing on it and to one side.
func (s *Store) cardJustify(layout IndexLayout) string {
	if layout.TextFullWidth {
		return "stretch"
	}
	return layout.TextAlign
}

// prefixed is a settings fragment ready to follow another one, or the empty
// string unchanged.
//
// The markup is a comma-separated list, and a list with a stray comma in it
// -- or two commas together -- is a setting nobody wrote.
func prefixed(setting string) string {
	if setting == "" {
		return ""
	}
	return ", " + setting
}
