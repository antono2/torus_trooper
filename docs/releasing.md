# Release the exact tested archives

Update `v.mod` and add the matching version section to `CHANGELOG.md`. CI takes
archive names from `v.mod`; compatibility pins remain in `compatibility.json`.
Review and merge the change, then wait for all main CI jobs, including both
package consumers, to pass. Do not rebuild the binaries after these checks.

In a clean checkout of that exact main commit, with Python 3 and authenticated
GitHub CLI:

```sh
python scripts/prepare_release.py RUN_ID --output /path/to/new-release-directory
```

The command checks the source commit and all required jobs, downloads the exact
tested archives, and generates `SHA256SUMS`, a source/compatibility manifest and
release notes. It refuses an existing output directory and does not publish.
Review the archive names, manifest, notes and CI evidence before proceeding.

Create and push only the matching tag, then create a draft with the two archives,
`SHA256SUMS` and `release-manifest.json`:

The commands below illustrate the published v0.23.1 release. For a new release,
substitute the version from the tested checkout in every tag, title and archive
name; do not reuse or move an existing release tag.

```sh
git tag v0.23.1
git push origin v0.23.1
gh release create v0.23.1 --repo antono2/torus_trooper --verify-tag --draft --title "Torus Trooper 0.23.1" --notes-file /path/to/new-release-directory/release-notes.txt /path/to/new-release-directory/torus-trooper-0.23.1-windows-x86_64.zip /path/to/new-release-directory/torus-trooper-0.23.1-linux-x86_64.tar.gz /path/to/new-release-directory/SHA256SUMS /path/to/new-release-directory/release-manifest.json
```

Before publication, run **Published desktop package consumers** manually with
the draft tag. Draft visibility requires the workflow's `contents: write`
permission, although the consumer jobs only download assets. Authenticated CI checks their
checksums and runtime behavior on both OSes. Publish only after those jobs pass:

```sh
gh workflow run published-packages.yml --repo antono2/torus_trooper -f tag=v0.23.1
gh release edit v0.23.1 --repo antono2/torus_trooper --draft=false --latest
```

The publication event also runs the download consumers. Preserve the older
release and its assets. A failed draft consumer is a release blocker; investigate
its preserved logs rather than replacing the tested archives with an ad hoc build.
