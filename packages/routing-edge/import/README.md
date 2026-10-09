# routing-edge closed import boundary

This directory holds the commit-bound Git-blob import recipe for the reviewed
48-file public routing slice. It is not a general release framework.

## Algorithms

**Tree digest (`source_tree_digest`)** — SHA256 of sorted lines `"{file_sha256}  {path}"`.
This is an inventory digest over pinned blob content, not archive bytes.

**Archive attestation (`source_archive_sha256`)** — SHA256 of the actual bytes in
the deterministic GNU ustar tar emitted during import (`gnu-ustar-deterministic-v1`,
`mtime=0`, `uid/gid=0`, sorted paths). The archive is written only into an
explicit empty output directory and is **not** committed to the public repo.

**Public verification** recomputes the tree digest from `import-receipt.json`,
checks non-adapted public files against receipt digests, validates the closed
metadata inventory, and matches provenance to receipt archive attestation.
It does not claim to verify unavailable archive bytes.

**Actual archive byte proof** runs during import via
`tests/routing-edge-import-source-proof.sh` against the pinned private git blobs.

## Import (root-owned, does not rewrite public source)

```sh
export INSPR_ROUTING_SOURCE_REPO=/path/to/private/inspr-checkout
export INSPR_ROUTING_STAGING_ROOT=/empty/staging/dir
export INSPR_ROUTING_ARCHIVE_DIR=/empty/archive/dir
./packages/routing-edge/import/import-from-source.sh
```

Copy from `INSPR_ROUTING_STAGING_ROOT` into the public tree only after review.
Public adaptations remain tracked separately in `public-adaptations.json`.

## Verify committed public boundary

```sh
python3 packages/routing-edge/import/boundary.py verify --repo-root .
bash tests/routing-edge-import-surface.sh .
python3 -m unittest tests/test_routing_edge_import_boundary.py -v
```
