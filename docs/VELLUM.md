# Publishing to Vellum

Vellum packages live in https://github.com/vellum-dev/vellum under `packages/<name>/VELBUILD`. This repo ships a
ready `vellum/VELBUILD` that installs the release archive into AppLoad's app directory.

## What the Vellum repository requires

- **A person opens the pull request.** Pull requests and issues "must be opened by a person, not by an agent";
  a PR description written by an LLM gets the PR closed. Write the description yourself.
- **No AI co-author trailers.** Commits in that repo must be authored and co-authored by people, no
  `Co-Authored-By:` naming an assistant or bot.
- A `packages/sudoku/VELBUILD` in Alpine's APKBUILD format with `maintainer`, `pkgname`, `pkgver`, `pkgrel`,
  `pkgdesc` (under 128 characters), `upstream_author`, `category` (one of `ui fixes utilities apps framework launchers development`),
  `url`, `arch`, `license` (SPDX id), `source` and `sha512sums`. The repo's `scripts/validate-velbuild.sh` checks the metadata
  (our CI runs it).
- Prefer building from source where possible (`image="ghcr.io/toltec-dev/rust:v4.0"` plus a `build()`); packages that
  ship prebuilt release binaries (as AppLoad and rm-pokemon do) are accepted. This package uses the prebuilt release archive
  because `resources.rcc` needs Qt's `rcc`, which the toolchain images do not provide.
- OS compatibility is declared in `depends=` (`remarkable-os>=3.29 remarkable-os<3.30` here). Packages that support none of the last three
  stable minor versions may be marked `status="unmaintained"`. Bump `pkgrel` for packaging-only changes, reset it to 0 when `pkgver` changes.
- Device exclusions are also `depends=` entries (`!rmppm`); `arch="aarch64"` already excludes the reMarkable 1 and 2.
- `depends="launcher"` is satisfied by AppLoad (`provides="launcher"`).
- Optional local checks (need Docker or Podman and `vbuild`): `./scripts/lint-packages.sh sudoku`,
  `./scripts/update-checksums.sh sudoku`, `./scripts/build-package.sh sudoku aarch64`.

## Steps

1. Make sure `X39/remarkable-sudoku` is on GitHub and the `maintainer` in `vellum/VELBUILD` is what you want listed.
2. Tag a release (`git tag v1.0.0 && git push origin v1.0.0`); the release workflow publishes
   `sudoku-appload-1.0.0-aarch64.tar.gz`.
3. `sh tools/update-velbuild.sh 1.0.0` writes the real `sha512sums` (and `pkgver`) into `vellum/VELBUILD`. Commit that.
4. Fork vellum-dev/vellum, copy `vellum/VELBUILD` to `packages/sudoku/VELBUILD`, test it with `build-package.sh`, and open the PR yourself.

## Decisions to confirm in the VELBUILD

- `license="MIT"` (matches `LICENSE`).
- `!rmppm`: the UI uses fixed pixel layouts made for the Paper Pro screen; the Paper Move is untested. Remove it if you test there.
- `remarkable-os>=3.29 remarkable-os<3.30`: only 3.29.1 is tested. The app relies on xochitl's internal `ghostBuster` object for
  the full-panel e-ink clear, which may change between firmware versions.
