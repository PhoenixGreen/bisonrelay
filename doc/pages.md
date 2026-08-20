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
in `partials/` and referred to by name:

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

Substitution is a single pass. A fragment that refers to another, or to
itself, is left as written rather than expanded further.

Note that this is a different mechanism from the `{{...}}` templates a
[simple store](simplestore.md) uses. Those are Go templates, expanded by the
serving side before anything is sent, and have access to the store's data;
`--include[...]--` survives being sent and is filled in by the reader. Both
may appear in one site.

### Other markup

Pages use the same Markdown extensions posts do — `--embed[...]--` for
images and file downloads, `--columns--`, `--cards--`, `--grid--` — plus two
of their own: `--form--` for something the reader answers, and
`--section id=x --` for the region an answer is written into.
