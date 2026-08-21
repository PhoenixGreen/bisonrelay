Simple Store
===

### Enable the store

To setup a simple store, a few configuration options need to be set.

To enable the simplestore, edit the configuration file to match:

```
[resources]
upstream = simplestore:/home/user/.brclient/store
```

To disable the store, just comment out the `upstream` line above.

To serve a store *and* a [pages site](pages.md) at the same time, set the
store's directory separately instead:

```
[resources]
upstream = pages:/home/user/.brclient/pages
storepath = /home/user/.brclient/store
```

The store then keeps all of its own paths and its front page moves to
`/store`, leaving the site's `index.md` as what visitors land on.

Next, the payment type needs to be set.  The options are `ln`, `onchain`, or
it can be left empty for manual charging.  If using `onchain`, an optional
account may be set to receive funds:

```
[simplestore]
paytype=ln
;account=store
```

### Configuration

Once the store has been enabled in the configuration file, a store
template will be installed into the path specified in the `upstream`
line above.

#### Store Front
First, edit `index.tmpl` to introduce your store front.

#### Products
In the `products/` directory you will find example product template files.
They should be edited to fit your store.  These files can contain multiple
products or can be split into multiple files.  Deleting a file removes all
products within that file from your store.

An example product might be:

```
[[products]]
title = "My guitar solo"
sku = "1209391282"
description = """An MP3 file of my guitar solo"""
tags = ["music", "mp3", "guitar"]
price = 0.99
sendfilename = "guitar_solo.mp3"
```

In the above example, `guitar_solo.mp3` should be located in the defined
`upstream` directory.

### Managing the store

In the app, the Pages section's Store tab sets up a store, edits the
catalogue, and works through the order book. Products written there land in
`products/` as the same TOML shown above, and the running store picks them up
without a restart.

### Viewing
To see your store within `brclient`, run the command `/pages local`.

Within the app, use Pages > My Site > View my site. The seller's own view of
the order book is also served as pages, at `/admin/orders`.

### A note on what customers write

A store's pages are Go `text/template`, which does not escape, and what comes
out of them is Markdown read by the other party in their own client. So the
names, addresses and comments a customer types are stripped of Bison Relay's
page markup as they arrive: runs of hyphens collapse to one, which disarms
`--embed[…]--`, `--form--`, `--include[…]--` and every other marker, since all
of them open with two.

Nothing there could ever execute — the renderer draws, it does not run. What
it prevents is a customer putting a form, or a file download, in front of the
seller on the seller's own order page, where it reads as the store's own
because it is. Comments are escaped in both directions, since a seller's
comment is read by the customer on theirs.
