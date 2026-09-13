# Ghostscript Tiger

`ghostscript-tiger.svg` — 68,630 bytes,
sha256 `5211e169283f43ab8ad7ea7998d917d5fbb3c568ac85c1a0217e86792822684d`.

Source: <https://commons.wikimedia.org/wiki/File:Ghostscript_Tiger.svg>,
derived from `examples/tiger.eps` in Ghostscript.

Authorship: Ghostscript authors.

## Licence

**GNU Affero General Public License**, full text in `LICENSE.AGPL-3.0.txt`.
This file is not public domain, unlike the other illustrations this project
uses as a corpus.

## Why it is here, and outside the published package

This directory is checked into git, so that the suite runs from any clone, and
it is listed in `.pubignore`, so it does not travel in the package published to
pub.dev.

The reason is practical rather than legal: shipping a test asset alongside MIT
code is mere aggregation (AGPL-3.0, section 5), but an AGPL file inside a
published package trips the licence scanners that many consumers run in
continuous integration. Keeping it out of the package means the question never
reaches anyone who depends on `dpdf`, while the tests can still use it.

Every illustration in `test/assets` that is **not** in this directory is public
domain. This is the single exception, and that is why it sits apart, in a
directory with its licence beside it.

A test that needs this file must skip when it is absent, since a consumer who
only has the published package will not have it.

## Why it is worth having

It is the classic stress image of PostScript and PDF: hundreds of filled paths,
many of them also stroked, and the drawing against which PDF generators have
been compared for decades.
