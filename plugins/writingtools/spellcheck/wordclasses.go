package spellcheck

// wordclasses.go holds the named lists of words the rules over words refer
// to as `{name}`.

// WordClasses are the named lists a rule refers to as `{name}`.
//
// Lists rather than tags because each is a fact about particular words that
// no part of speech carries: "team" and "dog" are both singular nouns, and
// only one of them can take "are".
var WordClasses = map[string][]string{
	// The pronouns that take the -s form of a verb, and the ones that do not.
	"he":   {"he", "she", "it"},
	"they": {"i", "you", "we", "they"},
	"subj": {"i", "you", "he", "she", "it", "we", "they"},

	// Everything that is one person or thing and can stand as a subject on
	// its own, for the exceptions about what came before one.
	"singular": {"i", "he", "she", "it", "everyone", "everybody", "someone",
		"somebody", "anyone", "anybody", "nobody", "everything", "something",
		"nothing", "anything"},

	"modal": {"can", "could", "will", "would", "shall", "should", "may",
		"might", "must", "can't", "cannot", "couldn't", "won't", "wouldn't",
		"shouldn't", "mustn't"},

	// Singular in form and plural in sense, or the head of "a ___ of them":
	// the nouns "are" and "have" follow without complaint.
	"collective": {"team", "staff", "family", "government", "committee",
		"company", "band", "group", "crowd", "public", "audience", "majority",
		"minority", "class", "crew", "couple", "pair", "press", "jury",
		"enemy", "council", "board", "club", "community", "generation",
		"party", "army", "navy", "faculty", "personnel", "clergy", "youth",
		"rest", "remainder", "bulk", "lot", "number", "handful", "bunch",
		"variety", "range", "total", "quarter", "third", "half", "percent",
		"part", "portion", "proportion", "fraction", "host", "series", "set",
		"dozen", "plenty", "multitude", "plethora", "wealth", "myriad",
		"slew", "array", "collection", "population", "selection", "string",
		"wave", "kind", "sort", "type", "cast", "gang", "squad", "side",
		"management", "opposition", "department", "ministry", "firm",
		"data", "media", "none", "all", "following", "latter", "former",
		"other", "same", "percentage", "amount", "flock", "herd", "choir",
		"orchestra", "congregation", "household", "nation", "tribe",
		"union", "league", "panel", "cabinet", "bank", "store", "school",
		"church", "university", "college", "police", "people"},

	// Nouns whose plural is their singular, and the number words that stay
	// as they are after another number.
	"invariant": {"fish", "sheep", "deer", "aircraft", "series", "species",
		"staff", "offspring", "cattle", "people", "police", "data", "media",
		"dozen", "hundred", "thousand", "million", "billion", "trillion",
		"percent", "swine", "moose", "salmon", "trout", "cod", "shrimp",
		"bison", "spacecraft", "hovercraft", "headquarters", "means",
		"crossroads", "personnel", "youth", "folk", "clergy", "vermin",
		"foot", "stone", "pence", "yen", "per", "plus", "minus", "times",
		"point", "pm", "am", "kg", "km", "cm", "mm", "ml", "mph", "gb",
		"mb", "kb", "tb", "hz", "khz", "mhz", "ghz", "kw", "mw", "ft",
		"oz", "lb", "lbs", "min", "sec", "hr", "hrs", "yr", "bn", "mn",
		"quid", "grand", "score", "something", "anything", "nothing",
		"everything", "one", "more", "less", "o'clock"},

	// What a number can be the label of rather than the count of: "page 2
	// section" is not "two section".
	"numbered": {"page", "chapter", "section", "step", "figure", "fig",
		"table", "level", "phase", "type", "class", "room", "gate",
		"platform", "line", "version", "part", "number", "no", "item",
		"volume", "act", "scene", "round", "stage", "grade", "year", "day",
		"week", "season", "episode", "series", "size", "route", "rule",
		"lane", "zone", "group", "unit", "model", "option", "question",
		"exercise", "appendix", "article", "clause", "note", "point",
		"top", "world", "formula", "category", "tier", "since", "in",
		"by", "of", "from", "until", "on", "at", "to", "for", "and"},

	// Nouns that are never counted, so never take "a" or a plural.
	"uncountable": {"advice", "information", "furniture", "equipment",
		"luggage", "baggage", "homework", "evidence", "feedback", "software",
		"hardware", "traffic", "news", "progress", "money", "weather",
		"music", "luck", "rubbish", "garbage", "jewelry", "jewellery",
		"machinery", "scenery", "stuff"},

	// Verbs that take "to" and a base verb after them.
	"wantto": {"want", "wants", "wanted", "need", "needs", "needed", "like",
		"likes", "liked", "love", "loves", "loved", "hate", "hates", "hated",
		"try", "tries", "tried", "trying", "decide", "decides", "decided",
		"hope", "hopes", "hoped", "plan", "plans", "planned", "learn",
		"learned", "learnt", "able", "unable", "ought", "have", "has", "had",
		"wish", "wished", "manage", "managed", "refuse", "refused", "going",
		"supposed", "allowed", "expect", "expected", "tend", "tends"},

	// Participles that cannot stand without "have" or "be" before them.
	"participle": {"seen", "gone", "taken", "given", "written", "eaten",
		"known", "shown", "spoken", "chosen", "driven", "fallen", "forgotten",
		"grown", "ridden", "risen", "stolen", "sworn", "thrown", "begun",
		"swum", "sung", "rung", "done"},

	// Adjectives short enough to compare with -er and -est.
	"shortadj": {"big", "small", "tall", "short", "old", "young", "fast",
		"slow", "cheap", "rich", "poor", "smart", "easy", "happy", "busy",
		"angry", "pretty", "early", "cold", "hot", "warm", "cool", "nice",
		"large", "strong", "weak", "clean", "dirty", "dark", "thin", "fat",
		"thick", "wide", "deep", "quick", "loud", "safe", "kind", "sad",
		"high", "low", "hard", "soft", "long", "great", "near", "late",
		"heavy", "funny", "lucky", "simple", "close", "new", "bright",
		"tough", "rough", "smooth", "sweet", "fresh", "wet", "dry"},

	// Verbs for what somebody is doing, which after "is" want -ing.
	"action": {"work", "play", "live", "study", "stay", "wait", "look",
		"talk", "walk", "run", "sit", "stand", "sleep", "read", "write",
		"cook", "eat", "drink", "travel", "go", "come", "watch", "listen",
		"learn", "try", "help", "move", "drive", "swim", "shop", "teach",
		"speak", "visit", "use", "make", "do", "take", "get", "buy",
		"sell", "build", "plan", "think", "feel", "enjoy", "start"},

	"weekday": {"monday", "tuesday", "wednesday", "thursday", "friday",
		"saturday", "sunday"},
	"month": {"january", "february", "march", "april", "may", "june",
		"july", "august", "september", "october", "november", "december"},
	"language": {"english", "french", "german", "spanish", "italian",
		"chinese", "japanese", "russian", "arabic", "portuguese", "dutch",
		"greek", "polish", "turkish", "korean", "hindi"},
}
