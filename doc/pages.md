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

A banner across the top of a page:

```
--header[220]--
background: --embed[type=image/png,data=...]--
left: ![](logo)
right: # My site
description: What the site is for.
nav: --include[navigation]--
navat: bottom
--/header--
```

Every field is optional — one with only a background is a banner, one with
only a title is a masthead. The number is the tallest it may be; without one
the reader's theme decides.

The three slots run left, middle and right. A slot on its own takes the whole
width and sits where its name says. Otherwise each takes a column and the last
one absorbs whatever is left at the end — so a logo on the left and a title in
the middle gives the title the right-hand space too, while a logo left and a
title right keeps the gap between them.

The three give three distances from the logo: `middle` sits beside it,
`right` against the far edge, and a `middle` with nothing to its left is
centred in the banner.

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

A bar is usually written once as a fragment and included wherever it is
wanted, which is what `nav:` above is doing.

### Other markup

Pages use the same Markdown extensions posts do — `--embed[...]--` for
images and file downloads, `--columns--`, `--cards--`, `--grid--` — plus two
of their own: `--form--` for something the reader answers, and
`--section id=x --` for the region an answer is written into.
