package spellcheck

// rules_contractions.go is the apostrophe people leave out: "dont", "wont",
// "youre".

// contractions are words missing their apostrophe, paired with the spelling
// wanted. Table-driven because there are two dozen of them differing in
// nothing but two strings, and written out longhand the first twelve took
// eighty lines and still left "didnt" -- the commonest of the lot -- out.
//
// Everything here is a spelling that is not an English word, which is what
// makes the rules safe to apply on sight. That is why the list stops where
// it does: "wed", "ill", "well", "shell", "hell", "id" and "were" are all
// real words, so "wed" cannot be corrected to "we'd" without knowing whether
// somebody got married. Those need the sentence, and the sentence is not
// available here.
//
// "Its" and "your" are absent for the same reason and are handled in
// rules_confusions.go, where the positions that decide them are spelled out.
var contractions = [][2]string{
	{"cant", "can't"}, {"wont", "won't"}, {"dont", "don't"},
	{"didnt", "didn't"}, {"doesnt", "doesn't"}, {"isnt", "isn't"},
	{"arent", "aren't"}, {"wasnt", "wasn't"}, {"werent", "weren't"},
	{"havent", "haven't"}, {"hasnt", "hasn't"}, {"hadnt", "hadn't"},
	{"wouldnt", "wouldn't"}, {"couldnt", "couldn't"},
	{"shouldnt", "shouldn't"}, {"mustnt", "mustn't"}, {"neednt", "needn't"},
	{"thats", "that's"}, {"whats", "what's"}, {"theres", "there's"},
	{"wheres", "where's"}, {"heres", "here's"}, {"whos", "who's"},
	{"youre", "you're"}, {"theyre", "they're"}, {"hes", "he's"},
	{"shes", "she's"}, {"ive", "I've"}, {"weve", "we've"},
	{"youve", "you've"}, {"theyve", "they've"}, {"youd", "you'd"},
	{"theyd", "they'd"}, {"youll", "you'll"}, {"theyll", "they'll"},
	{"oclock", "o'clock"},
}

const explainContraction = "This is a contraction -- two words shortened " +
	"into one -- and the apostrophe stands in for the letters that were " +
	"dropped."

func buildContractionRules() []GrammarRule {
	rules := make([]GrammarRule, 0, len(contractions))
	for _, pair := range contractions {
		wrong, right := pair[0], pair[1]
		rules = append(rules, GrammarRule{
			Pattern:     `\b` + eitherCase(wrong) + `\b`,
			Flags:       []string{"i " + wrong + " think so"},
			Message:     "Missing apostrophe",
			Suggest:     right,
			Category:    "Punctuation",
			Explanation: explainContraction,
		})
	}
	return rules
}

// contractionRules is the group rules.go assembles, built from the table above
// rather than written out: two dozen rules differing in nothing but two
// strings, and written longhand the first twelve took eighty lines and still
// left "didnt" -- the commonest of the lot -- out.
var contractionRules = buildContractionRules()
