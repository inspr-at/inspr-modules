# INSPR cross-app routing contract

Configurable public origin, optional native `public_base_path` per app, and
prefix-preserving edge rules for Aithema, Paimos, Pharos, and Janus. This is a
draft protocol discriminator `inspr.routing/0.1-draft`. It does not change the
umbrella release scheme and is not live proxy or SSO proof.

JSON documents are claims a validator can check. Schema validity is not
authentication, packaging deployment, or proof that a combined browser address
already works in production.

## Architecture invariants

- `public_origin` is `scheme` + `host` only. No path, query, fragment, or
  credentials belong in the origin object.
- `public_base_path` is canonical ASCII: empty string (`""`) for standalone root,
  or one or more `/segment` components where each segment matches
  `[A-Za-z0-9_-]+`. No trailing slash, empty segments, dot segments, percent
  encoding, backslashes, queries, fragments, control characters, or
  protocol-relative paths.
- The edge preserves the configured prefix. It does not strip paths, rewrite
  HTML, iframe-wrap apps, emit permissive CORS, or trust forwarded identity
  headers (`X-Forwarded-User`, `X-Remote-User`, and similar).
- `X-Forwarded-Prefix` may be echoed as optional diagnostics but is never the
  sole source of truth because it is spoofable.
- Same origin is a shared trust domain, not shared authority. Each app keeps its
  own verified project membership, CSRF policy, and OIDC client/audience. Cookie
  names should avoid accidental collisions; cookie `Path` is not an isolation
  boundary against a compromised same-origin app. `__Host-` cookies remain
  `Secure`, `Path=/`, and without `Domain`.
- Disabled apps use `enabled: false`, `public_base_path: ""` on the shared
  origin, and may declare `disconnected.external_origin` for cross-navigation to
  a separate hostname. Do not proxy a dead prefix as a fake app.
- `/aithema`, `/paimos`, `/pharos`, and `/janus` are sample connected-install
  vocabulary only. Public fixtures carry no operator endpoints or secrets.
- Landing at `/` is explicit configuration (`aithema_workspace` or
  `connected_default_app`), not an invented universal gateway.

## Owning-app integration notes

These are contract expectations for the next implementation phase in each
product repository. This validator does not modify app routers.

| App | Standalone default | Connected install work |
|---|---|---|
| Aithema | `public_base_path=""`; keep `/oidc/callback`, `/logout`, `/projects/...` | Mount router and root-absolute assets under the configured prefix; derive OIDC `redirect_uri` from `public_origin` + `join_public_path(base, redirect_path)` |
| Paimos | `PAIMOS_URL` continues to hit `/api` when base is empty | Add `createWebHistory(base)`, prefix hard-coded `/api` and SSE URLs, rename generic `session` / `csrf_token` cookies with dual-read |
| Pharos | Origin-root Axum routes and assets | Nest every `/` route and `/assets/...` path; register prefixed OIDC redirect URI; browser Paimos links become same-origin `/paimos/...` when connected |
| Janus | `PublicURL` host-only today | Mux prefix for `/oidc/callback`, `/static/...`, `/flow/...`; include base path in `PublicURL` without double-joining |
| Flow shell | Embedded chrome only | Optional URL-join helper for hosts; no router or gateway behavior |
| Packaging (nixcfg / inspr-services) | One hostname per product today | Prefix-preserving reverse proxy module after app flags exist; set `X-Forwarded-Proto` / `X-Forwarded-Host` to the public origin |

Use `join_public_path(public_base_path, endpoint)` from `validate.py` when
building browser URLs, OIDC redirect URIs, and deep links so prefixes are not
duplicated and queries stay outside the path join.

## Layout and validation

- `schema/routing.schema.json` — JSON Schema Draft 2020-12 shape contract.
- `fixtures/valid/` — standalone Aithema, combined connected install, and
  Aithema-at-root with prefixed peers.
- `fixtures/invalid/` — replace-only patch fixtures with named semantic codes.
- `validate.py` — stdlib-only semantic checks plus `join_public_path`,
  `public_url`, and `validate_return_target` helpers.
- `tests/test_validate.py` — focused positive, adversarial, and join/redirect
  coverage.

```sh
python3 -m unittest discover -s tests -v
python3 validate.py fixtures/valid/combined-connected.json
```

Consumers should apply a standards-compliant Draft 2020-12 JSON Schema validator,
then run equivalent semantic checks. This bundled validator is not a reverse
proxy, SSO broker, HTML rewriter, or packaging module.

`packages/routing-edge` compiles this contract plus explicit deployment inputs
into Traefik 3.7.12 file-provider configuration. Schema validity remains not live
proxy or SSO proof.

## Draft compatibility (unreleased)

`inspr.routing/0.1-draft` is draft-to-draft only. There is no umbrella `VERSION`
bump and no claim that product routers or nixcfg packaging already honor the
contract. Real common-origin login proof remains a later INSPR acceptance gate.
