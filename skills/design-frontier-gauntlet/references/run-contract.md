# Run and gallery contract

Use one output root with this shape:

```text
<run-root>/
├── manifest.json
├── concepts/
│   ├── codex-imagegen/index.html
│   ├── claude-fable/index.html
│   ├── higgsfield-structure/index.html
│   ├── higgsfield-spatial/index.html
│   └── higgsfield-precision/index.html
└── gallery/index.html
```

Unavailable concepts may omit their directory. The gallery builder preserves
their card and reason.

All concept entries still require `label`, `provider`, `model`, `thesis`, and
`note`, including a lens stopped during preflight. A complete undispatched
entry is explicit and value-free:

```json
{
  "id": "claude-fable",
  "label": "Editorial surprise",
  "provider": "Anthropic",
  "model": "Claude Fable 5.1 (requested; not resolved)",
  "status": "unavailable",
  "not_dispatched": true,
  "reason": "Exact Fable 5.1 was unavailable during preflight.",
  "thesis": "No concept was generated.",
  "note": "No provider call or substitution occurred."
}
```

The gallery embeds ready concepts with `sandbox="allow-scripts"` and a
no-referrer policy. Concepts may execute their local interactions but cannot
share the gallery origin or navigate/mutate their parent. They must still avoid
remote requests; iframe sandboxing is not a network policy.

## Shared brief

Keep the brief short enough that each lens still makes choices:

```text
Ticket and tracker:
Audience and moment:
Job to be done:
Product facts that must stay true:
Required landing state:
Required linked flows (2–3):
Empty/error/first-use recovery:
Accessibility and responsive floor:
Simulation boundary:
Decision this comparison should enable:
```

Do not include preferred colors, layout, metaphors, or another concept unless
the user explicitly made one of those a product constraint.

## Manifest

`manifest.json` is UTF-8 JSON with schema version 1:

```json
{
  "schema_version": 1,
  "ticket": "PRODUCT-123",
  "title": "A short comparison title",
  "summary": "The stable product problem shared by every lens.",
  "concepts": [
    {
      "id": "codex-imagegen",
      "label": "Living interaction",
      "provider": "OpenAI",
      "model": "built-in ImageGen",
      "status": "ready",
      "entry": "concepts/codex-imagegen/index.html",
      "thesis": "One sentence describing the direction.",
      "note": "One factual implementation note.",
      "worker": {
        "name": "named-session",
        "uuid": "123e4567-e89b-42d3-a456-426614174000"
      }
    }
  ]
}
```

The exact required IDs are `codex-imagegen`, `claude-fable`,
`higgsfield-structure`, `higgsfield-spatial`, and `higgsfield-precision`.
Every dispatched concept needs a different actual worker UUID; RFC 9562 UUIDv7
sessions are valid. Ready concepts require a local HTML entry below the run
root. Unavailable concepts omit `entry` and require a specific `reason`. If
preflight prevents dispatch, also omit `worker` and set `not_dispatched` to
`true`; never fabricate a worker identity. Keep `note`, `thesis`, and `reason`
value-free.

Every dispatched Higgsfield lens also records the anti-stale selection
evidence used for that run:

```json
"model_evidence": {
  "cli_version": "1.1.24",
  "discovery_date": "2026-09-03",
  "display_name": "Recraft V4.1",
  "job_type": "recraft_v4_1",
  "parameters": ["model_type", "prompt", "resolution"],
  "official_sources": ["https://higgsfield.ai/ai-image"]
}
```

Use the observed values, not this example as a pin. `parameters` lists only
fields actually sent. `official_sources` accepts HTTPS pages on
`higgsfield.ai`; keep URLs and all other evidence free of query strings,
credentials, account identifiers, or private inputs. A lens stopped before
dispatch does not invent model evidence. Discovery evidence older than seven
UTC calendar days is rejected so a new comparison cannot silently reuse a
stale catalog selection.

## Comparison question

The gallery is evidence for a human decision, not a score generator. Review:

- Does the landing state reveal what deserves attention without dashboard
  clutter?
- Can a first-time user always take a useful next action?
- Do the linked states express a coherent interaction model rather than a set
  of screenshots?
- Are agents, projects, relationships, and authority legible?
- Does the direction remain usable with keyboard, reduced motion, and a narrow
  viewport?
- Which idea should be carried into production, and which should remain a
  reference only?
