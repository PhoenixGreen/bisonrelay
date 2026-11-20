# Drawn characters

`drawn_styles.json.gz` holds four character styles for the Stock panel's
"Drawn characters": each style's parts (heads, faces, hair, clothes and so
on) as SVG with placeholders for colours and other parts, and the choices
each part offers. Characters are put together from them on this computer;
nothing is fetched.

The parts come from the DiceBear avatar library (https://www.dicebear.com),
version 9.4.2 of its packages @dicebear/open-peeps, @dicebear/notionists,
@dicebear/lorelei and @dicebear/pixel-art, turned into plain data.

## The drawings: CC0 1.0

All four styles' designs are dedicated to the public domain under CC0 1.0
(https://creativecommons.org/publicdomain/zero/1.0/):

- Open Peeps, by Pablo Stanley (https://www.openpeeps.com/)
- Notionists, by Zoish (https://bio.link/heyzoish)
- Lorelei, by Lisa Wischofsky (https://www.instagram.com/lischi_art/)
- Pixel Art, by DiceBear (https://www.dicebear.com)

## DiceBear's code: MIT

The parts were taken from files the DiceBear packages generate, which are
under this licence:

MIT License

Copyright (c) 2024 Florian Körner

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Format

gzip of JSON: an object of styles by name, each with title, creator,
source, license, viewBox, shapeRendering, body, parts ({group: {variant:
template}}) and defaults (the style's own option defaults: each group's
choices, each colour's choices as "<name>Color", and "<group>Probability"
as a percentage). In a template, {{c:name}} is a colour and {{p:group}} a
part. Made by a converter that refuses any template it does not wholly
understand.
