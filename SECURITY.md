# Security policy

Security maintenance focuses on the latest calendar release
(`vYYMMDDhhmmss.0.0`). Reproduce reports on that release when possible;
earlier releases and archived history do not have a separate maintenance lane.
See the README for the tested dependency baseline; it is not a compatibility
guarantee.

Report vulnerabilities privately through GitHub's **Report a vulnerability**
on this repository's [Security page](https://github.com/inspr-at/inspr-modules/security/advisories/new)
(private vulnerability reporting). Avoid public issues for undisclosed security
problems.

Include the affected calendar tag or commit, module/package/check, Nix and
dependency versions, impact, prerequisites, and minimal reproduction steps or
a proof of concept. Remove credentials and private operator data from examples.

Scope includes this repository's modules, packages, scripts, bundled doctrine
and release/check tooling. Consumer configuration, private infrastructure and
upstream dependencies are maintained by their owners; explain any interaction
with this repository when reporting them here.
