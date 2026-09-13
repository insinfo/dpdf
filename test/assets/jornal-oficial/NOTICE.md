# Jornal Oficial de Rio das Ostras

Six issues of the official gazette of the municipality of Rio das Ostras, Rio
de Janeiro, Brazil, from December 2024, each with the cover image the
municipality publishes beside it. `indice.json` records, for every file, the
edition, the date and the URL it was downloaded from.

Source: <https://www.riodasostras.rj.gov.br/jornal-oficial/>

## Licence

These are official acts of a public body — the published record of a
municipality's executive and legislative decisions. Brazilian law, Lei
9.610/1998 article 8, IV, places "os textos de tratados ou convenções, leis,
decretos, regulamentos, decisões judiciais e demais atos oficiais" outside
copyright protection. They are reproduced here unmodified, byte for byte.

## Why they are here

Every other PDF in this repository's test suite was written by this package.
A corpus that we generate only exercises the constructs we chose to emit, and
that blind spot is not theoretical: several real defects survived thousands of
tests and fell out of the first documents produced by other tools.

These files come from a commercial publishing pipeline. They carry embedded
TrueType subsets and Type0/Identity-H fonts, resource dictionaries that reuse
short names across Form XObjects, images drawn at reduced scale, and ToUnicode
CMaps written the way real producers write them rather than the way the
specification suggests.

## What the test built on them can and cannot catch

`test/render/jornal_oficial_test.dart` asserts that each cover opens, draws
without skipping a glyph, an image or an operator, and produces a plausible
amount of ink. On a foreign document those counters are the ones that move
first, and they are what a corpus of our own making never exercises.

It deliberately does **not** compare pixels against the published cover image.
That image is a lossy JPEG at another resolution, and measurement showed it
cannot tell a correct render from a broken one: with the font-resource bug that
these very files exposed, the whole-page disagreement moved only from 2.50 % to
3.24 %, and the worst 32x32 block did not move at all. Regressions of that
shape are locked by `test/render/font_resource_name_test.dart`, which
constructs the collision directly and fails deterministically without the fix.

## Packaging

This directory is checked into git, so the suite runs from any clone, and is
listed in `.pubignore`, so it does not travel in the published package — 5.5 MB
of fixtures is not something a consumer of the library should have to download.
The test skips when the files are absent.
