Pages
===

A page is a markdown document one client serves to another over the same
encrypted transport everything else travels on. There is no server in the
middle and no copy anywhere else: a site is readable by the people its author
is already connected to, and only while the author's client is reachable.

### The protocol

A request is an `RMFetchResource` -- a path, optional metadata, and an
optional JSON body -- and the answer is an `RMFetchResourceReply` carrying a
status and the page. The statuses are deliberately HTTP-shaped:

| Status | Meaning |
| --- | --- |
| 200 | Here is the page. |
| 400 | The request made no sense. |
| 404 | Hosting, but nothing at that path. |
| 501 | Not hosting anything at all. |

The 404/501 distinction is what lets a visitor tell "this user has no site"
from "this user has no such page". A client that serves nothing still answers,
at the cost of one message: without a reply there is no way to tell it apart
from being offline, and the request simply waits in the send queue.

Note that no status means "offline". Bison Relay has no presence, by design --
a request to someone unreachable stays queued and is delivered whenever they
next connect.

### Hosting from the app

Settings live in the Pages section: **My Site** switches hosting on, chooses
the directory, and edits the markdown. Changes take effect immediately and are
written back to the config file.

### Hosting from the config file

```
[resources]
upstream = pages:~/.brclient/pages
```

The directory is served as-is. `index.md` is the front page -- it is what the
app requests when someone opens your site.

Pages may link to each other with a plain relative path, and to *another
user's* site with an absolute one:

```
[About me](about.md)
[Their front page](br://<their public id>/index.md)
```

Markdown embeds work the same as they do in posts, including images and
download links to shared files.

### A site and a store together

A [simple store](simplestore.md) can be served alongside a pages site:

```
[resources]
upstream = pages:~/.brclient/pages
storepath = ~/.brclient/store
```

The store keeps its own paths (`/cart`, `/orders`, `/admin` and so on) and its
front page moves to `/store`, leaving the root index to the pages site. Store
templates that link to absolute paths keep working unchanged.

With `storepath` alone and no `upstream`, the store takes the root, which is
what `upstream = simplestore:...` has always done.

### Other upstreams

`upstream` also accepts an `http://`/`https://` base URL, which proxies
requests to a web server, and `clientrpc`, which hands them to a client
connected over the RPC interface. Neither is editable from the app, since the
app is not the thing serving.
