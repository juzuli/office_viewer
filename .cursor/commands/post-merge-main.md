---
description: After merging to main — quality, docs, pub example, publish, GitHub release
---

You are running the **post-merge to `main`** maintainer workflow for `office_viewer`.

Follow **CONTRIBUTING.md → “After merging to `main`”** as the source of truth. Work the checklist in order; skip only what clearly does not apply. Ask before publishing to pub.dev or creating a GitHub Release if the user has not already approved those writes.

## Do this

1. **Confirm branch** — `git checkout main && git pull`. Summarize what landed since the last pub/release tag.
2. **Quality gate** — `flutter pub get && flutter analyze && flutter test`. Fix failures before continuing.
3. **Versions** — Decide which packages need a bump (`office_viewer`, `office_viewer_engine_dart`, `office_viewer_engine_convert`, `office_viewer_engine_pdf`). Update CHANGELOGs. Keep every `description` in pubspec between **60–180** characters.
4. **Docs sync** — Update README Install / Support / registry order if engines changed. **Must** update pub [`example/`](example/) when install instructions change (`example_app/` is not published). Strip stale “not on pub yet” / LOK / path-only wording.
5. **Dependency floors** — Engine constraints and `example/pubspec.yaml` hosted pins match what you will publish.
6. **Publish** (only with user OK, or if they already asked to publish):
   - Dry-run: `./tool/publish.sh --dry-run`
   - Real: `./tool/publish.sh --force`
   - PDF separately if bumped (move root `.pubignore` aside; see CONTRIBUTING).
7. **GitHub Release** — Tag `vX.Y.Z` matching core; notes cover engines shipped in the same cut. If `gh` needs workflow scope, tell the user to run `gh auth refresh -h github.com -s workflow`.
8. **Downstream** — If relevant, bump YChat / other hosts to new `^` pins and keep registry **PDF → Convert (optional) → Dart**.

## Report back

End with a short status table: what was checked, what was published, what was skipped, and any remaining manual steps.
