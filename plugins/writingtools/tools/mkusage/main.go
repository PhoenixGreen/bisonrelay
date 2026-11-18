// Command mkusage counts how English is used, in a large body of edited text,
// and writes down the three things about it the app's checker needs.
//
//   - usage-tags.txt: how much likelier one part of speech is after another.
//     The lexicon says "works" can be a noun or a verb; this is what says
//     which it is after "the" and which after "it".
//   - usage-ngrams.bin: the company each confusable word keeps -- how often
//     "real" and "reel" each sit between "a" and "problem". See
//     data/confusion-sets.txt.
//   - usage-pairs.bin and usage-pairs.txt: which pairs of common words are
//     never found side by side, however often chance alone says they should
//     be. "the of" would turn up 160,000 times if words fell at random.
//   - usage-countable.txt: which nouns are not written without an article.
//
// and one for the dictionary:
//
//   - data/frequency.txt: how often each word is written, which is what
//     ranks corrections for a misspelling.
//
// The text is not in the repository and none of it ships: only the counts
// do. It is the Leipzig Corpora Collection's English corpora, one sentence
// per line as "number<TAB>sentence" -- see data/LICENSE-LEIPZIG for which,
// and README.md for how to fetch them.
//
// A seventeenth of every file is left uncounted, so the app's tests can
// measure the checker on text it has not already seen.
//
// Run from the module root, after mklexicon:
//
//	go run ./tools/mkusage /path/to/*-sentences.txt
package main

import (
	"bufio"
	"encoding/binary"
	"fmt"
	"hash/fnv"
	"math"
	"os"
	"sort"
	"strings"
)

const (
	lexiconFile = "lexicon.txt"
	setsFile    = "data/confusion-sets.txt"

	// Every holdoutEvery-th line, at holdoutAt, is kept out of the counts.
	holdoutEvery = 17
	holdoutAt    = 3

	// pairWords is how many of the commonest words the never-together table
	// covers. Its size is the square of this.
	pairWords = 4000

	// A pair is recorded as never-together when chance would put it side by
	// side at least pairExpected times in the text and it was found fewer
	// than one time in pairRarity of that.
	//
	// The first number is the one that matters. At 20 the table held 49,000
	// pairs and half of what it marked in edited text was sound -- "the
	// senior can sign up", "projects about history" -- because two fairly
	// common words that had simply never met look the same, to a count, as
	// two that cannot. At 120 nearly every pair left has a grammar word on
	// one side or both, which is where "cannot" lives: "the of", "is be",
	// "our and", "a what".
	pairExpected = 120.0
	pairRarity   = 150.0

	// priorWeight is how far "found there far more than its rival" allows
	// for one of the two being commoner everywhere: 0 would not allow for it
	// at all, and 1 would ask a word fifty times commoner than its rival to
	// be found fifty times oftener before the context counted for anything.
	//
	// It was 1 at first, and "a reel problem" went unremarked: "real
	// problem" is in the text 216 times and "reel problem" never, and 216
	// was not fifty times the nothing it needed to beat by enough. Halfway
	// keeps the contexts where the commoner word plainly belongs without
	// keeping every place it has ever been.
	priorWeight = 0.5

	// ngramBudget is how many counted contexts ship, across all the sets.
	// Each costs six bytes.
	ngramBudget = 1200000
)

func main() {
	files := os.Args[1:]
	if len(files) == 0 {
		fatal(fmt.Errorf("usage: mkusage SENTENCES.txt..."))
	}
	lex := readLexicon()
	sets := readSets()

	// --- first pass: how often each word is written ---
	freq := map[string]uint32{}
	var tokens uint64
	eachSentence(files, func(line string) {
		for _, u := range units(tokenize(line, lex)) {
			freq[u]++
			tokens++
		}
	})
	writeFrequency(freq, lex)

	// The commonest words, for the never-together table.
	type wc struct {
		w string
		c uint32
	}
	ranked := make([]wc, 0, len(freq))
	for w, c := range freq {
		if w == "#" || w == "*" {
			continue
		}
		ranked = append(ranked, wc{w, c})
	}
	sort.Slice(ranked, func(i, j int) bool {
		if ranked[i].c != ranked[j].c {
			return ranked[i].c > ranked[j].c
		}
		return ranked[i].w < ranked[j].w
	})
	if len(ranked) > pairWords {
		ranked = ranked[:pairWords]
	}
	rank := map[string]int{}
	for i, e := range ranked {
		rank[e.w] = i
	}

	// --- second pass: pairs, contexts, and which tag follows which ---
	members := newMembers(sets)
	pairs := map[uint32]uint32{}
	grams := map[uint64]uint32{}
	nouns := map[string]*nounUse{}
	model := newTagModel()
	n := 0
	eachSentence(files, func(line string) {
		toks := tokenize(line, lex)
		us := units(toks)
		for i := 0; i+1 < len(us); i++ {
			a, ok := rank[us[i]]
			if !ok {
				continue
			}
			if b, ok := rank[us[i+1]]; ok {
				pairs[uint32(a*pairWords+b)]++
			}
		}
		for i, u := range us {
			id, ok := members.id[u]
			if !ok {
				continue
			}
			l1, l2, r1, r2 := at(us, i-1), at(us, i-2), at(us, i+1), at(us, i+2)
			grams[slot(context("l", l1), id)]++
			grams[slot(context("r", r1), id)]++
			grams[slot(context("M", l1, r1), id)]++
			grams[slot(context("A", l2, l1), id)]++
			grams[slot(context("B", r1, r2), id)]++
		}
		countNouns(us, lex, nouns)
		// One sentence in eight is plenty for a table of forty tags squared.
		if n++; n%8 == 0 {
			model.countSure(toks, lex)
		}
	})

	writePairs(ranked2words(ranked, func(e wc) string { return e.w }), func(i, j int) (uint32, float64) {
		return pairs[uint32(i*pairWords+j)],
			float64(ranked[i].c) * float64(ranked[j].c) / float64(tokens)
	})
	writeNgrams(grams, members, freq)
	writeCountable(nouns)

	// The tag table is settled in three rounds. The first counted only
	// between words that have one reading; each later round tags the text
	// with the last table and counts everything.
	model.finish()
	for round := 0; round < 2; round++ {
		next := newTagModel()
		n = 0
		eachSentence(files, func(line string) {
			if n++; n%8 != 0 {
				return
			}
			next.countTagged(tokenize(line, lex), lex, model)
		})
		next.finish()
		model = next
	}
	model.write()
}

func ranked2words[T any](list []T, word func(T) string) []string {
	out := make([]string, len(list))
	for i, e := range list {
		out[i] = word(e)
	}
	return out
}

func at(us []string, i int) string {
	if i < 0 {
		return "<s>"
	}
	if i >= len(us) {
		return "</s>"
	}
	return us[i]
}

// context is a hash of the words around a gap and which gap it is: "M" for
// the word either side, "A" and "B" for the two before and the two after,
// "l" and "r" for the one before and the one after. The app builds the same
// string and takes the same hash, and that is the whole of the format --
// engine/language/usage.dart is the other copy.
func context(kind string, parts ...string) uint64 {
	h := fnv.New64a()
	h.Write([]byte(kind))
	for _, p := range parts {
		h.Write([]byte{0})
		h.Write([]byte(p))
	}
	return h.Sum64()
}

// wordBits is how many of a context's low bits are given over to saying
// which confusable word was in the gap, while counting.
const wordBits = 10

func slot(ctx uint64, word int) uint64 { return ctx&^(1<<wordBits-1) | uint64(word) }

// fileKey is what a context with a particular word in its gap is stored
// under: the two hashes mixed and folded to four bytes.
//
// Four bytes are not enough on their own. A million entries fill one part in
// four thousand of what four bytes can say, so one lookup in four thousand
// for a context that was never kept would land on some other context's
// count -- and nearly every lookup is for a context that was never kept. A
// document makes thousands of them, and each false hit reads as "the other
// word is found here". So a fifth byte from elsewhere in the hash goes with
// each key, and a lookup has to match both.
func fileKey(ctx uint64, word string) (key uint32, check byte) {
	w := fnv.New64a()
	w.Write([]byte(word))
	h := (ctx>>wordBits)*0x9E3779B97F4A7C15 ^ w.Sum64()
	h ^= h >> 29
	h *= 0xBF58476D1CE4E5B9
	h ^= h >> 32
	return uint32(h), byte(h >> 40)
}

// members numbers the confusable words and remembers each one's rivals.
type members struct {
	id     map[string]int
	words  []string
	rivals [][]int
}

func newMembers(sets [][]string) *members {
	m := &members{id: map[string]int{}}
	for _, set := range sets {
		for _, w := range set {
			if _, ok := m.id[w]; !ok {
				m.id[w] = len(m.words)
				m.words = append(m.words, w)
				m.rivals = append(m.rivals, nil)
			}
		}
	}
	if len(m.words) >= 1<<wordBits {
		fatal(fmt.Errorf("%d confusable words is more than wordBits allows", len(m.words)))
	}
	for _, set := range sets {
		for _, w := range set {
			for _, x := range set {
				if x != w {
					m.rivals[m.id[w]] = append(m.rivals[m.id[w]], m.id[x])
				}
			}
		}
	}
	return m
}

func eachSentence(files []string, fn func(string)) {
	for _, path := range files {
		file, err := os.Open(path)
		if err != nil {
			fatal(err)
		}
		sc := bufio.NewScanner(file)
		sc.Buffer(make([]byte, 1<<20), 1<<24)
		n := 0
		for sc.Scan() {
			n++
			if n%holdoutEvery == holdoutAt {
				continue
			}
			line := sc.Text()
			if tab := strings.IndexByte(line, '\t'); tab >= 0 {
				line = line[tab+1:]
			}
			fn(line)
		}
		file.Close()
	}
}

// --- the never-together table ---

func writePairs(words []string, count func(i, j int) (seen uint32, expected float64)) {
	n := len(words)
	bits := make([]byte, (n*n+7)/8)
	marked := 0
	for i := 0; i < n; i++ {
		for j := 0; j < n; j++ {
			seen, expected := count(i, j)
			if expected >= pairExpected && float64(seen) < expected/pairRarity {
				at := i*n + j
				bits[at/8] |= 1 << (at % 8)
				marked++
			}
		}
	}
	must(os.WriteFile("usage-pairs.txt", []byte(strings.Join(words, "\n")+"\n"), 0o644))
	must(os.WriteFile("usage-pairs.bin", bits, 0o644))
	fmt.Fprintf(os.Stderr, "mkusage: %d words, %d pairs never together\n", n, marked)
}

// --- the confusable words' company ---

// writeNgrams keeps the contexts that can decide between a word and its
// rivals, and writes them sorted by key, each with its count on a log scale.
//
// Nearly all of what was counted decides nothing. "to" was seen in two
// million contexts, and in almost every one of them "too" was not seen at
// all and nobody would write it. A context earns its five bytes only where
// a word is found there far more than its rival is, allowing for how much
// commoner one of them is everywhere: then somebody who wrote the rival
// there has probably made the mistake.
//
// The rival's own count for such a context is kept beside it, so the app can
// take an absent context as a count of nothing rather than as a count nobody
// wrote down.
func writeNgrams(grams map[uint64]uint32, m *members, freq map[string]uint32) {
	keys := make([]uint64, 0, len(grams))
	for k := range grams {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool { return keys[i] < keys[j] })

	type entry struct {
		k     uint32
		check byte
		c     uint32
	}
	add := func(list []entry, ctx uint64, word string, c uint32) []entry {
		k, check := fileKey(ctx, word)
		return append(list, entry{k, check, c})
	}
	var kept []entry
	for factor := 2.0; ; factor *= 1.5 {
		kept = kept[:0]
		keep := map[int]bool{}
		for from := 0; from < len(keys); {
			to := from + 1
			for to < len(keys) && keys[to]>>wordBits == keys[from]>>wordBits {
				to++
			}
			// One context, and every confusable word seen in it.
			count := map[int]uint32{}
			for _, k := range keys[from:to] {
				count[int(k&(1<<wordBits-1))] = grams[k]
			}
			for k := range keep {
				delete(keep, k)
			}
			for w, cw := range count {
				if cw < 2 {
					continue
				}
				for _, x := range m.rivals[w] {
					prior := float64(freq[m.words[w]]+1) / float64(freq[m.words[x]]+1)
					if float64(cw) >= factor*math.Pow(prior, priorWeight)*float64(count[x]+1) {
						keep[w] = true
					}
				}
			}
			// Every rival of a word that is kept is kept beside it, and so
			// on outwards. A word can be in more than one set -- "no" is
			// confused with "know" and with "not" -- and a count kept for
			// one of those would otherwise be read against a blank for the
			// other, as though "not visible" had never been written.
			for grew := true; grew; {
				grew = false
				for w := range keep {
					for _, x := range m.rivals[w] {
						if count[x] > 0 && !keep[x] {
							keep[x] = true
							grew = true
						}
					}
				}
			}
			for w := range keep {
				kept = add(kept, keys[from], m.words[w], count[w])
			}
			from = to
		}
		fmt.Fprintf(os.Stderr, "mkusage: %d contexts decide at %.1f times the odds\n",
			len(kept), factor)
		if len(kept) <= ngramBudget {
			break
		}
	}
	// How often each word is written at all: what "far more than its rival"
	// is measured against.
	for _, w := range m.words {
		if c := freq[w]; c > 0 {
			kept = add(kept, context("u"), w, c)
		}
	}
	sort.Slice(kept, func(i, j int) bool {
		if kept[i].k != kept[j].k {
			return kept[i].k < kept[j].k
		}
		return kept[i].check < kept[j].check
	})

	// The count, then every key, then every check byte, then every count:
	// three columns rather than a row each, so the keys can be searched as
	// the numbers they are.
	n := len(kept)
	out := make([]byte, 4+6*n)
	binary.LittleEndian.PutUint32(out[0:], uint32(n))
	for i, e := range kept {
		binary.LittleEndian.PutUint32(out[4+4*i:], e.k)
		out[4+4*n+i] = e.check
		out[4+5*n+i] = logCount(e.c)
	}
	must(os.WriteFile("usage-ngrams.bin", out, 0o644))
	fmt.Fprintf(os.Stderr, "mkusage: %d contexts kept of %d counted\n",
		len(kept), len(grams))

	for _, w := range m.words {
		if freq[w] < 20 {
			fmt.Fprintf(os.Stderr, "mkusage: %q was seen %d times\n", w, freq[w])
		}
	}
}

// logCount fits a count in a byte: eight steps to each doubling.
func logCount(c uint32) byte {
	v := math.Round(8 * math.Log2(float64(c)))
	if v > 255 {
		v = 255
	}
	return byte(v)
}

func writeFrequency(freq map[string]uint32, lex *lexicon) {
	type wc struct {
		w string
		c uint32
	}
	var list []wc
	for w, c := range freq {
		if c >= 3 && lex.has(w) {
			list = append(list, wc{w, c})
		}
	}
	sort.Slice(list, func(i, j int) bool {
		if list[i].c != list[j].c {
			return list[i].c > list[j].c
		}
		return list[i].w < list[j].w
	})
	var b strings.Builder
	b.WriteString("# Generated by tools/mkusage -- do not edit.\n")
	b.WriteString("# How often each dictionary word is written, commonest first.\n")
	b.WriteString("# Counted from the corpora named in data/LICENSE-LEIPZIG.\n")
	for _, e := range list {
		fmt.Fprintf(&b, "%s\t%d\n", e.w, e.c)
	}
	must(os.WriteFile("data/frequency.txt", []byte(b.String()), 0o644))
}

// --- which nouns need an article ---

// nounUse is how a noun was found where a noun phrase plainly ends with it:
// after "is" with and without "a", and after a preposition with and without
// a determiner.
type nounUse struct {
	isA, isBare, prepDet, prepBare uint32
}

var (
	copulas = map[string]bool{"is": true, "was": true, "am": true}
	places  = map[string]bool{"in": true, "to": true, "at": true, "from": true,
		"into": true, "near": true}
	articles    = map[string]bool{"a": true, "an": true}
	determiners = map[string]bool{"a": true, "an": true, "the": true, "my": true,
		"your": true, "his": true, "her": true, "our": true, "their": true,
		"this": true, "that": true}
	// What can follow the last word of a noun phrase. Without this "is car
	// insurance" would be counted as "car" doing without an article.
	phraseEnds = map[string]bool{"</s>": true, ",": true, ".": true, "and": true,
		"or": true, "but": true, "who": true, "that": true, "which": true,
		"in": true, "on": true, "at": true, "for": true, "of": true,
		"with": true, "to": true, "from": true, "by": true, "as": true,
		"when": true, "while": true, "because": true, "if": true, "so": true,
		"than": true}
)

func countNouns(us []string, lex *lexicon, nouns map[string]*nounUse) {
	nn := tagID["NN"]
	for i, u := range us {
		if !phraseEnds[at(us, i+1)] {
			continue
		}
		share := 0
		for _, r := range lex.words[u] {
			if r.tag == nn {
				share = r.weight
			}
		}
		if share < 60 {
			continue
		}
		use := nouns[u]
		if use == nil {
			use = &nounUse{}
			nouns[u] = use
		}
		l1, l2 := at(us, i-1), at(us, i-2)
		switch {
		case copulas[l1]:
			use.isBare++
		case articles[l1] && copulas[l2]:
			use.isA++
		}
		switch {
		case places[l1]:
			use.prepBare++
		case determiners[l1] && places[l2]:
			use.prepDet++
		}
	}
}

// writeCountable lists the nouns that are not written without an article:
// "student", "idea", "house". English does not mark which nouns those are,
// and no dictionary here says -- "I am student" is wrong and "I am president"
// is not. What can be counted is how each noun is actually used. One that
// follows "is a" hundreds of times and bare "is" almost never is a noun that
// wants its article.
//
// Two lists, because the two positions differ: "home", "school" and "work"
// go bare after a preposition and not after "is".
func writeCountable(nouns map[string]*nounUse) {
	var afterIs, afterPrep []string
	for w, u := range nouns {
		if u.isA >= 15 && float64(u.isBare) <= 0.03*float64(u.isA) {
			afterIs = append(afterIs, w)
		}
		if u.prepDet >= 40 && float64(u.prepBare) <= 0.02*float64(u.prepDet) {
			afterPrep = append(afterPrep, w)
		}
	}
	sort.Strings(afterIs)
	sort.Strings(afterPrep)
	must(os.WriteFile("usage-countable.txt", []byte(
		"# Generated by tools/mkusage -- do not edit.\n"+
			"# Nouns not written without an article: after \"is\", then after a\n"+
			"# preposition of place.\n"+
			"is "+strings.Join(afterIs, " ")+"\n"+
			"place "+strings.Join(afterPrep, " ")+"\n"), 0o644))
	fmt.Fprintf(os.Stderr, "mkusage: %d nouns need an article after \"is\", %d after a preposition\n",
		len(afterIs), len(afterPrep))
}

func readSets() [][]string {
	var sets [][]string
	file, err := os.Open(setsFile)
	if err != nil {
		fatal(err)
	}
	defer file.Close()
	sc := bufio.NewScanner(file)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		sets = append(sets, strings.Fields(line))
	}
	return sets
}

func must(err error) {
	if err != nil {
		fatal(err)
	}
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, "mkusage:", err)
	os.Exit(1)
}
