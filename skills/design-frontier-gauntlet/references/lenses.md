# Lens selection

Use this reference while selecting tools/models and writing the five blind
worker briefs. The roles are stable; provider catalogs are not.

## Shared factual envelope

Every lens receives the same audience, jobs, required flows, product facts,
accessibility requirements, and simulation boundary. It receives no screenshot
or prose from another lens. Visual convergence caused by the shared product is
acceptable; convergence caused by copying is not.

## Lens briefs

### `codex-imagegen` — living interaction

Ask Codex to invent the interaction architecture in native HTML/CSS/JS and use
the built-in OpenAI ImageGen tool for at least one integrated visual asset.
Judge whether generated imagery and real interface mechanics form one system.
The asset must be copied into the concept directory; a reference to a generator
cache path is not a deliverable.

### `claude-fable` — editorial surprise

Ask Claude Fable 5.1 for a distinct, coherent visual thesis and complete
clickable concept. Record the model identity the CLI resolves. Do not substitute
Opus, Sonnet, or another model if Fable 5.1 is unavailable.

### `higgsfield-structure` — graphic system

Choose a live image model suited to controlled composition, graphic language,
or vector-like structure. The current verified candidate is Recraft V4.1
(`recraft_v4_1`), whose live schema exposes `model_type` including `vector`.
Treat that as a candidate, not a permanent pin.

### `higgsfield-spatial` — place and material

Choose a live image model suited to spatial composition, material, depth, or a
cinematic environment. The current verified candidate is Seedream 5.0 Pro
(`seedream_v5_pro`), whose live schema exposes wide aspect ratios and up to 2K.
Use a different available model if current evidence better fits the role.

### `higgsfield-precision` — legible interface detail

Choose a live image model suited to layout reasoning, exact text, or controlled
reference work. The current verified candidate is Nano Banana Pro
(`nano_banana_pro`), whose live schema exposes image references and up to 4K.
Use a different available model if current evidence better fits the role.

## Required Higgsfield discovery

1. Search current official Higgsfield pages for the available image-model
   families and their stated strengths. Use official sources, not listicles or
   remembered names. Useful entry points are:
   - `https://higgsfield.ai/ai-image`
   - `https://higgsfield.ai/canvas-intro`
   - `https://higgsfield.ai/creator-hub/help-center/ai-models`
2. Run the full, unfiltered catalog:

   ```bash
   higgsfield model list --image --json
   ```

3. Intersect the official candidates with live `job_type` values. Pick three
   distinct models that best cover structure, space, and precision.
4. Inspect each exact schema before writing its command:

   ```bash
   higgsfield model get <job_type> --json
   ```

5. Record the observed CLI version, discovery date, display name, `job_type`,
   and only the parameters actually used. The live schema wins over examples.

If fewer than three suitable distinct image models survive the intersection,
keep the missing role in the manifest as `unavailable` with the evidence. Do
not reuse one model under two names or replace Higgsfield with another provider.
