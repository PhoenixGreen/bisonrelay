// Command mkdefs condenses WordNet's sense data into the definitions the
// plugin ships.
//
// WordNet stores a synset per line of data.<pos>: an offset, some
// bookkeeping, the words that share the sense, the pointers to related
// senses, and finally, after a "|", the gloss. Almost all of the 21MB is
// discarded here; what is kept is the words, the definition and one example.
//
// Senses are ordered by index.<pos>, NOT by the order they appear in
// data.<pos>. That distinction is the whole reason index.* is shipped. A
// data file is ordered by byte offset, which is meaningless to a reader, and
// taking the first few senses from it gave "bank" as a flight manoeuvre,
// "run" as a score in baseball and "happy" as "well expressed and to the
// point" -- each of them WordNet's *least* common sense for the word,
// selected purely because it sat earliest in the file. index.* lists a
// lemma's synsets in WordNet's own frequency rank, most used first, which is
// the order somebody looking a word up expects.
//
// Definitions are kept separate from the synonyms in thesaurus.txt rather
// than merged into them, because the two sources do not divide a word into
// the same senses: MyThes has its own grouping, and lining WordNet's up with
// it would mean guessing which of its senses matched which of theirs. Listing
// them separately is honest about that.
//
// data/function-words.txt is merged in on top. WordNet holds only nouns,
// verbs, adjectives and adverbs, so it has nothing at all for "the", "of" or
// "although" -- and those are the words a reader is likeliest to select. It
// also carries the vocabulary WordNet 3.1 is simply too old to have: a
// wordlist from SCOWL knows "blockchain" and "smartphone" as spellings, and
// a lexical database published in 2011 has nothing to say about either.
//
// Run from the repo root:
//
//	go run ./tools/mkdefs > definitions.txt
//
// Output is one line per word, sorted:
//
//	word|pos:definition~example|pos:definition
package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

const (
	wordnetDir       = "data/wordnet"
	functionWordFile = "data/function-words.txt"
	// cntlistFile holds how often each sense was actually used in WordNet's
	// tagged corpus. index.<pos> ranks senses *within* a part of speech and
	// says nothing about which part of speech a word usually is; this does.
	cntlistFile = "cntlist.rev"
)

// maxDefinitions caps how many senses a word keeps. WordNet gives "run" over
// fifty; the first few carry the meanings anyone is looking up, and a menu
// showing them has to stay readable.
//
// It matters far less now than it did. While the senses were in file order
// this cap was what threw away the useful ones; in rank order the first three
// are the three a reader wants.
const maxDefinitions = 3

// posFiles pairs each part of speech with its data and index files. WordNet's
// own codes are single letters; these are the labels shown to a reader.
var posFiles = []struct {
	pos   string
	data  string
	index string
}{
	{"noun", "data.noun", "index.noun"},
	{"verb", "data.verb", "index.verb"},
	{"adj", "data.adj", "index.adj"},
	{"adv", "data.adv", "index.adv"},
}

type definition struct {
	pos     string
	text    string
	example string
}

// pick chooses which of a word's senses to keep: the best one from each part
// of speech first, then the next best, and so on until the cap is reached.
//
// Round-robin rather than straight down the ranking, because WordNet ranks
// within a part of speech and not across them. Taken in file order, nouns
// filled the cap before a verb was ever reached -- so "run" was three kinds
// of baseball score and never "move fast on foot", which is what anybody
// selecting the word meant. One of each first is also how a dictionary is
// laid out, and for a word that is only ever one part of speech it changes
// nothing.
//
// [order] is the parts of speech most-used first, from cntlist.rev. Without
// it round-robin still put nouns first always, which is right for "bank" and
// "set" and wrong for "go", "take" and "run" -- words that are overwhelmingly
// verbs and led with a noun sense nobody wanted. A word the corpus never
// tagged keeps the declared order, which is the old behaviour for the 100,000
// headwords too rare to have been tagged at all.
func pick(senses map[string][]definition, order []string) []definition {
	var out []definition
	for round := 0; len(out) < maxDefinitions; round++ {
		var added bool
		for _, pos := range order {
			list := senses[pos]
			if round >= len(list) {
				continue
			}
			out = append(out, list[round])
			added = true
			if len(out) >= maxDefinitions {
				break
			}
		}
		if !added {
			break
		}
	}
	return out
}

// posOrder is the parts of speech for one word, most-used first.
//
// Ties and absences keep the declared order, so this only ever moves a part
// of speech that the corpus positively says is the more used one.
func posOrder(counts map[string]int) []string {
	order := make([]string, 0, len(posFiles))
	for _, pf := range posFiles {
		order = append(order, pf.pos)
	}
	if len(counts) == 0 {
		return order
	}
	sort.SliceStable(order, func(i, j int) bool {
		return counts[order[i]] > counts[order[j]]
	})
	return order
}

// readCounts totals how often each part of speech of each word was used.
//
// cntlist.rev is one line per sense: "go%2:38:00:: 1 25" -- the lemma, a
// "%", the part-of-speech digit, and after the sense number the count. The
// digits are WordNet's: 1 noun, 2 verb, 3 adjective, 4 adverb, 5 adjective
// satellite, which is an adjective for this purpose.
func readCounts(path string) map[string]map[string]int {
	f, err := os.Open(path)
	if err != nil {
		fmt.Fprintln(os.Stderr, "mkdefs:", err)
		os.Exit(1)
	}
	defer f.Close()

	out := map[string]map[string]int{}
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		fields := strings.Fields(sc.Text())
		if len(fields) < 3 {
			continue
		}
		lemma, rest, ok := strings.Cut(fields[0], "%")
		if !ok || rest == "" {
			continue
		}
		var pos string
		switch rest[0] {
		case '1':
			pos = "noun"
		case '2':
			pos = "verb"
		case '3', '5':
			pos = "adj"
		case '4':
			pos = "adv"
		default:
			continue
		}
		n, err := strconv.Atoi(fields[2])
		if err != nil {
			continue
		}
		lemma = strings.ToLower(lemma)
		if out[lemma] == nil {
			out[lemma] = map[string]int{}
		}
		out[lemma][pos] += n
	}
	return out
}

func main() {
	// byPos holds every word's senses per part of speech, each list already
	// in WordNet's rank order, so the selection below can see all of them.
	byPos := map[string]map[string][]definition{}
	var synsets int

	for _, pf := range posFiles {
		glosses, n := readGlosses(filepath.Join(wordnetDir, pf.data))
		synsets += n
		// One pass over the index, which is already sorted by lemma, adding
		// each lemma's senses in the order the index gives them.
		forEachIndexEntry(filepath.Join(wordnetDir, pf.index),
			func(word string, offsets []string) {
				if !usableHeadword(word) {
					return
				}
				word = headwordText(word)
				for _, off := range offsets {
					g, ok := glosses[off]
					if !ok {
						continue
					}
					if byPos[word] == nil {
						byPos[word] = map[string][]definition{}
					}
					byPos[word][pf.pos] = append(byPos[word][pf.pos],
						definition{pf.pos, g.text, g.example})
				}
			})
	}

	counts := readCounts(filepath.Join(wordnetDir, cntlistFile))
	entries := map[string][]definition{}
	var reordered int
	for word, senses := range byPos {
		order := posOrder(counts[word])
		if len(order) > 0 && order[0] != posFiles[0].pos && len(senses) > 1 {
			reordered++
		}
		entries[word] = pick(senses, order)
	}

	// Merged last and allowed to win: a hand-written gloss for "will" is
	// about the auxiliary, which is the sense anyone selecting it means,
	// where WordNet's entry is about willpower and a legal document.
	added := mergeFunctionWords(entries)

	words := make([]string, 0, len(entries))
	for w := range entries {
		words = append(words, w)
	}
	sort.Strings(words)

	out := bufio.NewWriter(os.Stdout)
	defer out.Flush()
	fmt.Fprintln(out, "# Generated by tools/mkdefs -- do not edit.")
	fmt.Fprintf(out, "# %d words condensed from %s, senses in WordNet rank order.\n",
		len(words), wordnetDir)
	fmt.Fprintln(out, "# Licence and attribution: data/LICENSE-WORDNET31.")
	fmt.Fprintln(out, "# Format: word|pos:definition~example|pos:definition")
	var written, examples int
	for _, w := range words {
		var b strings.Builder
		b.WriteString(w)
		for _, d := range entries[w] {
			b.WriteByte('|')
			b.WriteString(d.pos)
			b.WriteByte(':')
			b.WriteString(clean(d.text))
			if d.example != "" {
				b.WriteByte('~')
				b.WriteString(clean(d.example))
				examples++
			}
			written++
		}
		fmt.Fprintln(out, b.String())
	}
	fmt.Fprintf(os.Stderr,
		"mkdefs: %d words, %d definitions (%d with an example) from %d synsets "+
			"(+%d hand-written, %d led by something other than a noun)\n",
		len(words), written, examples, synsets, added, reordered)
}

// clean makes one field safe for the line format. A pipe separates senses, a
// tilde separates a definition from its example, and neither may appear
// inside one. WordNet uses the pipe only as the gloss separator and contains
// a single tilde in 117,791 glosses, so this changes essentially nothing --
// it is here so that it cannot start mattering later.
func clean(s string) string {
	s = strings.ReplaceAll(s, "|", "/")
	s = strings.ReplaceAll(s, "~", "-")
	return strings.TrimSpace(s)
}

type gloss struct {
	text    string
	example string
}

// readGlosses reads data.<pos>, returning the gloss for each synset offset.
//
// A gloss is `definition; "an example"; "another"`, and the split is on the
// semicolon that precedes a quote rather than on the first semicolon of any
// kind. Cutting at the first semicolon truncated 14% of definitions
// mid-sentence: "a flight maneuver; aircraft tips laterally about its
// longitudinal axis" became "a flight maneuver", which says nothing.
func readGlosses(path string) (map[string]gloss, int) {
	f, err := os.Open(path)
	if err != nil {
		fmt.Fprintln(os.Stderr, "mkdefs:", err)
		os.Exit(1)
	}
	defer f.Close()

	out := make(map[string]gloss, 128*1024)
	var n int
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for sc.Scan() {
		line := sc.Text()
		// The licence is printed at the top of every data file, indented by
		// two spaces; every real entry starts with its offset.
		if strings.HasPrefix(line, "  ") {
			continue
		}
		head, raw, found := strings.Cut(line, "|")
		if !found {
			continue
		}
		offset, _, ok := strings.Cut(strings.TrimSpace(head), " ")
		if !ok || offset == "" {
			continue
		}
		text, example := splitGloss(raw)
		if text == "" {
			continue
		}
		out[offset] = gloss{text, example}
		n++
	}
	if err := sc.Err(); err != nil {
		fmt.Fprintln(os.Stderr, "mkdefs:", path+":", err)
		os.Exit(1)
	}
	return out, n
}

// splitGloss separates the definition from the first usage example.
func splitGloss(raw string) (text, example string) {
	raw = strings.TrimSpace(raw)
	// The examples begin at the first `; "`. Everything before it is the
	// definition, however many clauses it runs to.
	cut := -1
	for i := 0; i+1 < len(raw); i++ {
		if raw[i] != ';' {
			continue
		}
		rest := strings.TrimLeft(raw[i+1:], " ")
		if strings.HasPrefix(rest, `"`) {
			cut = i
			break
		}
	}
	if cut < 0 {
		return strings.TrimSpace(raw), ""
	}
	text = strings.TrimSpace(raw[:cut])
	// One example, not all of them: a second is rarely more use than the
	// first and every one costs space in a file that ships to every device.
	rest := strings.TrimSpace(raw[cut+1:])
	if open := strings.Index(rest, `"`); open >= 0 {
		if close := strings.Index(rest[open+1:], `"`); close >= 0 {
			example = strings.TrimSpace(rest[open+1 : open+1+close])
		}
	}
	return text, example
}

// forEachIndexEntry walks index.<pos>, handing each lemma its synset offsets
// in WordNet's sense-rank order.
//
// The line is: lemma pos synset_cnt p_cnt [ptr_symbol...] sense_cnt
// tagsense_cnt synset_offset... -- so the offsets are the last synset_cnt
// fields, and everything between is bookkeeping this does not need.
func forEachIndexEntry(path string, fn func(word string, offsets []string)) {
	f, err := os.Open(path)
	if err != nil {
		fmt.Fprintln(os.Stderr, "mkdefs:", err)
		os.Exit(1)
	}
	defer f.Close()

	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for sc.Scan() {
		line := sc.Text()
		if strings.HasPrefix(line, "  ") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 3 {
			continue
		}
		count, err := strconv.Atoi(fields[2])
		if err != nil || count <= 0 || count > len(fields) {
			continue
		}
		fn(strings.ToLower(fields[0]), fields[len(fields)-count:])
	}
	if err := sc.Err(); err != nil {
		fmt.Fprintln(os.Stderr, "mkdefs:", path+":", err)
		os.Exit(1)
	}
}

// mergeFunctionWords reads the hand-written glosses and replaces whatever
// WordNet had for the same word.
//
// Replaces rather than appends. Several of these words do have a WordNet
// entry for an unrelated sense -- "will" as determination, "can" as a metal
// container, "may" as the month -- and listing those first under a word
// somebody selected for its grammatical use is worse than saying nothing.
//
// The file may give an example after a tilde, exactly as the output format
// does.
func mergeFunctionWords(entries map[string][]definition) int {
	f, err := os.Open(functionWordFile)
	if err != nil {
		fmt.Fprintln(os.Stderr, "mkdefs:", err)
		os.Exit(1)
	}
	defer f.Close()

	var added int
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		word, body, found := strings.Cut(line, "|")
		if !found {
			continue
		}
		pos, text, found := strings.Cut(body, ":")
		if !found || strings.TrimSpace(text) == "" {
			continue
		}
		text, example, _ := strings.Cut(text, "~")
		if strings.TrimSpace(text) == "" {
			continue
		}
		word = strings.ToLower(strings.TrimSpace(word))
		if _, seen := entries[word]; !seen {
			added++
		}
		entries[word] = []definition{{
			pos:     strings.TrimSpace(pos),
			text:    strings.TrimSpace(text),
			example: strings.TrimSpace(example),
		}}
	}
	if err := sc.Err(); err != nil {
		fmt.Fprintln(os.Stderr, "mkdefs:", functionWordFile+":", err)
		os.Exit(1)
	}
	return added
}

// maxPhraseWords caps how long a headword may be.
//
// Three. WordNet carries entries of six and seven words -- "arteria
// gastrica sinistra", "American Federation of Labor" -- and a lookup is
// triggered by a selection, so an entry longer than anybody would select is
// weight in the file and nothing else. Two and three cover the phrasal
// verbs and compounds that are actually looked up: "take off", "give up
// on", "wedding ring".
const maxPhraseWords = 3

// usableHeadword keeps what a lookup could actually be triggered on: one to
// three alphabetic words.
//
// WordNet writes a multi-word entry with underscores, and those used to be
// rejected outright -- which discarded 64,246 headwords, 43% of its
// vocabulary, and left the tool with nothing to say about "take off" or "in
// spite of". Those are exactly the constructions somebody still learning
// English looks up, so they are kept now and the underscores become spaces.
func usableHeadword(w string) bool {
	if w == "" {
		return false
	}
	// WordNet joins a phrase's words with underscores and MyThes with
	// spaces; both are read here so the two generators can share this.
	words := 1
	for _, r := range w {
		switch {
		case r >= 'a' && r <= 'z':
		case r == '_' || r == ' ':
			words++
			if words > maxPhraseWords {
				return false
			}
		default:
			return false
		}
	}
	for _, bad := range []string{"_", " ", "__", "  ", "_ ", " _"} {
		if strings.HasPrefix(w, bad) || strings.HasSuffix(w, bad) ||
			strings.Contains(w, "__") || strings.Contains(w, "  ") {
			return false
		}
	}
	return true
}

// headwordText is the form a headword is stored and looked up under: the
// words as somebody would type them.
func headwordText(w string) string { return strings.ReplaceAll(w, "_", " ") }
