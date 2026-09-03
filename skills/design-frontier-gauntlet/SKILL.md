---
name: design-frontier-gauntlet
description: "Create five independently conceived, clickable interface directions and one local comparison gallery when a product needs genuine visual exploration before implementation. Use for design-frontier studies, competing UI concepts, or a high-ambition interface redesign—not routine UI implementation or production deployment."
---

# Design Frontier Gauntlet

Run a bounded design exploration, not a disguised production build. Five
isolated builders interpret one shared product problem through different
creative lenses. The controller makes their standalone concepts comparable in
one local gallery; a human chooses what deserves implementation.

## Non-negotiable boundaries

- Read the installed `inspr-worker-doctrine` skill before any state change.
- Bind the work to exactly one ticket in the product's designated tracker:
  PPM or PMA, never both. Before dispatch, write `I work on this` using the
  canonical marker with the actual session UUID for the controller and each
  builder that is dispatched.
  A lens stopped by preflight has no worker and records `not_dispatched=true`;
  never invent a UUID. One builder owns one concept; builders never co-author
  or repair another concept.
- Use five isolated output directories and, when code repositories are
  involved, distinct worktrees. A concept may read the shared brief and source
  product but writes only within its assigned directory.
- Default output is a local prototype. Do not edit the production application,
  push, merge, publish, deploy, or change live data unless the user separately
  authorizes that delivery.
- Keep credentials, auth state, prompts containing private data, and generated
  inputs outside repositories and the Nix store. Never copy tokens or session
  files into a concept or gallery.
- Send external model providers only approved, non-confidential product facts.
  Never put customer data, credentials, private source, unpublished designs,
  or internal-only documents into ImageGen, Claude, or Higgsfield prompts.
- A clickable prototype must label simulated actions. It must not silently call
  real APIs, start workers, send messages, deploy, or imply that a mock action
  happened.

## Prepare the run

1. Write one short shared brief: audience, job to be done, existing product
   truth, required flows, constraints, and the decision the gallery should
   enable. Separate required behavior from visual taste.
2. Choose an output root explicitly. If the user did not name one, use a
   disposable directory from `mktemp -d`; do not invent a new repository.
   Export the chosen absolute path as `RUN_ROOT` for the commands below.
3. Create `concepts/<lens-id>/` for each lens and a controller-owned
   `manifest.json`. Use the schema and brief pattern in
   [references/run-contract.md](references/run-contract.md).
4. Preflight the five tool/model paths before dispatch. Missing authentication,
   quota, CLI, model, or browser support is an unavailable lens—not permission
   to install software, buy credits, switch providers, or fake its result.

## Use exactly five lenses

Read [references/lenses.md](references/lenses.md) before selecting models or
writing worker briefs.

1. **Codex + OpenAI ImageGen** — Codex builds the native HTML/CSS/JS concept and
   integrates at least one original visual made with the built-in ImageGen
   tool. Do not substitute an API/CLI image generator.
2. **Claude Fable 5.1** — Fable owns a separate concept and its visual thesis.
   Dispatch through the local Claude CLI with `claude --model fable`, then
   record its resolved identity as `Claude Fable 5.1` (or
   `claude-fable-5-1`). If that exact model is unavailable, mark this lens
   unavailable rather than silently using another Claude model.
3. **Higgsfield structural lens** — a model suited to graphic systems,
   composition, or vector-like structure.
4. **Higgsfield spatial lens** — a model suited to environments, depth,
   material, or cinematic spatial invention.
5. **Higgsfield precision lens** — a model suited to readable interface detail,
   controlled editing, or text/layout reasoning.

The three Higgsfield models must be distinct. Select them at run time from the
intersection of current official web documentation and the live unfiltered
`higgsfield model list --image --json` response, then inspect every selected
model with `higgsfield model get <job_type> --json`. Never trust a remembered
catalog or semantic search alone.

## Worker contract

Give every builder the same product facts and required flows, plus only its
lens. Do not show it other concepts or prescribe the expected visual answer.
Each builder must produce:

- `index.html` as the entry point, with local assets and no required build step;
- a landing state plus two or three meaningfully linked states;
- keyboard-operable primary flows and a responsive layout;
- visible recovery from empty, unavailable, or first-use states;
- honest labels on every simulated mutation; and
- a short, value-free manifest summary: thesis, model/tool actually used,
   worker name and UUID (when dispatched), status, and any unavailable
   capability.

Prefer native HTML/CSS/JS for the interaction shell. Generated imagery may
enrich the direction but must not flatten the whole interface into a picture.
Do not load remote scripts, fonts, analytics, trackers, or production data.
Concept state must stay in memory. The gallery sandbox deliberately denies web
storage, cookies, modal dialogs, form submission, popups, and downloads; do not
use those primitives for a required flow.

## Build the comparison gallery

After the five workers stop, the controller validates their manifest entries
and runs:

```bash
for DESIGN_FRONTIER_SKILL in \
  "$HOME/.codex/skills/design-frontier-gauntlet" \
  "$HOME/.claude/skills/design-frontier-gauntlet"; do
  test -f "$DESIGN_FRONTIER_SKILL/scripts/build_gallery.py" && break
done
: "${RUN_ROOT:?export RUN_ROOT as the chosen design-frontier output root}"
test -f "$DESIGN_FRONTIER_SKILL/scripts/build_gallery.py" || {
  echo "design-frontier-gauntlet is not installed for Codex or Claude" >&2
  exit 1
}
python3 "$DESIGN_FRONTIER_SKILL/scripts/build_gallery.py" --root "$RUN_ROOT"
```

Open `$RUN_ROOT/gallery/index.html` locally. The gallery provides a matrix view
and keyboard-accessible single-concept views. It preserves unavailable lenses
with their reason instead of dropping them, so a partial run never masquerades
as a five-way comparison. Ready concepts run in script-only sandboxed frames;
they cannot inherit the gallery origin, navigate the parent, submit forms, open
popups, or trigger downloads. The sandbox is a containment backstop, not
permission for a concept to make network calls.

## Bounded QA

Run QA once, after all five concepts have reported:

1. When modifying this skill, run
   `python3 "$DESIGN_FRONTIER_SKILL/scripts/test_build_gallery.py"` and the
   repository's normal focused checks.
2. Serve the run root locally and exercise gallery navigation, each ready
   concept's main flow, keyboard focus, reduced motion, and narrow/mobile
   layout. Do not use a production URL.
3. Check the gallery against the required flows and factual constraints. Do not
   normalize away creative differences.
4. Allow at most one focused repair pass per concept for a broken link,
   inaccessible primary control, false claim, overflow, or missing requirement.
   Taste iteration waits for the human's selection.

Stop after the comparison is decision-ready. Report the local gallery path,
five statuses, actual model/tool identities, material gaps, and the next
decision. Never self-declare a taste winner.
