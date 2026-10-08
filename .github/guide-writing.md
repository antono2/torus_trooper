# Guide-writing notes

These rules govern future changes to the [design guide](../docs/learning-path.md).
They belong here so the reader-facing guide remains about game design and
implementation.

## Explain decisions for readers

- Follow the reader-state and top-down principles in
  [Gernot Heiser's technical writing guide](https://gernot-heiser.org/style-guide.html):
  introduce the problem and needed terms before the implementation details.
  Its paper- and thesis-specific formatting rules do not apply here.
- Explain the general design choice, show this repository's implementation
  and compare other viable implementations with reasons to choose each.
- Include production-scale concerns. Avoid framing a basic version as the only
  viable choice or making exercises the main teaching method.
- Keep examples concrete: name the relevant state, order, data layout,
  lifetime, asset or device constraint. State assumptions and limits.
- Write about this repository as its own game. The README holds the credit to
  the project that inspired it. The guide does not track correspondence to
  another implementation.

## Keep the guide accurate

- Check each source link against the current code. Distinguish implemented
  behavior from proposed variants and release work.
- Link named functions, structs and focused tests to their current source
  lines using relative `#L` links. A file-level link is suitable when the
  discussion covers the whole file. Use commit-pinned links only when
  explaining a historical version.
- After source moves, review and update line anchors, then run
  `python3 scripts/check_guide_links.py --refresh`. Run
  `python3 scripts/check_guide_links.py` in the normal guide check; it also
  validates local files and Markdown headings. The fingerprint file is
  `.github/guide-source-anchors.json`.
- Update diagrams when a boundary, order or lifetime changes. Use Mermaid
  diagrams when they clarify a relationship; keep a text explanation nearby.
- Recheck claims about platform requirements against current primary
  documentation before changing them.
- Validate links and `git diff --check`. For code changes, run
  the closest focused test, then headless regression and graphical or OpenCL
  checks when those boundaries are affected.
