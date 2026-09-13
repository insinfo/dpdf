# Distributed fixtures

Hashes and sources: `manifest.json`. The nine in-house fixtures are covered by
`LICENSE.generated.txt`; ABeeZee-Regular.ttf keeps the full `OFL.txt`;
pdf20-offset-start.pdf comes from the PDF Association and keeps CC BY-SA 4.0.
The licence notices use LF line endings, per `.gitattributes`, so that the
hashes still match after a checkout on other platforms. The terms are also
collected in `../../THIRD_PARTY_NOTICES.md`.

The in-house images are synthetic geometric patterns, and the names say what
they are: shapes-rgb.jpg, shapes-rgb.png and shapes-rgb-large.bmp carry the
same drawing — a blue rectangle, an orange ellipse and a red diagonal — in
three formats and two sizes, and blue-square-16.gif is a 16 px palette-indexed
blue square. They used to be called Desert.jpg, bee.png, WP_20140410_001.bmp
and bulb.gif, inherited names that described none of the content and made each
test look as if it exercised a photograph. test.pdf holds a synthetic page with
two rectangles. image.jb2 exercises a generic MMR region, and does not stand
for full JBIG2 coverage.

The eight `.svg` files are public domain, from publicdomainvectors.org;
`manifest.json` carries the URL of each. They serve as a conversion corpus
precisely because this project did not draw them: they bring paths, gradients,
groups and transforms that our own generators never emit. The names were moved
to kebab-case, and one was corrected — `tiger1.svg` became
`bengal-tiger-head.svg`, which is what the illustration shows.

`ghostscript-tiger/` is the one exception to public domain: it is AGPL. It sits
in its own directory with the full licence text and its provenance beside it,
and is excluded from the published package by `.pubignore`. See
`ghostscript-tiger/NOTICE.md`.

pdf20-offset-start.pdf is an unmodified copy of `PDF 2.0 with offset start.pdf`
from the PDF Association's pdf20examples repository, renamed only to take the
spaces out of the path. It is the official ISO 32000-2, 7.5.2 example: `%PDF-`
starts at byte 656, after 656 bytes of plain-text comment, and the xref offsets
are counted from the percent sign, not from the start of the file. The
attribution that CC BY-SA 4.0 requires is in `../../THIRD_PARTY_NOTICES.md`.

rootRsa.cer is a self-signed RSA-2048 test certificate, named
DPDF Synthetic Test CA, serial 1491571158. It holds no private key. It was
generated for the fixture; it stands for no public or ICP-Brasil trust.

The manifest's source fields record the generator originally used,
`tool/generate_test_assets.py`, which is no longer present in this tree. They
are not recreation instructions. The hashes are what let you verify the
preserved bytes. The old generators of the embedded data are likewise not
needed in order to consume the existing resources.
