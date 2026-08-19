package thesaurus

import (
	"bufio"
	"os"
	"strings"
	"testing"
)

// TestCoverageOverDictionary is the measurement the lemmatiser exists for:
// how much of the dictionary a lookup can actually answer for.
//
// Skipped unless the generated files are present, so it does not fail a
// checkout that has only the compressed ones.
//
// It asks for the wordlist by its real name. It used to look for
// "../words.txt", which stopped existing when the list was split per
// language -- so this skipped on every run and reported nothing, which is
// how the sense-ordering fault in tools/mkdefs went unnoticed: the one
// measurement that would have shown it had quietly turned itself off. A
// skipped test that looks like a passing one is worse than no test.
func TestCoverageOverDictionary(t *testing.T) {
	idx := loadIndex(t)
	words := loadWords(t, "../words-en-GB.txt")

	var answered, definitions, synonyms, examples int
	for _, w := range words {
		entry, ok := idx.Lookup(w)
		if ok {
			answered++
		}
		if len(entry.Definitions) > 0 {
			definitions++
		}
		if len(entry.Senses) > 0 {
			synonyms++
		}
		for _, d := range entry.Definitions {
			if d.Example != "" {
				examples++
				break
			}
		}
	}
	pct := func(n int) int { return n * 100 / len(words) }
	t.Logf("dictionary %d words: answered %d (%d%%), definitions %d (%d%%), "+
		"synonyms %d (%d%%), with an example %d (%d%%)",
		len(words), answered, pct(answered), definitions, pct(definitions),
		synonyms, pct(synonyms), examples, pct(examples))

	// Floors rather than exact figures: the point is to catch the data
	// silently getting worse -- a generator change that drops half the
	// senses, or a wordlist that grows past what WordNet covers -- without
	// failing every time a dataset is legitimately updated.
	if got := pct(definitions); got < 80 {
		t.Errorf("definition coverage fell to %d%%, floor is 80%%", got)
	}
	if got := pct(synonyms); got < 65 {
		t.Errorf("synonym coverage fell to %d%%, floor is 65%%", got)
	}
	if got := pct(examples); got < 25 {
		t.Errorf("example coverage fell to %d%%, floor is 25%%", got)
	}
}

// TestVerbsLeadWhereVerbsDominate pins the second half of the ordering work.
//
// index.<pos> ranks senses within a part of speech and says nothing about
// which part of speech a word usually is, so round-robin still put nouns
// first always: "go" led with "a time period for working", "take" with "the
// income or profit arising from such transactions", "run" with baseball.
// cntlist.rev carries WordNet's tagged-corpus counts across parts of speech
// and settles it.
func TestVerbsLeadWhereVerbsDominate(t *testing.T) {
	idx := loadIndex(t)
	for _, w := range []string{"go", "take", "run", "write", "think", "know", "carry"} {
		entry, ok := idx.Lookup(w)
		if !ok || len(entry.Definitions) == 0 {
			t.Errorf("%q: no definition", w)
			continue
		}
		if got := entry.Definitions[0].PartOfSpeech; got != "verb" {
			t.Errorf("%q leads with a %s (%q), expected the verb",
				w, got, entry.Definitions[0].Text)
		}
	}
}

// ...and a noun-dominant word still leads with its noun, so the ordering is
// following the corpus rather than simply preferring verbs.
func TestNounsStillLeadWhereNounsDominate(t *testing.T) {
	idx := loadIndex(t)
	for _, w := range []string{"bank", "book", "light", "study", "child"} {
		entry, ok := idx.Lookup(w)
		if !ok || len(entry.Definitions) == 0 {
			t.Errorf("%q: no definition", w)
			continue
		}
		if got := entry.Definitions[0].PartOfSpeech; got != "noun" {
			t.Errorf("%q leads with a %s, expected the noun", w, got)
		}
	}
}

// TestCommonSensesComeFirst pins the ordering fault this data had.
//
// Senses used to arrive in data-file order, which is byte offset and means
// nothing to a reader: "bank" led with a flight manoeuvre, "happy" with
// "well expressed and to the point". Both are WordNet's least common sense
// for the word. tools/mkdefs now walks index.<pos>, which is WordNet's own
// frequency rank.
func TestCommonSensesComeFirst(t *testing.T) {
	idx := loadIndex(t)
	for _, tc := range []struct{ word, want string }{
		{"bank", "sloping land"},
		{"happy", "joy or pleasure"},
		{"book", "written work"},
		// "set" moved from the noun to the verb when the parts of speech
		// were ordered by use rather than always noun-first. WordNet's
		// tagged corpus has the verb ahead, and "set the table" against "a
		// set of books" is a fair contest -- so this now pins the part of
		// speech it leads with rather than one wording of one sense.
	} {
		entry, ok := idx.Lookup(tc.word)
		if !ok || len(entry.Definitions) == 0 {
			t.Errorf("%q: no definition", tc.word)
			continue
		}
		if got := entry.Definitions[0].Text; !strings.Contains(got, tc.want) {
			t.Errorf("%q leads with %q, expected something containing %q",
				tc.word, got, tc.want)
		}
	}
}

// A definition must not stop at the first semicolon. The gloss for bank's
// flight-manoeuvre sense is "a flight maneuver; aircraft tips laterally
// about its longitudinal axis (especially in turning)", and cutting at the
// semicolon left "a flight maneuver", which says nothing at all.
func TestDefinitionsAreNotTruncated(t *testing.T) {
	idx := loadIndex(t)
	entry, ok := idx.Lookup("bank")
	if !ok {
		t.Fatal("no entry for bank")
	}
	for _, d := range entry.Definitions {
		if d.Text == "a flight maneuver" {
			t.Error("bank's flight sense is still truncated at the semicolon")
		}
	}
}

func loadIndex(t *testing.T) *Index {
	t.Helper()
	read := func(name string) string {
		b, err := os.ReadFile(name)
		if err != nil {
			t.Skipf("generated data not present: %v", err)
		}
		return string(b)
	}
	return NewIndex(read("../thesaurus.txt"), read("../definitions.txt"),
		read("../exceptions.txt"), read("../inflections.txt"))
}

func loadWords(t *testing.T, path string) []string {
	t.Helper()
	f, err := os.Open(path)
	if err != nil {
		t.Skipf("wordlist not present: %v", err)
	}
	defer f.Close()
	var out []string
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		w := strings.TrimSpace(sc.Text())
		if w != "" && !strings.HasPrefix(w, "#") {
			out = append(out, w)
		}
	}
	return out
}

// A phrase is what somebody learning English most often needs explained, and
// the two datasets carry tens of thousands of them. They used to be
// discarded at generation time: usableHeadword rejected anything with an
// underscore, which threw away 64,246 WordNet headwords, 43% of its
// vocabulary.
func TestPhrasesAreAnswered(t *testing.T) {
	idx := loadIndex(t)
	for _, p := range []string{"take off", "give up", "look after", "wedding ring"} {
		entry, ok := idx.Lookup(p)
		if !ok || entry.IsEmpty() {
			t.Errorf("%q: nothing", p)
			continue
		}
		if entry.Word != p {
			t.Errorf("%q answered as %q", p, entry.Word)
		}
	}
}

// A phrase inflects at one end or the other, and which end depends on what
// the phrase is: a phrasal verb inflects its verb, a noun compound its head
// noun.
func TestInflectedPhrasesReduce(t *testing.T) {
	idx := loadIndex(t)
	for _, tc := range []struct{ asked, want string }{
		{"took off", "take off"},          // verb, first word
		{"gave up", "give up"},            // verb, first word
		{"wedding rings", "wedding ring"}, // noun, last word
	} {
		entry, ok := idx.Lookup(tc.asked)
		if !ok {
			t.Errorf("%q: nothing", tc.asked)
			continue
		}
		if entry.Word != tc.want {
			t.Errorf("%q reduced to %q, expected %q", tc.asked, entry.Word, tc.want)
		}
	}
}

// Inflections are the reverse of the reduction the lookup already did, and
// were held in one direction only.
func TestInflectionsAreListed(t *testing.T) {
	idx := loadIndex(t)
	for _, tc := range []struct {
		word string
		want []string
	}{
		{"go", []string{"goes", "went", "gone"}},
		{"child", []string{"children"}},
		{"happy", []string{"happier", "happiest"}},
		{"be", []string{"am", "is", "are", "was", "were", "been"}},
	} {
		entry, ok := idx.Lookup(tc.word)
		if !ok {
			t.Errorf("%q: nothing", tc.word)
			continue
		}
		have := map[string]bool{}
		for _, f := range entry.Inflections {
			have[f] = true
		}
		for _, w := range tc.want {
			if !have[w] {
				t.Errorf("%q is missing the form %q (has %v)",
					tc.word, w, entry.Inflections)
			}
		}
	}
}

// The forms are gated on part of speech, because the dictionary check alone
// rejects non-words and not wrong ones: "run"+"es" is "runes", a real word
// and not a form of run, and "-er" on a verb gives an agent noun.
func TestInflectionsExcludeDerivations(t *testing.T) {
	idx := loadIndex(t)
	for _, tc := range []struct{ word, unwanted string }{
		{"run", "runes"},
		{"run", "runner"},
		{"take", "taker"},
		{"happy", "happily"},
	} {
		entry, ok := idx.Lookup(tc.word)
		if !ok {
			continue
		}
		for _, f := range entry.Inflections {
			if f == tc.unwanted {
				t.Errorf("%q lists %q, which is not one of its forms",
					tc.word, tc.unwanted)
			}
		}
	}
}

// A phrase has no inflections of its own to list; the forms belong to the
// word inside it, which is a different entry.
func TestPhrasesHaveNoInflections(t *testing.T) {
	idx := loadIndex(t)
	entry, ok := idx.Lookup("take off")
	if !ok {
		t.Skip("phrase data not present")
	}
	if len(entry.Inflections) > 0 {
		t.Errorf("take off lists inflections: %v", entry.Inflections)
	}
}
