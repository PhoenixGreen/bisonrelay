// Command dumpdata writes the spellcheck-data payload for one language as
// JSON, exactly as the built module would answer get_spellcheck_data.
//
// It exists so the app's own tests can run the shipped rules through the
// app's own engine. The rules are written here and executed there, and for a
// long time nothing checked the two together: this package's tests run the
// patterns through Go's RE2, which cannot read every one of them, and the
// app's tests ran its engine over a handful of rules written out by hand.
// A rule could pass both and still do nothing in the running app.
//
// Run from the module root:
//
//	go run ./tools/dumpdata -locale en-US > /tmp/writingtools-en-US.json
package main

import (
	"bytes"
	"compress/gzip"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"

	"github.com/companyzero/bisonrelay/plugins/writingtools/spellcheck"
)

func gunzipFile(path string) (string, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	r, err := gzip.NewReader(bytes.NewReader(raw))
	if err != nil {
		return "", err
	}
	defer r.Close()
	out, err := io.ReadAll(r)
	return string(out), err
}

// example is one rule's own proof, for the app's tests to run: the plugin's
// tests cannot, since the engine that reads the rules is the app's.
type example struct {
	// Rule is what the app reports the rule as: a token rule's id, or a
	// regular expression's source.
	Rule   string   `json:"rule"`
	Flags  []string `json:"flags,omitempty"`
	Leaves []string `json:"leaves,omitempty"`
}

func read(path string) []byte {
	raw, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintln(os.Stderr, "dumpdata:", err)
		os.Exit(1)
	}
	return raw
}

func main() {
	locale := flag.String("locale", spellcheck.DefaultLanguage, "which language to dump")
	examples := flag.Bool("examples", false,
		"dump every rule's flags and leaves instead of the data")
	flag.Parse()

	if *examples {
		var out []example
		for _, r := range spellcheck.TokenRules {
			out = append(out, example{"token:" + r.ID, r.Flags, r.Leaves})
		}
		for _, r := range spellcheck.Rules {
			if len(r.Flags)+len(r.Leaves) > 0 {
				out = append(out, example{r.Pattern, r.Flags, r.Leaves})
			}
		}
		if err := json.NewEncoder(os.Stdout).Encode(out); err != nil {
			fmt.Fprintln(os.Stderr, "dumpdata:", err)
			os.Exit(1)
		}
		return
	}

	words, err := gunzipFile("words-" + *locale + ".txt.gz")
	if err != nil {
		fmt.Fprintln(os.Stderr, "dumpdata:", err)
		os.Exit(1)
	}
	common, err := gunzipFile("common-" + *locale + ".txt.gz")
	if err != nil {
		fmt.Fprintln(os.Stderr, "dumpdata:", err)
		os.Exit(1)
	}
	enc := json.NewEncoder(os.Stdout)
	if err := enc.Encode(spellcheck.Data{
		Words:          spellcheck.ParseWords(words),
		CommonWords:    spellcheck.ParseWords(common),
		Language:       *locale,
		Languages:      spellcheck.Languages,
		GrammarRules:   spellcheck.Rules,
		AnalysisChecks: spellcheck.AnalysisChecks,
		Grammar: spellcheck.NewGrammar(spellcheck.GrammarTables{
			LexiconGZ:     read("lexicon.txt.gz"),
			Transitions:   string(read("usage-tags.txt")),
			ConfusionSets: string(read("data/confusion-sets.txt")),
			NgramsGZ:      read("usage-ngrams.bin.gz"),
			PairWords:     string(read("usage-pairs.txt")),
			PairBitsGZ:    read("usage-pairs.bin.gz"),
			Countable:     string(read("usage-countable.txt")),
		}),
	}); err != nil {
		fmt.Fprintln(os.Stderr, "dumpdata:", err)
		os.Exit(1)
	}
}
