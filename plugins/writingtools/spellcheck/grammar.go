package spellcheck

import "strings"

// grammar.go assembles the Grammar the plugin sends, from the tables its
// tools generate and the rules written in tokenrules_*.go.
//
// The tables are passed in rather than embedded here because they live at
// the module root, where main.go embeds them and tools/dumpdata reads them
// from disk; this package only knows what shape they go out in.

// GrammarTables are the generated files a Grammar is built from, each as it
// is stored.
type GrammarTables struct {
	LexiconGZ     []byte // lexicon.txt.gz
	Transitions   string // usage-tags.txt
	ConfusionSets string // data/confusion-sets.txt
	NgramsGZ      []byte // usage-ngrams.bin.gz
	PairWords     string // usage-pairs.txt
	PairBitsGZ    []byte // usage-pairs.bin.gz
	Countable     string // usage-countable.txt
}

// NewGrammar is the Grammar for the tables given. A build without its tables
// still answers: the rules that need them simply find nothing.
func NewGrammar(t GrammarTables) *Grammar {
	return &Grammar{
		Lexicon:       t.LexiconGZ,
		Transitions:   t.Transitions,
		ConfusionSets: ParseSets(t.ConfusionSets),
		Ngrams:        t.NgramsGZ,
		PairWords:     t.PairWords,
		PairBits:      t.PairBitsGZ,
		Classes:       classes(t.Countable),
		Rules:         TokenRules,
	}
}

// The classes that are counted rather than written: which nouns are not
// used without an article, as "is" and as "place" in usage-countable.txt.
const (
	ClassNeedsArticle      = "needs-article"
	ClassNeedsArticlePlace = "needs-article-place"
)

// classes is WordClasses with the counted classes added.
func classes(countable string) map[string][]string {
	all := make(map[string][]string, len(WordClasses)+2)
	for name, words := range WordClasses {
		all[name] = words
	}
	// Always present, so a rule naming one is a rule that finds nothing
	// rather than a rule that fails to compile.
	all[ClassNeedsArticle] = []string{}
	all[ClassNeedsArticlePlace] = []string{}
	for _, line := range strings.Split(countable, "\n") {
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		switch fields[0] {
		case "is":
			all[ClassNeedsArticle] = fields[1:]
		case "place":
			all[ClassNeedsArticlePlace] = fields[1:]
		}
	}
	return all
}

// ParseSets reads data/confusion-sets.txt: a set of words to a line, with
// blank lines and "#" comments ignored.
func ParseSets(txt string) []string {
	var sets []string
	for _, line := range strings.Split(txt, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		sets = append(sets, strings.Join(strings.Fields(line), " "))
	}
	return sets
}
