package thesaurus

import "testing"

// morphy_test.go covers the reduction from a word as typed to the form the
// data is keyed by. It is the difference between a lookup answering for 86%
// of the dictionary and answering for 36%, so the cases below are the ones
// that difference is made of.

// wordnet is a stand-in for the real data: only base forms, exactly as
// WordNet and MyThes store them, and sorted, because the index binary-
// searches line offsets rather than reading the file in.
const wordnet = `box|noun:a container with a flat base
bus|noun:a large road vehicle
cat|noun:a small domesticated feline
child|noun:a young human being
foot|noun:the lower extremity of the leg
go|verb:to move from one place to another
good|adj:having desirable qualities
happy|adj:enjoying or showing joy
mouse|noun:a small rodent
payment|noun:the act of paying
run|verb:to move fast on foot
stop|verb:to cease moving
walk|verb:to travel on foot
worry|verb:to feel anxious
`

const irregular = `better|good,well
children|child
feet|foot
mice|mouse
went|go
`

func lookup(t *testing.T, word string) (Entry, bool) {
	t.Helper()
	return NewIndex("", wordnet, irregular, "").Lookup(word)
}

func TestLookupReducesInflections(t *testing.T) {
	cases := map[string]string{
		// Regular plurals, including the spellings that need their own rule.
		"cats":  "cat",
		"buses": "bus",
		"boxes": "box",
		// -y stems.
		"worries":  "worry",
		"happier":  "happy",
		"happiest": "happy",
		// Participles, including the doubled consonant that is spelling
		// rather than meaning.
		"walking":  "walk",
		"walked":   "walk",
		"running":  "run",
		"stopped":  "stop",
		"stopping": "stop",
		// Irregulars, which no suffix rule reaches. These are the reason the
		// exception list is shipped at all.
		"went":     "go",
		"children": "child",
		"mice":     "mouse",
		"feet":     "foot",
		"better":   "good",
		// Possessives, which are 27,000 of the dictionary's entries.
		"payment's":  "payment",
		"cat's":      "cat",
		"children's": "child",
	}
	for typed, want := range cases {
		entry, ok := lookup(t, typed)
		if !ok {
			t.Errorf("Lookup(%q) found nothing, want the entry for %q", typed, want)
			continue
		}
		if entry.Word != want {
			t.Errorf("Lookup(%q).Word = %q, want %q", typed, entry.Word, want)
		}
	}
}

// The word itself always wins. A rule that fired ahead of a real entry would
// answer for the wrong word while looking as though it had worked.
func TestLookupPrefersTheWordItself(t *testing.T) {
	for _, word := range []string{"cat", "run", "good", "go"} {
		entry, ok := lookup(t, word)
		if !ok || entry.Word != word {
			t.Errorf("Lookup(%q) = %q, %v; want the word itself", word, entry.Word, ok)
		}
	}
}

// A reduction is only accepted if it is actually in the data, so an
// over-eager rule costs nothing.
func TestLookupRejectsGuessesThatMissed(t *testing.T) {
	// "bus" ends in "s" and would reduce to "bu" under the plural rule; the
	// word itself is in the data and wins. "gas" has no entry at all, and
	// neither does "ga", so the guess must not invent one.
	for _, word := range []string{"gas", "sing", "thing", "kencameron"} {
		if entry, ok := lookup(t, word); ok {
			t.Errorf("Lookup(%q) returned %+v, want no match", word, entry)
		}
	}
}

// An index with no exception list still reduces what the suffix rules can
// reach, so an older generated build degrades rather than breaking.
func TestLookupWithoutExceptions(t *testing.T) {
	idx := NewIndex("", wordnet, "", "")
	if entry, ok := idx.Lookup("cats"); !ok || entry.Word != "cat" {
		t.Errorf(`Lookup("cats") = %q, %v; want "cat"`, entry.Word, ok)
	}
	if _, ok := idx.Lookup("went"); ok {
		t.Error(`Lookup("went") found something without the exception list`)
	}
}

// Contractions are two words run together and appear in neither source. The
// commonest are glossed by hand -- reducing "wouldn't" to "would" drops the
// negation -- and the rest fall back to the base word.
func TestLookupHandlesContractions(t *testing.T) {
	const glossed = `can't|verb:short for "cannot"
she|pron:a female person
they|pron:people already mentioned
wouldn't|verb:short for "would not"
`
	idx := NewIndex("", glossed, irregular, "")

	// A hand-written gloss wins outright, and is not reduced away.
	for _, word := range []string{"can't", "wouldn't"} {
		entry, ok := idx.Lookup(word)
		if !ok || entry.Word != word {
			t.Errorf("Lookup(%q) = %q, %v; want the word itself", word, entry.Word, ok)
		}
	}

	// The rest reduce to the base word.
	for typed, want := range map[string]string{
		"she'd":   "she",
		"she'll":  "she",
		"they've": "they",
		"they're": "they",
	} {
		entry, ok := idx.Lookup(typed)
		if !ok || entry.Word != want {
			t.Errorf("Lookup(%q) = %q, %v; want %q", typed, entry.Word, ok, want)
		}
	}
}

// Reported: "I've" was flagged as a misspelling, because macOS substitutes
// U+2019 for a typed apostrophe. The data is keyed with the plain one, so
// every contraction was unfindable as actually typed.
func TestLookupFoldsTypographicApostrophes(t *testing.T) {
	const glossed = `can't|verb:short for "cannot"
they|pron:people already mentioned
`
	idx := NewIndex("", glossed, "", "")

	for _, word := range []string{"can’t", "canʼt", "can‘t"} {
		if entry, ok := idx.Lookup(word); !ok || entry.Word != "can't" {
			t.Errorf("Lookup(%q) = %q, %v; want the entry for can't",
				word, entry.Word, ok)
		}
	}
	if entry, ok := idx.Lookup("they’ve"); !ok || entry.Word != "they" {
		t.Errorf(`Lookup("they’ve") = %q, %v; want "they"`, entry.Word, ok)
	}
}

// The datasets are American, so a British spelling has no entry of its own.
// Under an en-GB dictionary those are exactly the words somebody is most
// likely to select, and returning nothing for "colour" would make the
// thesaurus look broken in the language it was just switched to.
func TestLookupReducesBritishSpellings(t *testing.T) {
	const american = `analyze|verb:to examine in detail
color|noun:the appearance produced by light of different wavelengths
favorite|noun:the one preferred
organize|verb:to arrange into a structure
recognize|verb:to identify from previous knowledge
`
	idx := NewIndex("", american, "", "")

	for typed, want := range map[string]string{
		"colour":    "color",
		"organise":  "organize",
		"recognise": "recognize",
		"analyse":   "analyze",
		// Reduced twice: the inflection first, then the spelling. The
		// table lists base forms only, so the order matters.
		"organised":  "organize",
		"colours":    "color",
		"favourites": "favorite",
	} {
		entry, ok := idx.Lookup(typed)
		if !ok || entry.Word != want {
			t.Errorf("Lookup(%q) = %q, %v; want %q", typed, entry.Word, ok, want)
		}
	}

	// The American spelling still answers directly, and is not routed
	// through the table.
	if entry, ok := idx.Lookup("color"); !ok || entry.Word != "color" {
		t.Errorf(`Lookup("color") = %q, %v`, entry.Word, ok)
	}
}
