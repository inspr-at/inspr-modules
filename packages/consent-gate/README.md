# consent-gate

Identity-free consent primitive for browser-facing surfaces. One manifest per
surface declares categories, services and texts; the gate decides what may
load and what to render. It implements the doctrine pattern
"web surfaces — cookies & consent" (`docs/AGENTS-DOMAIN-DEV.md`):

- **Tier 0** — the manifest has no optional service: nothing is rendered
  except an optional `[data-consent-open]` control that opens the sheet.
- **Tier 1** — only embeds need consent: a contextual placeholder replaces
  each `[data-consent-embed]` element until "load once" (this page view) or
  "always allow" (persisted for the category). No page-level bar.
- **Tier 2** — a service has a tracking destination: a non-modal bar with
  equivalent **reject** and **accept** buttons, a **settings** link and a
  category sheet. Escape or cancelling the sheet during the first prompt
  counts as refusal. Nothing optional loads before an affirmative, persisted,
  purpose-specific choice.

Behaviour that is the same on every surface:

- The decision is a host-only cookie `v1;r=<revision>;g=<granted>;t=<unix>`
  (`SameSite=Lax`, `Secure` on HTTPS, no identifier), kept `maxAgeDays`
  (default 180) for a grant and a refusal alike. `revision` is bumped only
  for a material change of purposes; copy edits keep the decision.
- An affirmative Global Privacy Control or Do-Not-Track signal is a refusal:
  no bar, stored, also over an older grant; signal disappearance does not
  revive it. Crawlers see no bar and get nothing.
- Every destination load re-validates cookie, expiry, revision, signal and
  crawler status. A grant that cannot be read back is no grant. A refusal
  that cannot be stored as a cookie falls back to a session-scoped revocation
  that still outranks a surviving grant on the next page.
- Withdrawal (or dropping a category in the sheet) clears the storage each
  affected service declares (`cookie`, `local`, `session`), sends Consent
  Mode `denied` to a loaded destination and reloads the page once the
  refusal is persisted, because a loaded tag has no reliable teardown.
- Google destinations run Consent Mode v2 in **basic** mode: `default`
  denied for every key, `update` grants only the keys the service declares,
  then `gtag.js` is injected with `cookie_domain` pinned to the host. A
  conversion fires only on pages that name the service in
  `data-consent-fire`, once per session.

## Files

| File | Purpose |
|---|---|
| `consent-gate.js` | Core (`insprConsentCore`, no DOM) + renderer and destination adapter (`insprConsent`). |
| `consent-gate.css` | Reference styles; every token is a `--ic-*` custom property with a neutral fallback. |
| `manifest.schema.json` | JSON Schema for the manifest. |
| `example/manifest.json`, `example/example.html` | A valid manifest and a page that uses it. |
| `../../tests/consent-gate.mjs` | Node test suite (part of `nix flake check`). |
| `../../scripts/check-consent-gate-vendored.sh` | Drift check for a consumer's vendored copy. |

## Manifest

```jsonc
{
  "version": 1,
  "revision": 1,               // bump only on a material purpose change
  "cookieName": "consent",     // host-only decision cookie
  "maxAgeDays": 180,
  "language": "de",            // else <html lang>, else the first text key
  "privacyUrl": "/privacy",
  "categories": [ { "id": "necessary", "required": true }, { "id": "marketing" } ],
  "services": [
    { "id": "ads", "category": "marketing", "provider": "…",
      "storage": [ { "kind": "cookie", "name": "_gcl_*", "days": 90 }, { "kind": "local", "name": "_gcl_ls" } ],
      "destination": { "type": "gtag", "tagId": "AW-…", "consent": ["ad_storage", "ad_user_data"],
                       "linkerAcceptIncoming": true, "conversion": { "sendTo": "AW-…/…" } } },
    { "id": "video", "category": "embeds", "provider": "…", "embed": { "host": "video.example.invalid" } }
  ],
  "text": { "de": { "bar": {…}, "sheet": {…}, "embed": {…}, "control": "…", "categories": {…}, "services": {…} } }
}
```

Exactly one category is `required`; optional services must sit in an
optional category; each service declares exactly one of `destination` or
`embed`. `consent` lists the Consent Mode keys the service may ever set:
an undeclared key (for example `ad_personalization`) stays denied. Validation
failures close the gate: nothing optional loads and nothing is rendered.

## Using it on a surface

1. Copy `consent-gate.js` and `consent-gate.css` into the surface's own
   assets (self-hosted; never a CDN). Record the inspr-modules revision you
   copied from and add the drift check to CI:

   ```sh
   scripts/check-consent-gate-vendored.sh path/to/vendored/consent-gate.js <sha256 of the copy at the pinned revision>
   ```

   A Go surface embeds the file with the rest of its assets; an Astro or
   static surface puts it under `public/`. Both compare bytes in CI.
2. Put the manifest into the page as
   `<script type="application/json" id="consent-manifest">…</script>`
   (or set `window.insprConsentManifest` before the gate script).
3. Load the gate with `defer`:
   `<script src="/assets/consent-gate.js" defer data-consent-manifest="#consent-manifest" data-consent-fire="ads"></script>`.
   `data-consent-fire` names the services whose conversion fires on this
   page; leave it empty elsewhere.
4. Mark embeds: `<iframe data-consent-embed="video" data-src="…">` (or keep
   `src`, the gate moves it to `data-src` before anything loads).
5. Put a `<button type="button" data-consent-open></button>` in every footer;
   the gate fills the label from `text.<lang>.control`.
6. Map the tokens: `--ic-surface`, `--ic-surface-soft`, `--ic-ink`,
   `--ic-muted`, `--ic-line`, `--ic-accent`, `--ic-focus`, `--ic-radius`,
   `--ic-radius-pill`, `--ic-font`, `--ic-font-heading`, `--ic-shadow`,
   `--ic-shadow-dialog`.
7. Keep the surface's CSP: `script-src 'self'` plus the destination hosts
   only where a destination exists; the gate needs no inline script.
8. Serve the same texts in every language the surface supports; the gate
   picks `manifest.language`, else `<html lang>`.

Programmatic access: `insprConsent.open()`, `insprConsent.withdraw()`,
`insprConsent.granted("marketing")`, `insprConsent.core` (the bound core).

## Testing on the surface

The core is unit-tested here. The surface owns the browser proof, run on a
CI runner with a real browser: fresh visit (no request to any destination
host), reject, accept (exactly one destination request, Consent Mode order),
settings after a refusal, withdrawal (storage cleared, reload, nothing
afterwards), GPC/DNT over an older grant, rejected and throwing cookie jars,
crawler user agent, conversion scope and dedupe, privacy page. Stub the
destination hosts inside the browser so the suite never reaches them.

## Licence

AGPL-3.0-only, like the rest of this repository. No third-party code is
vendored in this package.
