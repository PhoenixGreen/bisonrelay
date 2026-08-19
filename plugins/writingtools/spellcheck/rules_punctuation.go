package spellcheck

// rules_punctuation.go is the comma, and the marks around it.
//
// Most of what people mean by "check my commas" is not decidable by any
// amount of pattern matching. Whether a clause is restrictive, whether two
// halves of a sentence are independent, whether a list needs a serial comma
// -- each of those needs to know what the sentence *is*, not what it looks
// like, and a rule that guesses gets it wrong on ordinary writing. Comma
// splices in particular look exactly like a correctly punctuated
// introductory phrase, which is why they are not here.
//
// What is decidable is everything about a comma's own position: a comma
// cannot sit against a full stop, or inside a bracket it does not belong to,
// or with a space in front of it. Those are below. So is the one class of
// missing comma that is not a judgement call -- after a conjunctive adverb
// opening a sentence, where no other reading exists.
//
// Numbers are the trap that runs through all of it: "1,000" and "3:00" and
// "3.5" are correct and common, so every rule here is written to leave a
// comma between digits alone.

const (
	explainCommaPosition = "A comma joins what is before it to what comes " +
		"after. Against another mark it has nothing to join."
	explainCommaAfterAdverb = "A word like this opening a sentence is an " +
		"aside about the whole sentence, and takes a comma to separate it " +
		"from the sentence itself."
)

var punctuationRules = []GrammarRule{
	{
		// The commonest of these by far, and unambiguous: whatever the comma
		// was joining, the full stop ended it.
		Pattern:     `,\s*([.!?])`,
		Flags:       []string{"that is all,."},
		Message:     "Comma before \"$1\"",
		Suggest:     "$1",
		Category:    "Punctuation",
		Explanation: explainCommaPosition,
	},
	{
		Pattern:     `,\s*\)`,
		Flags:       []string{"(as noted,)"},
		Message:     "Comma before \")\"",
		Suggest:     ")",
		Category:    "Punctuation",
		Explanation: explainCommaPosition,
	},
	{
		Pattern:     `\(\s*,\s*`,
		Flags:       []string{"(, as noted)"},
		Message:     "Comma after \"(\"",
		Suggest:     "(",
		Category:    "Punctuation",
		Explanation: explainCommaPosition,
	},
	{
		// A comma runs into the quote or bracket that follows it. The
		// existing "missing space" rule only covers a letter after the
		// comma, which is the case that reads worst but not the only one.
		//
		// Digits are deliberately not included: "1,000" is a number, not a
		// mistake.
		Pattern:  `,(["(\[])`,
		Flags:    []string{`he said,"hello"`},
		Leaves:   []string{"it cost 1,000 today"},
		Message:  "Missing space after comma",
		Suggest:  ", $1",
		Category: "Spacing",
		Explanation: "Punctuation is followed by a space, which separates " +
			"it from what comes next. Without one the two run together.",
	},
	{
		// Two full stops. The antipatterns are the two readings that are not
		// a mistake: three or more dots is an ellipsis, and a dot pair
		// against a digit is a version number or a range.
		Pattern:      `\.\.`,
		Flags:        []string{"that is all.. we go"},
		Leaves:       []string{"wait for it... there", "the loop runs 0..10 in Rust"},
		Antipatterns: []string{`\.{3,}`, `\d\.\.`, `\.\.\d`},
		Message:      "Doubled full stop",
		Suggest:      ".",
		Category:     "Punctuation",
		Explanation: "One full stop ends a sentence. Three make an " +
			"ellipsis. Two are neither.",
	},
	{
		// The one missing comma with no other reading. Each of these words
		// opening a sentence is an aside about the sentence as a whole;
		// there is no construction where it runs straight into what follows.
		//
		// "However" and "Similarly" are deliberately absent, and they are
		// the two worth naming. "However you do it, it works" and "Similarly
		// designed products failed" are both correct, and both would be
		// broken by a comma.
		Pattern: `(?<=^|[.!?]\s|\n)(Therefore|Moreover|Furthermore|` +
			`Nevertheless|Consequently|Additionally|Meanwhile|Firstly|` +
			`Secondly|Finally)\s+(?=[A-Za-z])`,
		Flags:       []string{"Therefore we go"},
		Leaves:      []string{"we can therefore go", "However you do it, it works"},
		Message:     "Missing comma after \"$1\"",
		Suggest:     "$1, ",
		Category:    "Punctuation",
		Explanation: explainCommaAfterAdverb,
	},
	{
		// The same thing for the phrases, which cannot be read as anything
		// else either. "For example" and "In fact" are left out: "for
		// example sentences, see page 3" and "in fact checking" are both
		// noun phrases, and both would be broken.
		Pattern: `(?<=^|[.!?]\s|\n)(In conclusion|On the other hand|` +
			`In other words|As a result)\s+(?=[A-Za-z])`,
		Flags:       []string{"In conclusion we go"},
		Message:     "Missing comma after \"$1\"",
		Suggest:     "$1, ",
		Category:    "Punctuation",
		Explanation: explainCommaAfterAdverb,
	},
	{
		// A yes or a no answering a question is separate from what follows
		// it. Restricted to what can follow -- "No one knows" and "No
		// longer" would otherwise be cut in half.
		// Both cases for what follows. The Yes or No is capitalised because
		// it opens the sentence, but what comes after it very often is not
		// -- "Yes i think so" is exactly the kind of line this is for, and a
		// pattern that insisted on "I" would have missed it.
		Pattern: `(?<=^|[.!?]\s|\n)(Yes|No)\s+([Ii]|[Ww]e|[Yy]ou|[Hh]e|` +
			`[Ss]he|[Ii]t|[Tt]hey|thanks|thank)\b`,
		Flags:    []string{"No i do not", "Yes i agree"},
		Leaves:   []string{"No one knows the answer", "No longer a problem"},
		Message:  "Missing comma after \"$1\"",
		Suggest:  "$1, $2",
		Category: "Punctuation",
		Explanation: "A yes or no answering a question stands apart from " +
			"the sentence that follows it.",
	},
	{
		// A suggestion, not an error: the comma before a conjunction joining
		// two independent clauses is standard, and leaving it out is a
		// choice plenty of people make in short sentences.
		//
		// Only "but", and only before a pronoun and a verb. "So" is left out
		// because "so" meaning "in order that" takes no comma, and nothing
		// here can tell the two apart.
		Pattern:  `(\w{3,})\s+but\s+(I|we|you|he|she|it|they)\s+(\w+)`,
		Flags:    []string{"we tried but it failed"},
		Message:  "Consider a comma before \"but\"",
		Suggest:  "$1, but $2 $3",
		Category: "Punctuation",
		Explanation: "Two complete statements joined by \"but\" usually " +
			"take a comma before it. In a short sentence it is often left " +
			"out on purpose.",
		Severity: SeveritySuggestion,
	},
}
