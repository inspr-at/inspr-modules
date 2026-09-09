# INSPR routing-edge

Deterministic stdlib compiler that turns an `inspr.routing/0.1-draft` contract
plus explicit operator deployment inputs into Traefik **3.7.13** file-provider
configuration. Native application paths are preserved. This is not live SSO
proof and not a credential store.

## Deployment modes and outputs

The deployment `mode` is closed: `managed` (the compatibility default when the
field is absent) or `external-file-provider`. Unknown and mixed modes fail.

Managed mode retains the original output and behavior:

- `dynamic.yml` — routers, services, middlewares, streaming transports
- `static.yml` — one entrypoint, file provider, dashboard/API omitted
- `wiring-report.json` — public URLs and unpublished control families; no secrets

External mode emits `dynamic.yml` plus the evidence-limited wiring report, but
no `static.yml`. It is for a consumer-owned, already-running Traefik whose static
configuration already defines the selected entrypoint, certificate resolver and
file-provider directory. The fragment creates no listener, certificate, ACME
configuration, helper process, dashboard or API. Generate into a staging
directory and install only `dynamic.yml` under a unique consumer-owned filename;
do not point a Traefik directory provider at the staging directory because the
JSON report is not a Traefik configuration document.

When an external generation replaces managed output in the same staging
directory, the compiler removes `static.yml` only when its INSPR-generated
header proves ownership. It refuses to remove an unrelated `static.yml`.

Pinned syntax: Traefik 3.7.13 `file-provider-v3.7.13`; the
[official release](https://github.com/traefik/traefik/releases/tag/v3.7.13)
lists five security advisories. The process-proof
artifact is the official `docker.io/library/traefik` OCI index
`sha256:f86a2cab1b5c649070c49f883c743dd32d8485a56e3368c5f93b9e91f1e91259`;
its linux/amd64 manifest is
`sha256:96780238b1bbda5a9bb997f4307ce69e798ad1cf6eb7f2dcc0a440823467d199`.
Registry digest verification and isolated loopback process tests are both
required evidence; a matching version string alone is not artifact provenance.
Untested versions are not claimed.

## Operator inputs

Managed deployment JSON is bounded:

- optional `mode: "managed"` (absence remains managed for compatibility)
- `entrypoint.name` / `entrypoint.address` (`:port` or `127.0.0.1:port`)
- `upstreams.<app>.url` origin-only (`http`/`https`, no userinfo/query/fragment/path)
- optional `upstreams.<app>.ca_file` for https backends
- `public_tls.cert_file` and `key_file` for public HTTPS
- `loopback_http_fixture: true` only for 127.0.0.1/localhost tests

External deployment JSON instead requires:

- `mode: "external-file-provider"`
- `entrypoint.name` naming an entrypoint in the existing static configuration
- `certificate_resolver` naming an existing resolver
- `resource_namespace`, a unique prefix for every generated Traefik object
- the same explicit `upstreams`; any `ca_file` is emitted unchanged

External mode rejects `entrypoint.address`, `public_tls` and
`loopback_http_fixture`. Its routers use the selected resolver, while certificate
issuance, renewal, key access, public ports, forwarded-header trust and process
lifecycle remain entirely consumer-owned. Every upstream CA path must be
readable by that existing Traefik process; a path in another unit's
`/run/credentials/...` directory is not usable.

Public operation requires HTTPS. HTTP is allowed only as an explicit loopback
fixture. HTTP upstreams are only accepted on loopback or private addresses.
Upstreams must be distinct servers from the public origin. The compiler never
selects an upstream from the request.

TLS private keys and certificates stay on the host filesystem. The compiler and
Nix packaging only carry **path strings**; they never read or import key material
at build or evaluation time.

The denial middleware is self-contained Traefik configuration: an impossible
allow-list returns 403 before its unreachable placeholder service can be used.
No helper service is required. Consumers own the chosen resource namespace and
fragment filename and must prevent collisions with all other dynamic providers.

## Trust and path rules

- Prefix-preserving: no `StripPrefix`, no HTML rewrite, no iframe gateway
- `passHostHeader: true`; Traefik sets `X-Forwarded-Host` / `X-Forwarded-Proto`
- Incoming `X-Forwarded-User` / `X-Remote-User` / `Remote-User` are deleted
- Optional `X-Forwarded-Prefix` is the configured prefix only, never request-chosen
- No CORS middleware, no shared session fallback, no identity injection
- Overlapping enabled mounts are rejected by the contract validator
- Root app plus prefixed peers use explicit priorities; PathRegexp uses segment
  boundaries so `/paimosx` is not `/paimos`
- Disabled apps are not proxied. Sample vocabulary of a disabled app
  (`/aithema`, `/paimos`, `/pharos`, `/janus`) is denied so it cannot fall through
  into a root-mounted peer
- Internal control paths are denied from **actual app route registrations**:
  Paimos control/lifecycle/dev-login/debug families, Janus `/internal` and
  `/buildz`, Pharos `/internal`, `/agent`, `/metrics`, `/register`, `/report`,
  Aithema `/session/demo`. Native unprefixed variants are also denied
- Paimos SSE (`/api/changes`, `/api/agent-mode/deliveries/events`,
  `/api/intake/sessions/{id}/stream`) is forwarded with
  `responseHeaderTimeout: 0s` and without buffering middleware
- Cookie `Path` is not an isolation boundary; apps keep their own OIDC/CSRF
- This generator does **not** attest upstream certificates or Zitadel SSO

## Python usage

```sh
python3 generate.py \
  --contract ../../contracts/routing/fixtures/valid/combined-connected.json \
  --deployment fixtures/valid/combined-connected.deployment.json \
  --output-dir ./out
```

```sh
python3 -m unittest discover -s tests -v
```

Loopback Traefik process tests use `INSPR_TRAEFIK_BIN` and require version
3.7.13. The external TLS proof discovers OpenSSL on `PATH`, or accepts an
explicit executable path through `INSPR_OPENSSL_BIN`; absence or an invalid
explicit path fails the proof rather than skipping it. Temporary directories
stay under `tests/.tmp/`. Neither binary is vendored.

## Nix package and NixOS module

Public reusable packaging lives under `nix/` in the
[`inspr-at/inspr-modules`](https://github.com/inspr-at/inspr-modules) atelier.
Consumers import it with their **own pinned nixpkgs** and a pinned
`inspr-modules` flake input. Nothing here fetches nixpkgs, Traefik or anything
else at build time or at run time.

**Publication prerequisite:** root review must publish this tree through
`inspr-modules` before consumers pin an immutable coordinate. The consumer example below targets `v0.5.0`; use it after the matching
GitHub Release is published. A prepared source branch alone is not release
availability.

### Package

From a consuming flake after publication:

```nix
inputs.inspr-modules.url = "github:inspr-at/inspr-modules/v0.5.0";

let
  routingEdge = inputs.inspr-modules.packages.${pkgs.system}.routing-edge;
in
routingEdge
```

Inside this repository, `packages.routing-edge` is built with `insprSource =
self` and needs no private umbrella checkout. The underlying `nix/default.nix`
takes exactly two arguments and no defaults:

```nix
let
  routingEdge = import ./packages/routing-edge/nix {
    inherit pkgs;              # caller-pinned nixpkgs
    insprSource = insprSrc;    # path or store path — no unpinned fetch
  };
in
routingEdge
```

Installed command: `inspr-routing-edge-compile`.

The build source is filtered down to the public compiler
(`packages/routing-edge/routing_edge`, `generate.py`, `LICENSE`) and the one
dependency it actually imports, `contracts/routing/validate.py`. Doctrine,
other contracts, fixtures and test trees never enter it. The installed tree
keeps those two paths relative to the store root, because
`routing_edge.compile` resolves the validator as
`Path(__file__).resolve().parents[3] / "contracts" / "routing"` — no packaging
hook in `compile.py` is needed, and the command works with no checkout present:

```sh
cd /
inspr-routing-edge-compile \
  --contract /path/to/contract.json \
  --deployment /path/to/deployment.json \
  --output-dir /tmp/routing-edge-out
```

The derivation is deliberately **name-only**: packaging the compiler does not
mint a release coordinate for it. `nix/pinned.nix` carries the Traefik syntax
pin, and an install-time check fails the build if it ever drifts from
`PINNED_TRAEFIK_VERSION` / `PINNED_TRAEFIK_SYNTAX` in `routing_edge/deployment.py`.

### NixOS module

Import `packages/routing-edge/nix/module.nix`. It is **disabled by default**.
It does not open a firewall port, does not expose the Traefik dashboard or API,
does not provision or renew a certificate, does not enrol an OIDC client and
does not deploy an app. A disabled configuration evaluates without any of the
inputs below being set.

`deploymentMode = "managed"` retains the service described below. In
`external-file-provider` mode the module builds one fragment and declares only
`environment.etc.<external.providerFile>`; it defines no routing-edge systemd
service and does not require `traefikPackage`, `publicTls` or an entrypoint
address. The caller still supplies the compiler `package`, public `contractFile`
and upstream map.

Caller supplies:

| Option | Meaning |
|---|---|
| `services.inspr.routingEdge.package` | compiler package built from `nix/default.nix` |
| `services.inspr.routingEdge.traefikPackage` | consumer-owned Traefik pin (see compatibility below) |
| `services.inspr.routingEdge.contractFile` | public routing contract JSON (no secrets — it goes to the store) |
| `services.inspr.routingEdge.upstreams.<app>.url` | explicit origin-only upstream |
| `services.inspr.routingEdge.upstreams.<app>.caFile` | optional CA bundle path for an https upstream |
| `services.inspr.routingEdge.publicTls.certFile` / `.keyFile` | absolute host paths for public HTTPS |
| `services.inspr.routingEdge.entrypoint.name` / `.address` | Traefik entrypoint (`:443` by default) |
| `services.inspr.routingEdge.loopbackHttpFixture` | loopback-only test edge; forbids `publicTls` |
| `services.inspr.routingEdge.allowUnpinnedTraefik` | opt out of the exact-version check, with a warning |
| `services.inspr.routingEdge.deploymentMode` | `managed` (default) or `external-file-provider` |
| `services.inspr.routingEdge.external.certificateResolver` | existing static resolver selector |
| `services.inspr.routingEdge.external.resourceNamespace` | unique generated-object prefix |
| `services.inspr.routingEdge.external.providerFile` | one relative `/etc` fragment path |
| `services.inspr.routingEdge.external.existingTraefikVersion` | consumer-reported existing process version |

```nix
{ config, pkgs, ... }:
{
  imports = [ inputs.inspr-modules.nixosModules.routing-edge ];

  services.inspr.routingEdge = {
    enable = true;
    package = routingEdgePkg;
    traefikPackage = traefik_3_7_12; # consumer-owned pin
    contractFile = ./routing/contract.json;
    publicTls = {
      certFile = "/etc/inspr/tls/public.crt";
      keyFile = "/etc/inspr/tls/public.key";
    };
    upstreams = {
      aithema.url = "https://aithema.internal:8443";
      paimos.url = "https://paimos.internal:8443";
      pharos.url = "https://pharos.internal:8443";
      janus.url = "https://janus.internal:8443";
    };
  };
}
```

External fragment installation:

```nix
services.inspr.routingEdge = {
  enable = true;
  deploymentMode = "external-file-provider";
  package = routingEdgePkg;
  contractFile = ./routing/contract.json;
  entrypoint.name = "existing-websecure";
  external = {
    certificateResolver = "existing-acme";
    resourceNamespace = "inspr-example";
    providerFile = "traefik/dynamic/inspr-example.yml";
    existingTraefikVersion = "3.7.13";
  };
  upstreams = {
    aithema.url = "https://aithema.internal:8443";
    paimos = {
      url = "https://paimos.internal:8443";
      caFile = "/etc/traefik/upstream-ca.crt";
    };
    pharos.url = "https://pharos.internal:8443";
    janus.url = "https://janus.internal:8443";
  };
};
```

The existing Traefik static file must already watch the directory containing
`/etc/traefik/dynamic/inspr-example.yml`, define `existing-websecure` and
`existing-acme`, and be able to read every referenced upstream CA. The module
does not alter that static file or the existing service. NixOS option merging
rejects another declaration that owns the same `environment.etc` file; semantic
Traefik-name collisions across other providers remain the consumer's duty.

#### Validate before listening

`preStart` runs the installed compiler against the contract and a generated
deployment document, writing `dynamic.yml`, `static.yml` and
`wiring-report.json` into `/run/inspr-routing-edge`. An invalid contract or
deployment pair fails the unit with the compiler's findings on stderr, before
any listener exists. Prefix preservation, the generated denial routers, the
dropped identity headers and the unbuffered SSE transports all come from that
compiler output unchanged. `static.yml` names `dynamic.yml` by absolute path,
and the unit's `WorkingDirectory` is the same runtime directory.

Configuration errors that Nix can see are reported as module assertions with a
usable message — missing `publicTls`, no upstreams, a `loopbackHttpFixture`
bound to a public address, a malformed or out-of-range entrypoint port.

#### Traefik compatibility

The compiler emits Traefik **3.7.13** `file-provider-v3.7.13` syntax. The module
reads the supplied package's `version` attribute — the one nixpkgs actually sets,
not `meta.version` — and an assertion fails when it does not match, *including*
when no version can be determined at all. Set `allowUnpinnedTraefik = true` to
proceed anyway; the check then becomes an explicit warning and compatibility is
the operator's claim. Untested versions are not claimed here.

#### Secrets and privileges

TLS material never enters the Nix store and is never read at evaluation or build
time. The option type rejects a relative path or inline PEM content, and the
module passes only *paths* to systemd:

- `LoadCredential=` installs the certificate, the private key and any upstream
  CA bundle into `/run/credentials/inspr-routing-edge.service`, owned by the
  unit's own user. The generated deployment document points Traefik at those
  credential paths. `ReadOnlyPaths` would not do: the service runs with
  `DynamicUser = true` and cannot read a root-owned `0600` key merely because it
  is visible.
- The unit runs unprivileged and sandboxed (`DynamicUser`, `ProtectSystem =
  "strict"`, `NoNewPrivileges`, `PrivateTmp`, `RestrictNamespaces`, a `native`
  syscall architecture and a `@system-service` filter).
- A port below 1024 is bound with `AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ]`
  and a capability bounding set containing nothing else. On any other port every
  capability is dropped.

Certificate issuance and renewal, firewall policy, DNS, SSO enrolment and app
deployment stay outside this module. Live NixOS activation and fleet-specific
deployment remain a separate, operator-owned gate in the consuming repository.

### Focused Nix checks

`pkgs` is required — these checks pin nothing:

```sh
# pure evaluation: mocked module harness + real NixOS module-system eval
nix-instantiate --eval --strict -A report packages/routing-edge/nix/tests \
  --arg pkgs 'import <your-pinned-nixpkgs> { system = builtins.currentSystem; }'

# package build + installed-command proof, run from / with no checkout in reach
nix-build -A packageProof packages/routing-edge/nix/tests \
  --arg pkgs 'import <your-pinned-nixpkgs> { system = builtins.currentSystem; }'
```

These cover a Darwin package build with an installed-command proof outside the
repository checkout, and module evaluation for the disabled, valid,
missing-input and invalid-configuration cases in both modes. The isolated
process test starts a consumer-owned static Traefik configuration with synthetic
loopback TLS and a second provider file, then checks prefix/API/assets/denials,
identity stripping and SSE. It proves fragment loading against the pinned
binary, not certificate issuance, public reachability, NixOS activation, live
upstream TLS or SSO. The NixOS evaluation is **evaluation only**: nothing builds
or activates a NixOS system on macOS.
