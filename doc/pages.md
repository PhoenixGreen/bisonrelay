Pages
===

A Bison Relay client can serve pages to the people it is connected to. They
are Markdown files in one directory, fetched on request over the same
encrypted transport as everything else — there is no server, and nothing is
uploaded anywhere. A page can only be read while the client serving it is
online.

### Enabling

```
[resources]
upstream = pages:/home/user/.brclient/pages
```

In bruig this is Pages > My Site, which writes the same setting.

`index.md` is the front page: it is what a visitor's client asks for when
they open somebody's site, so a site without one cannot be entered.

### Linking

A link with no scheme is a page of the same site:

```
[About](about.md)
```

`br://<user id>/<path>` reaches somebody else's site, which is how one site
links to another.

Page names should avoid spaces. A space ends a Markdown link, so
`[x](Test Page.md)` links to `Test` and leaves `Page.md)` as text — bruig
publishes pages under a lowercased, underscored name for this reason.

### Shared fragments

A fragment several pages share — a header, a navigation bar — is written once
in `partials/` and referred to by name. In bruig it is written in
**Writing > My Posts > Partials**, or made with the "New fragment" button in
Pages > My Site, and published like a page:

```
partials/navigation.md      one file
--include[navigation]--     in any page
```

The fragment is **not** expanded into the page before it is sent. It travels
alongside the first page that refers to it, in a single reply, and the
reader's client keeps it and fills in every later page itself. A navigation
bar on twenty pages therefore crosses the wire once rather than twenty times,
and each subsequent page costs one round trip carrying only its own text.

Requests say which fragments the asking client already holds, so the serving
side leaves those out. A client that does not send that list simply receives
them again: it costs bandwidth and breaks nothing.

A fragment may refer to another — a header holding a navigation bar is the
ordinary case:

```
partials/navigation.md      [Home](index.md) · [About](about.md)
partials/header.md          # My site
                            --include[navigation]--
index.md                    --include[header]--
```

Everything a page reaches is sent with it, so the nesting costs no extra
round trips. A fragment that refers to itself, or two that refer to each
other, are left as written rather than expanded — the marker stays visible,
which is what says a cycle has been made.

Note that this is a different mechanism from the `{{...}}` templates a
[simple store](simplestore.md) uses. Those are Go templates, expanded by the
serving side before anything is sent, and have access to the store's data;
`--include[...]--` survives being sent and is filled in by the reader. Both
may appear in one site.

### Headers and navigation

A banner across the top of a page is rows, and a row is one or two cells:

```
--header--
background: --embed[type=image/png,data=...]--
--row[96,split]--
left: ![](logo)
right: # My site
--/row--
--row[44,center]--
--include[navigation]--
--/row--
--/header--
```

At most two rows of at most two cells. Every shape people build — a logo
beside a title, a bar of links under them — fits in that, and every shape past
it is one that has to be made to work at a width its author never saw.

A row's marker carries its height and how it divides. `split` puts two cells
at opposite edges with the slack between them. `left`, `center` and `right`
place one cell, or two sitting together a fixed gap apart — which is a logo
and the title beside it, the one shape `split` cannot make. In `left` the
second cell takes whatever the first leaves, so a title runs to the far edge
rather than stopping halfway. **The height is
fixed and everything in the row is sized to it** — a logo is as tall as its
row, a title is set to its row — so a banner resizes without anything in it
changing height.

The heights are what the banner is drawn at in a window wide enough for it.
In a narrower one **the whole banner scales down together** — its rows, and
the writing and pictures sized from them — so it keeps its proportions instead
of the title absorbing the whole difference on its own. Only ever down, and
only so far; both limits are in Settings > Appearance > Markdown > Header and
navigation.

A title too long for its row is **condensed rather than shrunk**: the letters
squeeze and the cap height stays, so the row still looks its height. Past
about two-thirds it stops being readable and is cut with an ellipsis instead.

A bar of links is a fragment in a row, with nothing special about it — which
is what the `--include[navigation]--` above is.

A title can be set apart from the rest of the page — it is the one piece of a
site whose look belongs to whoever wrote it:

```
titlesize: 48          leave it out and the row's height decides
titleweight: bold
titleitalic: yes
titlecase: upper       changes the words, so what is copied is what is shown
titletracking: 3       letter spacing
titlecolor: #ffcc00
titlegradient: #f00,#00f       colours across the words
titleimage: --embed[...]--     a picture inside the words
titleoutline: 2                a line round the letters
titleoutlinecolor: #ffffff
titleoutlinegradient: #f00,#00f
titlebackground: #00000080     #rrggbbaa, so it can be see-through
titleborder: 2                 a box round the whole title, not the letters
titlebordercolor: #ffffff
titleradius: 8
titlepadding: 12
```

Heading marks in a cell are dropped: how large a title is set is its row, not
how many hashes were typed.

A bar of links, one link a line:

```
--nav[pills]--
[Home](index.md)
[About](about.md)
--/nav--
```

`plain`, `pills`, `underline` or `boxed`. The writer picks the shape, because
it is part of how the page is laid out; what each shape looks like is the
reader's, through Settings > Appearance > Markdown > Header and navigation and
the colours they read in.

### Other markup

Pages use the same Markdown extensions posts do — `--embed[...]--` for
images and file downloads, `--columns--`, `--cards--`, `--grid--` — plus two
of their own: `--form--` for something the reader answers, and
`--section id=x --` for the region an answer is written into.
