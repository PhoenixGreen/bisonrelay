package thesaurus

import (
	"strings"

	"github.com/companyzero/bisonrelay/plugins/writingtools/spellcheck"
)

// morphy.go reduces a word as typed to the form the datasets are keyed by.
//
// This is the difference between a thesaurus that answers and one that mostly
// does not. WordNet and MyThes both store base forms only -- "cat" and not
// "cats", "run" and not "running", "happy" and not "happier" -- so of the
// 121,000 words the dictionary knows, only 77,000 have an entry to look up
// directly. The other 44,000 are almost all inflections of a word that is
// there, plus 27,000 possessives, and reducing them is the whole job.
//
// The rules are WordNet's own (its "Morphy" component): a table of suffix
// detachments per part of speech, plus an exception list for the forms no
// rule reaches -- went/go, children/child, better/good. The exception list
// ships with WordNet and is generated into exceptions.txt by tools/mkdefs.
//
// Every candidate is checked against the data before it is accepted, so a
// wrong guess costs nothing: "sing" does not become "s" because "s" has no
// entry, and "axes" is tried as both "axe" and "ax".

// detachment is one suffix rule: strip Suffix, append Replace.
type detachment struct{ suffix, replace string }

// Ordered longest-suffix-first within each group so "buses" is tried as
// "bus" before "buse", and "flies" as "fly" before "flie".
var (
	nounRules = []detachment{
		{"ches", "ch"}, {"shes", "sh"}, {"sses", "ss"},
		{"ses", "s"}, {"xes", "x"}, {"zes", "z"},
		{"men", "man"}, {"ies", "y"}, {"es", "e"}, {"es", ""}, {"s", ""},
	}
	verbRules = []detachment{
		{"ies", "y"}, {"ing", "e"}, {"ing", ""},
		{"es", "e"}, {"es", ""}, {"ed", "e"}, {"ed", ""}, {"s", ""},
	}
	adjRules = []detachment{
		{"iest", "y"}, {"ier", "y"},
		{"est", "e"}, {"est", ""}, {"er", "e"}, {"er", ""},
	}
	// Adverbs have no inflections in English; the -ly rule is here because
	// people look up "quickly" and want "quick", which WordNet holds as the
	// adjective. Offered last, so a real adverb entry always wins.
	advRules = []detachment{{"ly", ""}}

	// A contraction is two words run together, and neither WordNet nor
	// MyThes holds one. The commonest are glossed by hand in
	// data/function-words.txt, because reducing "wouldn't" to "would" drops
	// the negation that is the whole reason the word is there. These rules
	// are for the rest, where the base word is a fair answer: "she'd" to
	// "she", "they've" to "they".
	//
	// Tried last of all, so a hand-written gloss always wins.
	contractionRules = []detachment{
		{"n't", ""}, {"'ve", ""}, {"'re", ""},
		{"'ll", ""}, {"'d", ""}, {"'m", ""},
	}
)

// irregularContractions are the ones the suffix rules mangle: stripping
// "n't" from "can't" leaves "ca". Kept here rather than in the generated
// exception list, which is WordNet's and should stay as WordNet wrote it.
var irregularContractions = map[string]string{
	"can't":  "can",
	"won't":  "will",
	"shan't": "shall",
	"ain't":  "be",
}

// candidates returns the forms [word] might reduce to, best first.
//
// Order matters and is not arbitrary: the word itself first, so a real entry
// is never passed over for a guess; then the exception list, which is
// authoritative where it applies; then the suffix rules, whose earlier
// entries are the more specific ones.
//
// This yields possibilities, not answers. The caller tries each against the
// data and takes the first that exists, which is what makes an over-eager
// rule harmless.
//
// A typographic apostrophe is folded to a plain one first: a text field that
// substitutes U+2019 as you type would otherwise make every contraction
// unfindable, since the data is keyed with the plain form.
func (idx *Index) candidates(word string) []string {
	word = foldApostrophes(word)

	// A phrase is reduced at its ends, because that is where English puts
	// the inflection and which end depends on what the phrase is.
	//
	// A phrasal verb inflects its verb and leaves the particle alone: "took
	// off" is "take off". A noun compound inflects its head noun, which is
	// the last word: "wedding rings" is "wedding ring". Trying both covers
	// the two shapes that actually occur, and costs a handful of candidates
	// rather than the product of every word's forms -- which for three
	// words would be dozens of mostly nonsense phrases to search for.
	if strings.IndexByte(word, ' ') >= 0 {
		out := []string{word}
		seen := map[string]bool{word: true}
		addPhrase := func(p string) {
			if !seen[p] {
				seen[p] = true
				out = append(out, p)
			}
		}
		if i := strings.IndexByte(word, ' '); i >= 0 {
			head, rest := word[:i], word[i:]
			for _, form := range idx.candidates(head) {
				addPhrase(form + rest)
			}
		}
		if i := strings.LastIndexByte(word, ' '); i >= 0 {
			rest, tail := word[:i+1], word[i+1:]
			for _, form := range idx.candidates(tail) {
				addPhrase(rest + form)
			}
		}
		return out
	}

	seen := map[string]bool{word: true}
	out := []string{word}
	add := func(w string) {
		// Two characters is the shortest English word, and a rule that
		// produces something shorter has eaten the word rather than reduced
		// it.
		if len(w) < 2 || seen[w] {
			return
		}
		seen[w] = true
		out = append(out, w)
	}

	// A possessive is not an inflection of the word, it is the word plus a
	// clitic -- and 27,000 of the dictionary's entries are one. Stripped
	// first, and what remains goes through everything else, so "children's"
	// reaches "child".
	base := word
	if strings.HasSuffix(base, "'s") || strings.HasSuffix(base, "’s") {
		base = base[:len(base)-2]
		if strings.HasSuffix(word, "’s") {
			base = strings.TrimSuffix(word, "’s")
		}
		add(base)
	}

	for _, form := range idx.exceptionsFor(base) {
		add(form)
	}

	if contraction, ok := irregularContractions[base]; ok {
		add(contraction)
	}

	for _, rules := range [][]detachment{
		nounRules, verbRules, adjRules, advRules, contractionRules,
	} {
		for _, r := range rules {
			if !strings.HasSuffix(base, r.suffix) {
				continue
			}
			stem := base[:len(base)-len(r.suffix)]
			if stem == "" {
				continue
			}
			add(stem + r.replace)
			// A doubled final consonant before -ing/-ed is spelling, not
			// meaning: "running" is "run", "stopped" is "stop". Only after
			// the plain form, which is right for "billing" and "falling".
			if r.replace == "" && len(stem) > 2 &&
				stem[len(stem)-1] == stem[len(stem)-2] &&
				!isVowel(stem[len(stem)-1]) {
				add(stem[:len(stem)-1])
			}
		}
	}

	// WordNet and MyThes are both American, so a British spelling has no
	// entry of its own: "colour" and "recognise" would come back with
	// nothing at all under an en-GB dictionary, which is exactly when
	// somebody is most likely to select them.
	//
	// Applied last, to every form found so far rather than only to the word
	// as typed. The two reductions compose in either order and the table
	// only lists base forms, so "colours" has to lose its "s" before the
	// table recognises it -- and "organised" has to lose its "d" before
	// "organise" can become "organize".
	for _, form := range append([]string(nil), out...) {
		if american, ok := americanSpelling[form]; ok {
			add(american)
		}
	}
	return out
}

func isVowel(c byte) bool {
	switch c {
	case 'a', 'e', 'i', 'o', 'u':
		return true
	}
	return false
}

// exceptionsFor returns the base forms WordNet records for an irregular
// word, or nothing.
//
// Read from the same sorted-line index the datasets use, so the exception
// list costs one offset per entry rather than a resident map of six thousand
// strings inside the wasm instance.
func (idx *Index) exceptionsFor(word string) []string {
	line, ok := idx.exceptions.find(word)
	if !ok {
		return nil
	}
	_, rest, found := strings.Cut(line, "|")
	if !found {
		return nil
	}
	return strings.Split(rest, ",")
}

// foldApostrophes replaces the apostrophes a text field may substitute with
// the plain one the data is keyed by. All of them are a single rune, so this
// cannot change what the word is -- only how it is spelled.
func foldApostrophes(word string) string {
	if !strings.ContainsAny(word, "\u2019\u02bc\u2018") {
		return word
	}
	return strings.NewReplacer(
		"\u2019", "'", "\u02bc", "'", "\u2018", "'",
	).Replace(word)
}

// americanSpelling maps a British spelling to the American one the datasets
// are written in. Derived from the same pair list the spelling-consistency
// check uses, so the two cannot disagree about what counts as a pair.
var americanSpelling = buildAmericanSpelling()

func buildAmericanSpelling() map[string]string {
	out := make(map[string]string, len(spellcheck.VariantPairs))
	for _, pair := range spellcheck.VariantPairs {
		if british, american, ok := spellcheck.SplitVariant(pair); ok {
			out[british] = american
		}
	}
	return out
}
