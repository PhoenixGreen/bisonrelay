package spellcheck

import (
	"regexp"
	"strings"
	"testing"
	"unicode"
)

func TestParseWordsSkipsBlanksAndComments(t *testing.T) {
	in := "# a comment\nHello\n\n  World  \n# another comment\nfoo\n"
	got := ParseWords(in)
	want := []string{"hello", "world", "foo"}
	if len(got) != len(want) {
		t.Fatalf("ParseWords(%q) = %v, want %v", in, got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("ParseWords(%q)[%d] = %q, want %q", in, i, got[i], want[i])
		}
	}
}

// countGroups counts the capturing groups in a pattern: an unescaped "("
// that does not open a non-capturing "(?...)" construct.
func countGroups(pattern string) int {
	n := 0
	for i := 0; i < len(pattern); i++ {
		switch pattern[i] {
		case '\\':
			i++ // skip whatever is escaped
		case '[':
			// Character classes may contain a literal "(".
			for i < len(pattern) && pattern[i] != ']' {
				if pattern[i] == '\\' {
					i++
				}
				i++
			}
		case '(':
			if i+1 < len(pattern) && pattern[i+1] == '?' {
				continue
			}
			n++
		}
	}
	return n
}

// TestRulesSuggestReferencesExist is the check that matters most for a rule
// file edited by hand: a "$2" in a rule with one group produces a suggestion
// with a literal "$2" in it, and nothing at build or load time notices.
func TestRulesSuggestReferencesExist(t *testing.T) {
	ref := regexp.MustCompile(`\$(\d+)`)
	for i, r := range Rules {
		groups := countGroups(r.Pattern)
		// Every replacement the rule offers, not only the first: an
		// alternative is spliced into the text exactly as Suggest is, and a
		// dangling $3 in one shows the reader a literal "$3" just the same.
		for _, template := range append([]string{r.Suggest}, r.Alternatives...) {
			for _, m := range ref.FindAllStringSubmatch(template, -1) {
				var n int
				for _, c := range m[1] {
					n = n*10 + int(c-'0')
				}
				if n > groups {
					t.Errorf("Rules[%d] (%q): %q references $%d but Pattern has %d groups",
						i, r.Message, template, n, groups)
				}
			}
		}
		if len(r.Alternatives) > 0 && r.Suggest == "" {
			t.Errorf("Rules[%d] (%q): has alternatives but no first answer",
				i, r.Message)
		}
	}
}

func TestRulesAreWellFormed(t *testing.T) {
	if len(Rules) == 0 {
		t.Fatal("Rules is empty")
	}
	seen := map[string]bool{}
	for i, r := range Rules {
		if r.Pattern == "" {
			t.Errorf("Rules[%d] has an empty pattern", i)
		}
		if r.Message == "" {
			t.Errorf("Rules[%d] (%q) has no message", i, r.Pattern)
		}
		if seen[r.Pattern] {
			t.Errorf("Rules[%d]: duplicate pattern %q", i, r.Pattern)
		}
		seen[r.Pattern] = true
	}
}

// correctText is ordinary, correct writing of the kind these rules will be
// run against constantly. Nothing here should be flagged.
var correctText = []string{
	"I sent the payment yesterday and it cleared this morning.",
	"Let's meet at 3pm. That works for me.",
	"The channel is open, so the invoice should route fine.",
	"Have a look at example.com when you get a chance.",
	"It cost 3.5 DCR, which isn't bad at all.",
	"He said (quite clearly) that he wouldn't be joining us.",
	"Can't wait -- that's excellent news!",
	"What's the plan for the release? I'd like to help.",
	"We should have tested it first; now we know.",
	"I'm going to the shop, and then I'll head home.",
	"Fine. Next question, then.",

	// "A" before a plural. All correct, and all of it is exactly the shape
	// the pluralAfterA rules look for, so this is where they are kept
	// honest. Two ways it is right: a plural describing the noun after it,
	// and a singular noun that merely ends in the letter s.
	"We put a comments section on a results page.",
	"She joined a sales team after opening a savings account.",
	"It is a systems problem, not a settings menu one.",
	"There is a bus at six and a class after it.",
	"That is a means to an end and a series of steps.",
	"It became a crisis, which is a process nobody enjoys.",
	"A few years ago we shipped a couple of days early.",

	// Agreement. Every line here is correct and sits in exactly the shape
	// rules_agreement.go looks for, which is the only reason that file is
	// allowed to exist at all -- the subjunctive, a singular subject with a
	// plural noun beside the verb, and the quantifiers that take a mass noun.
	"If I were you I would wait, and I wish it were simpler.",
	"She asked whether it were possible, but as it were, nobody minded.",
	"The list of files was long and the set of rules was short.",
	"There was plenty of time and there was lots of grass.",
	"Some of it was fine, and all of this was expected.",
	"All business of this kind was handled locally.",
	"We use it to open the door, and I suppose to err is human.",
	"He was supposed to call, and we used to meet on Fridays.",
	"I can hardly wait, and we could hardly move.",
	// The reading that made the two pronoun rules argue with each other:
	// fixing the first sentence produces the second, which the other rule
	// then offered to change straight back.
	"Some parts of it were exciting, and a photo of you was on the wall.",
	"A box of chocolates was on the table and both of the answers were right.",
	"Neither of us was ready, and each of them was tested.",
	// The shapes the newest agreement and double-negative rules look for,
	// all of it correct writing.
	"There was a receipt in my bag, and there was glass everywhere.",
	"There was a series of delays and there was progress at last.",
	"Bread and butter was all we had, and fish and chips was on the menu.",
	"The news and the weather was on while we waited.",
	"I didn't need it and it doesn't succeed often.",
	"I couldn't find it anywhere and she never said anything.",
	"There was hardly any time and hardly any seats were left.",
	"He had already gone, and I have just eaten.",
	"She told me and my friend the news, and it gave me and my mate time.",
	"see docs.rs and news.ycombinator.com for details",
	// its/it's used correctly, which the new rules must not touch.
	"The channel lost its funding, and it's closed now.",
	"Its balance is low, but its owner has more.",
	"It's going to take a while.",
	// Possessives before nouns that look like the words above: each of these
	// is correct and an over-eager rule would flag it.
	"Its true value is hard to judge.",
	"Its cold storage keeps the keys offline.",
	"Its early adopters were patient.",
	"Its best feature is the relay.",
	"Its interesting parts are undocumented.",
	"Its going rate is higher than that.",
	"Its freezing point is well below zero.",
	"Its only purpose is to relay messages.",
	"e.g. this one, i.e. that one",
	// their/there used correctly, which the new confusion rules must not
	// touch: a possessive before a noun, and an existential before a verb.
	"Their wallet is empty, so there is nothing to send.",
	"There are two of them, and their channels are both open.",
	"They brought their own hardware to the meetup.",
	"I told them there would be a delay.",

	// then/than used correctly, in both directions.
	"I would rather walk than drive.",
	"Other than that, it went fine.",
	"We synced the wallet and then sent the payment.",
	"Back then the fees were higher.",

	// lose/loose. The adjective is the whole reason the rule needs an object
	// after it before it fires.
	"The connector is loose, so check it before you plug in.",
	"He handed over a loose collection of notes.",
	"I did not want to lose the channel.",

	// affect/effect. "Effect" as a verb is real; so is "affect" as a noun in
	// clinical writing, though that one is rarer than the typo.
	"The upgrade will effect change across the network.",
	"The fee had no effect on routing.",
	"Latency does affect the user experience.",

	// your/you're. Every one of these was flagged by an earlier draft of the
	// rule, and every one of them is correct.
	"It is your right to refuse.",
	"Please confirm your correct address.",
	"We received your late payment yesterday.",
	"Your next appointment is on Tuesday.",
	"Thanks for your amazing work on the relay.",
	"Your invited guests can bring one other person.",
	"Your mistaken belief is understandable.",

	// to/too. The bare "to" before an adjective is fine; only the leading
	// verb makes it wrong.
	"I spoke to many people about it.",
	"We went to great lengths to fix it.",
	"That is to be expected at this stage.",

	// in principal. "Principal" is also an adjective.
	"The bank operates in principal cities only.",
	"Interest is charged on principal amounts over 1 DCR.",
	"I agree in principle with the proposal.",

	// have + participle, done properly.
	"They have gone quiet since the release.",
	"We have run the migration twice.",
	"She has read the specification.",

	// Words the confusion rules cover, used the right way round.
	"Whose keys are these?",
	"Who's going to review it?",
	"Please advise us on the best approach.",
	"Thanks for the advice about routing.",
	"Bear with me while I sync.",
	"That was a part of the original design.",

	// brake/break, both words used correctly. The verb "breaks" is the whole
	// difficulty: three of these are a thing being damaged or a rota, and all
	// three sit in exactly the shape the brake rules look for.
	"Let's take a break and come back at two.",
	"Press the brake before the corner and the hand brake at the top.",
	"My car breaks down every winter, but the brakes are fine.",
	"The disc breaks under load, so we replaced the front brakes.",
	"Their breaks are too short and the front breaks off in transit.",
	"We break for lunch at noon and brake at the junction on the way.",

	// A possessive before an -ing word, used correctly. The first four are
	// the fused participle -- the possessive really does own the action,
	// because the whole phrase is the subject -- and the rest are the -ing
	// words that are ordinary nouns.
	"Your talking is distracting me, and their leaving was sudden.",
	"Your asking helps nobody and his coming was a surprise.",
	"Their taking of the city ended the war.",
	"Your writing is good and your thinking is clear.",
	"Whose cooking is this, and whose writing is on the box?",
	"Check your reading list before your training day.",
	"Is there going to be a meeting, or was there something else?",
	"The path out there going north is closed.",

	// The rest of the confusable pairs added alongside them, every one used
	// the right way round.
	"We will go outside whether or not the weather improves.",
	"I want a piece of cake, and it gave me a peace of mind I needed.",
	"There is a hole in the wall, but the whole wall is sound.",
	"I've seen that film and the final scene was excellent.",
	"We were allowed to read the story, and she read it aloud to the class.",
	"Take a deep breath and breathe slowly.",
	"The criticism didn't faze her during the next phase of the project.",
	"The room is quite large but very quiet.",
	"We walked past the station after we passed the shop.",
	"In the past I would have accepted everyone except Tom.",
	"I lead the team every Tuesday, we lead the market, and she led the group.",
	"The car was stationary while I bought some stationery.",
	"I know the answer is no.",
	"I need to go early because there is too much to do.",

	// The homophone batch, every pair used correctly. The lines that matter
	// most are the ones where the *other* spelling is the one that follows
	// the same shape: "the prophet preached" after a determiner, "steel
	// himself" after a modal, "the Isle of Wight" after a determiner, and
	// "his alter ego" after "the".
	"I can hear something outside, so come over here.",
	"I knew I needed a new car.",
	"We won the match by one goal.",
	"I felt weak for a week after being ill.",
	"Let's meet after we buy some meat.",
	"He threw the ball through the window.",
	"Don't waste food, and check your waist size.",
	"Please wait while I check the weight, and the wait was worth it.",
	"We need to weigh the bags before deciding which way to go.",
	"I would build the table from wood.",
	"The seam came loose but the trousers seem fine.",
	"Don't stare at people while walking down the stairs.",
	"The dog wagged its tail while I told a tale.",
	"The king sat on the throne after the crown was thrown down.",
	"I heard a noise while watching the herd of cows.",
	"I guessed that our guest would arrive early.",
	"I was bored during the meeting and stared at the board.",
	"The band was banned from playing after midnight.",
	"They stood beside the altar and would not alter the ceremony, and the alter ego stayed hidden.",
	"The city council sought legal counsel.",
	"They used a clever device and devised a new solution.",
	"The question was designed to elicit information about an illicit trade.",
	"She was discreet about the matter, which had several discrete parts.",
	"Please ensure the door is locked and insure the car.",
	"He has a decent salary and began his descent down the mountain.",
	"The medicine helped lessen the pain and taught me a lesson.",
	"The lone student applied for a student loan.",
	"The flag was attached to a pole after the election poll.",
	"I like to pore over books while you pour the tea.",
	"The dragon likes to hoard gold while a horde approaches.",
	"He was vain about the vein on his hand, and it was all in vain.",
	"The eagle began to soar while my legs were sore.",
	"We met in the morning during a period of mourning.",
	"She won a medal and promised not to meddle.",
	"I read a book about a red car.",
	"The sole of my shoe is worn but my soul is happy.",
	"The company made a profit while the prophet preached.",
	"We walked down the aisle before visiting the Isle of Wight.",
	"The sky was blue and the wind blew strongly.",
	"The child began to whine while the adults drank wine.",
	"They used steel to build it and nobody tried to steal it, though he had to steel himself first.",
	"We learned to sail while the shop held a sale, and the house is for sale.",
	"After crossing the desert we had dessert.",
	"She stepped forth on the fourth day.",
	"He behaved in a polite manner while visiting the old manor house.",
	"In the presence of the head teacher she opened her presents.",
	"London is the capital city.",
	"We heard the floor creak beside the small creek.",
	"The building was formerly a school and was formally opened as a museum.",
	"I hurt my toe when we called a tow truck.",
	"Bear in mind that the bare minimum will do.",

	// The second homophone pass. These pairs are two nouns, so a determiner
	// decides nothing -- "a currant bush", "a beech tree", "the gilt frame"
	// and "a leek" are all correct and all were flagged by a first draft that
	// leaned on one.
	"I can see the sea from my window.",
	"Where did you wear your new shoes, and go to where the road ends.",
	"I don't know whether the weather will improve.",
	"Please write the right answer; it was a rite of passage.",
	"I will buy some milk by six.",
	"I want to be brave when I see a bee.",
	"My son loves sitting in the sun.",
	"The knight rode through the village at night.",
	"The flower is growing beside the bag of flour.",
	"We waited for an hour outside our house.",
	"She ate eight strawberries.",
	"The bear had bare patches of fur.",
	"He wants to sell his old phone because its cell battery is damaged.",
	"The bus fare is fair.",
	"The great chef cleaned the oven grate; you did a great job.",
	"My injured heel will eventually heal.",
	"The machine remained idle while the singer, my idol, performed.",
	"The male postman delivered the mail.",
	"The lion's mane was visible from the main road.",
	"I bought a pair of shoes and ate a pear.",
	"The plane flew over the plain, and I wrote it in plain English.",
	"The school principal explained the guiding principle.",
	"During the king's reign the rain was heavy, so he pulled the rein and gave the horse free rein.",
	"She rode her bicycle along the road.",
	"He played the main role and then ate a bread roll.",
	"The fabric is coarse but the training course is excellent.",
	"Wait in the queue until you receive your cue.",
	"The river current carried the boat past a currant bush.",
	"The car has dual airbags, while the story describes a duel.",
	"The author wrote a foreword before telling readers to look forward.",
	"The horse's gait changed when it reached the gate.",
	"My voice is hoarse after riding a horse.",
	"The miner suffered a minor injury.",
	"We reached the peak and took a quick peek below.",
	"He used the pedal to cycle while trying to peddle his products.",
	"The animals hunt their prey, while the people pray.",
	"The story is real and the line is on a reel.",
	"The tree's root grew across our chosen route.",
	"Farmers shear sheep, and by sheer luck none escaped.",
	"We visited the building site, saw an amazing sight, and learned how to cite sources.",
	"We booked a hotel suite and ordered a sweet dessert.",
	"The team worked hard and the river began to teem with fish.",
	"The company agreed to waive the fee, and I gave them a wave goodbye.",
	"In days of yore, people protected your family differently.",
	"We walked along the beach and saw a beech tree.",
	"The cat has sharp claws and the contract contains an important clause.",
	"I hope to earn enough money to buy an urn.",
	"He felt guilt after damaging the gilt frame.",
	"The hare has thick hair.",
	"We made a large haul and carried it through the hall.",
	"I gave the book to him after singing a hymn.",
	"The pipe has a leak, and I added a leek to the soup.",
	"The maid cleaned the meal I had made.",
	"Would you like to use an oar, or should we search for iron ore?",
	"Her face went pale when she dropped the pail.",
	"We heard the peal of bells while I peeled an orange.",
	"I need to rest after trying to wrest the door open.",
	"The situation became tense while we put up the tents.",
	"The boat was tied to the dock as the tide came in.",
	"The vain man noticed a vein while watching the weather vane.",
	"The whole wall has a large hole.",
	"I washed my clothes using several cleaning cloths.",
	"An eminent scientist warned that the danger was imminent.",
	"Her speech gave us insight but did not incite violence.",
	"The men arrived in the guise of tourists, and someone said hello to the guys.",
	"London is the capital of the UK.",
	"Exercise strengthens your muscles, while a pot of steamed mussels is seafood.",
	"The naval officer has a scar near his navel.",

	// The split-compound rules. Each of these is the reading that keeps a
	// pair of words apart, and each one cost a rule its guard.
	"My self-esteem took a knock.",
	"Your self-esteem matters too.",
	"It gave him self-confidence.",
	"We watched it self-destruct.",
	"Her self-control is remarkable.",
	"I like my true self better.",
	"Every body in the room turned around.",
	"That would be cause for concern.",
	"Interest is charged on the whole amount, be cause for celebration or not.",
	"We parked in side streets all week.",
	"It came with out-of-date firmware.",
	"We shipped it with out of date documentation.",
	"Send it to me to review before Friday.",
	"There is a part of this I still do not follow.",

	// Punctuation. Numbers are the trap that runs through all of it.
	"It cost 1,000 DCR at 3:00 on 3.5 percent.",
	"The file is at v1.2.3, not v1.2.4.",
	"The loop runs 0..10 in Rust.",

	// a/an. The first line is every family the "a" rule must not touch, the
	// second the same for "an", and both are correct writing that the rule
	// as usually stated -- "an before a vowel" -- would break.
	"It was a unique opportunity, a one-off, and a euro-denominated unit.",
	"A university course on a European utility is a useful thing once a year.",
	"We waited an hour for an honest answer from an heir.",
	"She has an MBA, an SMS alert and an X-ray booked.",
	"An unimportant detail took an uninteresting hour.",
	"That is an odd effect on an old idea.",
	"The plan is to close the door and to narrow the gap.",
	"No one knows the answer yet.",
	"No longer a problem.",
	"Yes and no, depending.",
	"However you do it, the result is the same.",
	"Similarly designed products failed the same way.",
	"For example sentences, see the appendix.",
	"Wait for it... there it is.",
	"She said, \"that works for me\".",
	"Therefore, we should wait.",
	"Meanwhile, the others kept going.",
	"I went but he stayed.",
}

// TestRulesDoNotFireOnCorrectText is the false-positive guard, and it is the
// most valuable test here. A wavy underline under correct writing is worse
// than a missed error, because it teaches people to stop reading the
// underlines at all.
//
// It covers the error rules. The suggestions are held to a different
// standard on purpose -- see the note at the top of rules_style.go.
//
// Rules using backreferences are skipped: they are written in Dart's dialect
// and Go's RE2 cannot compile them by design. Those are covered by the app's
// own tests, where they actually run.
func TestRulesDoNotFireOnCorrectText(t *testing.T) {
	skipped := 0
	for _, r := range Rules {
		// Errors only. A suggestion is an opinion about writing that is not
		// wrong -- that is what the severity means -- so holding one to this
		// standard would mean no sentence in the corpus below could contain
		// a cliche, a wordy phrase or a missing optional comma. The corpus
		// is meant to be ordinary writing, and ordinary writing contains all
		// three.
		if r.Severity == SeveritySuggestion {
			continue
		}
		// Checks likewise, and for a sharper reason: a check exists to fire
		// on writing that is probably correct. "He had to brake" is in this
		// corpus and a brake/break check that could be held to this standard
		// would be a rule the error tier could have carried already. What
		// keeps them honest instead is TestCheckRulesAskAQuestion, which
		// insists they ask rather than assert, and the antipatterns each one
		// carries for the readings that are settled.
		if r.Severity == SeverityCheck {
			continue
		}
		re, err := regexp.Compile(r.Pattern)
		if err != nil {
			// RE2 rejects it. That is expected for the constructs Dart has
			// and Go does not -- but only for those, so the reason is
			// checked rather than counted.
			if !usesDartOnlySyntax(r.Pattern) {
				t.Errorf("rule %q does not compile and uses nothing Dart-only: %v",
					r.Message, err)
			}
			skipped++
			continue
		}
		// The antipatterns are part of the rule, so they are part of the
		// test. Without this a rule that moved its guard out of the pattern
		// -- which is the point of having them -- would read as a new false
		// positive on text it has always handled correctly.
		var exceptions []*regexp.Regexp
		for _, source := range r.Antipatterns {
			anti, err := regexp.Compile(source)
			if err != nil {
				t.Errorf("rule %q: antipattern %q does not compile: %v",
					r.Message, source, err)
				continue
			}
			exceptions = append(exceptions, anti)
		}

		for _, text := range correctText {
			for _, at := range re.FindAllStringIndex(text, -1) {
				if suppressed(exceptions, text, at) {
					continue
				}
				t.Errorf("rule %q fired on correct text %q (matched %q)",
					r.Message, text, text[at[0]:at[1]])
			}
		}
	}
	// Every skip is accounted for above rather than counted here. A count
	// was a magic number that had to be raised each time a lookaround rule
	// was added, and raising it is exactly the moment nobody checks what
	// else slipped past -- a pattern with a genuine typo in it would have
	// been waved through as one more expected skip.
	t.Logf("%d of %d rules are beyond RE2 and are covered app-side, where "+
		"they run", skipped, len(Rules))
}

// suppressed reports whether an antipattern covers the match at [start,end).
//
// Contained, not merely overlapping: an antipattern describes a longer
// reading that the match is part of -- "my self" inside "my self-esteem" --
// so a pattern that happens to clip the edge of one is not that reading.
func suppressed(exceptions []*regexp.Regexp, text string, at []int) bool {
	for _, anti := range exceptions {
		for _, e := range anti.FindAllStringIndex(text, -1) {
			if e[0] <= at[0] && e[1] >= at[1] {
				return true
			}
		}
	}
	return false
}

// dartOnlySyntax is the constructs Dart's regex engine has and Go's RE2 does
// not, by design: RE2 guarantees linear time and neither can be done in it.
var dartOnlySyntax = regexp.MustCompile(`\(\?<?[=!]|\\[1-9]`)

func usesDartOnlySyntax(pattern string) bool {
	return dartOnlySyntax.MatchString(pattern)
}

// TestRulesCatchTheirOwnMistake is gone, and TestRuleExamples replaced it.
//
// It paired rules with text by *message*, in a map, and messages are not
// unique: eight rules say `Should be "$1 effect"` and a map keeps one of
// them. So it silently covered a fraction of what it appeared to, and the
// fraction shrank every time a rule was added. Examples live on the rule
// now, so every rule is covered exactly once and by construction.

// categories is the closed set the app groups rules by. Adding one is a
// deliberate act -- the popup heading it appears under is written to match --
// so a typo in an existing name must not quietly create a new group.
var categories = map[string]bool{
	"Spacing":        true,
	"Punctuation":    true,
	"Capitalization": true,
	"Grammar":        true,
	"Confused words": true,
	"Style":          true,
	"Repetition":     true,
	"Readability":    true,
	"Consistency":    true,
	// The checks -- see rules_checks.go. A heading of its own rather than
	// "Confused words", which the error rules use: those two rows say
	// different things and the row is where the reader learns which.
	"Possible confusion": true,
	"Redundancy":         true,
	"Inclusive language": true,
	"Typography":         true,
}

// TestRulesAreExplained guards the thing a new rule is likeliest to be
// missing. A rule without an explanation still works -- the app falls back to
// the message alone -- so nothing breaks visibly, and the gap survives.
func TestRulesAreExplained(t *testing.T) {
	for i, r := range Rules {
		if !categories[r.Category] {
			t.Errorf("Rules[%d] (%q): category %q is not one of the known groups",
				i, r.Message, r.Category)
		}
		if r.Explanation == "" {
			t.Errorf("Rules[%d] (%q) has no explanation", i, r.Message)
			continue
		}
		if !strings.HasSuffix(r.Explanation, ".") {
			t.Errorf("Rules[%d] (%q): explanation is not a sentence: %q",
				i, r.Message, r.Explanation)
		}
		// An explanation no longer than the message is repeating it rather
		// than explaining it, which is worse than none: it takes up the space
		// where the reader expected to learn something.
		if len(r.Explanation) <= len(r.Message) {
			t.Errorf("Rules[%d] (%q): explanation adds nothing: %q",
				i, r.Message, r.Explanation)
		}
	}
}

// Rules sharing a message must at least agree on which group they belong to.
//
// Only the category, not the explanation. Explanations were once required to
// match as well, on the reasoning that two rules saying the same thing should
// say it the same way -- but the generated style rules quote the phrase they
// caught ("\"in regard to\" can usually be shortened to \"about\""), which is
// more use than a shared sentence would be. A category that disagrees is
// still a mistake: it decides which page the issue is listed on.
func TestSharedMessagesShareTheirCategory(t *testing.T) {
	seen := map[string]string{}
	for i, r := range Rules {
		if was, ok := seen[r.Message]; ok && was != r.Category {
			t.Errorf("Rules[%d] (%q) is in category %q, but an earlier rule "+
				"with the same message is in %q", i, r.Message, r.Category, was)
		}
		seen[r.Message] = r.Category
	}
}

// TestAntipatternsAreReachable: every antipattern must match one of its own
// rule's Leaves examples.
//
// An exception that matches nothing is one nobody notices has stopped
// working: the rule simply gets noisier, and the only evidence is a false
// positive somebody has to report. This is the check a negative lookahead
// could never have -- glued onto the end of a pattern, there is nothing to
// test on its own.
//
// Against the rule's own examples rather than the shared corpus, which is
// where this started. The corpus answers a different question -- does any
// rule fire on ordinary writing -- and making it carry a sentence for every
// exception in the plugin turned it into a list whose reason for each line
// lived somewhere else. It also subsumes the separate "every antipattern has
// a reason" check: a rule with antipatterns and no Leaves now fails here, by
// name.
func TestAntipatternsAreReachable(t *testing.T) {
	for i, r := range Rules {
		for _, source := range r.Antipatterns {
			anti, err := regexp.Compile(source)
			if err != nil {
				t.Errorf("Rules[%d] (%q): antipattern %q does not compile: %v",
					i, r.Message, source, err)
				continue
			}
			var matched bool
			for _, text := range r.Leaves {
				if anti.MatchString(text) {
					matched = true
					break
				}
			}
			if !matched {
				t.Errorf("Rules[%d] (%q): antipattern %q matches none of the "+
					"rule's own Leaves examples -- add the reading it is for, "+
					"or the exception is dead", i, r.Message, source)
			}
		}
	}
}

// TestCheckRulesAskAQuestion holds the check tier to the terms it was allowed
// in on.
//
// A check is permitted to be wrong about the writing, which is a licence no
// other rule in this package has. What it is not permitted to do is spend
// that licence as though it were an error: a rule that fires on correct text
// and says "Should be \"break\"" is worse than the silence it replaced,
// because the reader who had it right is now being corrected by a rule that
// does not know. The question mark is the whole bargain, so it is checked
// rather than trusted to review.
// checkCategories are the headings a check may carry. "Possible confusion" is
// the tier's own and belongs to nothing else; "Punctuation" is shared with the
// mechanical comma rules on purpose, because a reader meets both in the same
// place and the heading is what says so. The severity, not the category, is
// what decides which page an issue is listed on.
var checkCategories = map[string]bool{
	"Possible confusion": true,
	"Punctuation":        true,
}

func TestCheckRulesAskAQuestion(t *testing.T) {
	for i, r := range Rules {
		if r.Severity != SeverityCheck {
			// The converse: nothing outside the tier may borrow its
			// category, or the amber rows and the red ones would be
			// indistinguishable in the one place they are read together.
			if r.Category == "Possible confusion" {
				t.Errorf("Rules[%d] (%q) is in \"Possible confusion\" but is "+
					"not a check", i, r.Message)
			}
			continue
		}
		if !strings.HasSuffix(r.Message, "?") {
			t.Errorf("Rules[%d]: a check must ask, not assert: %q", i, r.Message)
		}
		if r.Suggest == "" {
			t.Errorf("Rules[%d] (%q): a check must offer the other reading",
				i, r.Message)
		}
		if !checkCategories[r.Category] {
			t.Errorf("Rules[%d] (%q): a check belongs in one of %v, not %q",
				i, r.Message, checkCategories, r.Category)
		}
		// A rule matching one bare word fires on every use of it, and the
		// tier is only tolerable while it fires on positions.
		if len(r.Antipatterns) == 0 {
			t.Errorf("Rules[%d] (%q): a check carries the readings it must "+
				"not fire on, and this one has none", i, r.Message)
		}
	}
}

// TestChecksDoNotRepeatTheErrorRules: no check may fire on text an error rule
// already catches.
//
// The two tiers are painted in different colours and listed on different
// pages, so a pair covered by both is reported twice, in two places, saying
// the same thing -- once as a correction and once as a question about the
// correction. Worse, it is the error rules that would look unreliable: a
// reader shown "Should be \"break\"" and "Did you mean \"break\"?" about the
// same three words learns that the tools are arguing with themselves.
//
// This is the boundary that will actually erode. The checks are being written
// pair by pair over ground the error rules already partly cover, and the
// natural mistake is to write a check for a position that was decidable all
// along.
func TestChecksDoNotRepeatTheErrorRules(t *testing.T) {
	type compiled struct {
		rule       GrammarRule
		re         *regexp.Regexp
		exceptions []*regexp.Regexp
	}
	var errors []compiled
	for _, r := range Rules {
		if r.Severity != "" {
			continue
		}
		re, err := regexp.Compile(r.Pattern)
		if err != nil {
			continue // Dart-only syntax; covered app-side.
		}
		c := compiled{rule: r, re: re}
		for _, source := range r.Antipatterns {
			if anti, err := regexp.Compile(source); err == nil {
				c.exceptions = append(c.exceptions, anti)
			}
		}
		errors = append(errors, c)
	}

	for i, r := range Rules {
		if r.Severity != SeverityCheck {
			continue
		}
		for _, text := range r.Flags {
			for _, e := range errors {
				for _, at := range e.re.FindAllStringIndex(text, -1) {
					if suppressed(e.exceptions, text, at) {
						continue
					}
					t.Errorf("Rules[%d] (%q) asks about %q, which the error "+
						"rule %q already corrects -- the position was "+
						"decidable, so fix the check or drop it",
						i, r.Message, text, e.rule.Message)
				}
			}
		}
	}
}

// TestPhraseTablesAreDisjoint: no phrase may appear in two of the tables the
// suggestion rules are generated from.
//
// Four tables now produce a rule per row -- wordiness, redundancy, clichés and
// the inclusive terms -- and they are edited separately, by whoever is adding
// to the one in front of them. A phrase in two of them is reported twice with
// two different headings and two different fixes, and the reader has no way to
// tell which of the two the tools actually believe.
//
// This is the check that would have caught the split itself going wrong: the
// redundancy rows were moved out of the wordiness table, and a copy left
// behind would have looked exactly like a normal day's work.
func TestPhraseTablesAreDisjoint(t *testing.T) {
	tables := map[string][][2]string{
		"wordy":     wordy,
		"redundant": redundant,
		"gendered":  gendered,
	}
	seen := map[string]string{}
	for name, table := range tables {
		for _, pair := range table {
			phrase := strings.ToLower(pair[0])
			if was, ok := seen[phrase]; ok {
				t.Errorf("%q is in both %s and %s", pair[0], was, name)
			}
			seen[phrase] = name
		}
	}
	for _, pair := range cliches {
		phrase := strings.ToLower(pair[0])
		if was, ok := seen[phrase]; ok {
			t.Errorf("%q is in both %s and cliches", pair[0], was)
		}
		seen[phrase] = "cliches"
	}
}

func TestRuleExamples(t *testing.T) {
	for i, r := range Rules {
		if len(r.Flags) == 0 {
			t.Errorf("Rules[%d] (%q) carries no example of what it catches",
				i, r.Message)
		}

		re, err := regexp.Compile(r.Pattern)
		if err != nil {
			// One of the handful Dart has constructs for and RE2 does not.
			// Its examples cannot run here; those rules are exercised
			// individually in the app's own tests, where they do run.
			if !usesDartOnlySyntax(r.Pattern) {
				t.Errorf("Rules[%d] (%q) does not compile: %v", i, r.Message, err)
			}
			continue
		}

		var exceptions []*regexp.Regexp
		for _, source := range r.Antipatterns {
			anti, err := regexp.Compile(source)
			if err != nil {
				t.Errorf("Rules[%d] (%q): antipattern %q does not compile: %v",
					i, r.Message, source, err)
				continue
			}
			exceptions = append(exceptions, anti)
		}

		// fires reports whether the rule, exceptions and all, has anything
		// to say about text -- which is what the app will do with it.
		fires := func(text string) bool {
			for _, at := range re.FindAllStringIndex(text, -1) {
				if !suppressed(exceptions, text, at) {
					return true
				}
			}
			return false
		}

		for _, text := range r.Flags {
			if !fires(text) {
				t.Errorf("Rules[%d] (%q) does not catch %q, which it is for",
					i, r.Message, text)
			}
		}
		for _, text := range r.Leaves {
			if fires(text) {
				t.Errorf("Rules[%d] (%q) fires on %q, which it must not",
					i, r.Message, text)
			}
		}
	}
}

// expandSuggestion fills a rule's Suggest template from a match, the way the
// app does: $1..$9 are the capture groups and $U1..$U9 are the same groups
// with the first letter capitalised.
func expandSuggestion(template, text string, at []int) string {
	var out strings.Builder
	for i := 0; i < len(template); i++ {
		if template[i] != '$' || i+1 >= len(template) {
			out.WriteByte(template[i])
			continue
		}
		upper := template[i+1] == 'U'
		digit := i + 1
		if upper {
			digit = i + 2
		}
		if digit >= len(template) || template[digit] < '1' || template[digit] > '9' {
			out.WriteByte(template[i])
			continue
		}
		n := int(template[digit] - '0')
		group := ""
		if 2*n+1 < len(at) && at[2*n] >= 0 {
			group = text[at[2*n]:at[2*n+1]]
		}
		if upper && group != "" {
			group = strings.ToUpper(group[:1]) + group[1:]
		}
		out.WriteString(group)
		i = digit
	}
	return out.String()
}

// TestRuleFixesResolveTheRule applies each rule's own suggestion to each of
// its examples and checks the rule then has nothing left to say.
//
// A fix that does not fix is the most embarrassing thing a checker can do,
// and it is invisible to every other test here: the rule fires on the wrong
// text, which is all the examples ask of it, and then offers a replacement
// that is just as wrong. Two of these shipped. "a affect" was corrected to
// "a effect" because the rule carried the determiner through untouched, and
// a blanket case-folding once left the weekday rules asking for a capital on
// "Tuesday", which already had one.
//
// The rules that legitimately have no fix -- the cliches and the passive,
// where the replacement depends on what the sentence is trying to say -- are
// skipped rather than exempted, because they carry no suggestion at all.
func TestRuleFixesResolveTheRule(t *testing.T) {
	for i, r := range Rules {
		if r.Suggest == "" {
			continue
		}
		re, err := regexp.Compile(r.Pattern)
		if err != nil {
			continue // Dart-only; covered app-side.
		}
		// Every answer the rule offers, not only the first. An alternative
		// that leaves the rule still firing is the same embarrassment as a
		// Suggest that does: the reader presses it, the mark stays, and the
		// tools look broken.
		answers := append([]string{r.Suggest}, r.Alternatives...)
		var exceptions []*regexp.Regexp
		for _, source := range r.Antipatterns {
			if anti, err := regexp.Compile(source); err == nil {
				exceptions = append(exceptions, anti)
			}
		}

		for _, text := range r.Flags {
			at := re.FindStringSubmatchIndex(text)
			if at == nil || suppressed(exceptions, text, at[:2]) {
				continue // TestRuleExamples already reports this.
			}
			for _, answer := range answers {
				replacement := expandSuggestion(answer, text, at)
				fixed := text[:at[0]] + replacement + text[at[1]:]
				if fixed == text {
					t.Errorf("Rules[%d] (%q): the fix %q for %q changes nothing",
						i, r.Message, answer, text)
					continue
				}
				// Only what was replaced is the fix's business. An example is
				// allowed to carry a second fault of the same kind -- "she
				// speaks french and german" does -- and the rule firing again
				// further along is it working, not failing.
				from, to := at[0], at[0]+len(replacement)
				for _, still := range re.FindAllStringIndex(fixed, -1) {
					if still[0] < to && still[1] > from &&
						!suppressed(exceptions, fixed, still) {
						t.Errorf("Rules[%d] (%q): fixing %q with %q gives %q, "+
							"which the rule still fires on",
							i, r.Message, text, answer, fixed)
						break
					}
				}
			}
		}
	}
}

// leadingAlternation returns the words of a pattern's opening `\b(a|b|c)`
// group, or nil if it does not open with one.
func leadingAlternation(pattern string) []string {
	const prefix = `\b(`
	if !strings.HasPrefix(pattern, prefix) {
		return nil
	}
	end := strings.IndexByte(pattern, ')')
	if end < 0 {
		return nil
	}
	return strings.Split(pattern[len(prefix):end], "|")
}

// TestLeadingWordsAcceptEitherCase is the guard for the bug that made every
// literal rule miss the start of a sentence.
//
// "Dont", "Cant", "Alot", "Thats" and "Your welcome" were all sailing
// through, which is precisely where those mistakes are typed. The fix was a
// pass over every rule folding the first letter of its leading word, and the
// pass had a hole: it read one backtick literal at a time, so a pattern built
// by concatenating several -- which is how the long alternations are written
// -- kept its first line folded and its continuation lines lowercase. Two
// rules sat half-converted afterwards and nothing said so.
//
// This asks the question directly of the finished pattern instead.
func TestLeadingWordsAcceptEitherCase(t *testing.T) {
	for i, r := range Rules {
		// The capitalisation rules are the exception, and they are the whole
		// exception: each exists to find the lowercase spelling, so accepting
		// a capital would make it fire on the form it is asking for.
		if r.Category == "Capitalization" {
			continue
		}
		for _, word := range leadingAlternation(r.Pattern) {
			first := rune(word[0])
			if !unicode.IsLower(first) {
				continue
			}
			t.Errorf("Rules[%d] (%q): leading alternative %q is lower-case "+
				"only, so the rule cannot fire at the start of a sentence",
				i, r.Message, word)
		}
	}
}
