# /inspr-versioning — adopt or refresh INSPR Calendar Versioning

Load and follow [AGENTS-VERSIONING.md](../docs/AGENTS-VERSIONING.md) for this
repository. This command is the interactive adoption path. It does not replace
the policy file.

## Confirm first — no edits yet

On invocation, **do not** edit files, commit, push, or open a PR.

1. Read `docs/AGENTS-VERSIONING.md` from this doctrine (vendored `./doctrine/`
   or `inspr-modules`).
2. Inspect the current repo only: declared scheme, tags/releases, version UI,
   presentation pin, visitor-facing history, trust context, and the owning
   tracker.
3. Classify the adoption outcome from the policy: new project, existing
   ticket, implicit proposal, already adopted, or blocked/excepted.
4. Reply with a short **TL;DR** of what you would do in *this* repo. Cover,
   as applicable:
   - `inspr-calendar-v2` coordinates (`YYMMDDhhmmss.0.0`)
   - Pretty display via the shared presentation bundle (not handwritten CSS)
   - click and keyboard copy the **canonical** version (`.0.0` stays; no
     decorative `v`)
   - visitor-facing history that is positive and feature-oriented, in the
     visitor's language — not a git log
   - pin of the shared renderer/config, with build checks
   - a pull request, not a direct push to `main`
5. Stop. Ask the user to reply **`ok`**. Any other reply is not consent.
   Repeat the ask if they change scope instead of confirming.

## After exact `ok`

Ticket first in this product's designated PPM or PMA tracker, never both.
Then implement the classified outcome in this repo and open a PR.

Web products default to Pretty with SemVer as the reduced display, one thin
adapter around the shared renderer, hover/focus reveal, and copy-to-clipboard
of the canonical string. Native/CLI-only surfaces keep canonical text and
record where Pretty does not apply.

Do not rewrite published tags, releases, or deployed versions. Work already
in flight keeps the scheme it started under. Do not merge the PR unless the
user asks. Do not fetch presentation config at runtime.

If the outcome is blocked or excepted, record the missing gate and stop
without a fake adoption PR.
