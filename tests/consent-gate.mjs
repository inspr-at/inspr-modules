#!/usr/bin/env node
// consent-gate core tests (INSPR-431). Runs under plain Node: the core has no
// DOM dependency. Browser behaviour is covered by the consuming surface's own
// browser suite (the primitive ships a reference suite in its README).
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import vm from "node:vm";
import assert from "node:assert/strict";

const here = dirname(fileURLToPath(import.meta.url));
const source = readFileSync(join(here, "..", "packages", "consent-gate", "consent-gate.js"), "utf8");
const sandbox = {};
vm.createContext(sandbox);
vm.runInContext(source, sandbox, { filename: "consent-gate.js" });
const core = sandbox.insprConsentCore;
assert.ok(core, "core exported without a DOM");
const plain = (v) => JSON.parse(JSON.stringify(v));

const example = JSON.parse(readFileSync(join(here, "..", "packages", "consent-gate", "example", "manifest.json"), "utf8"));

// ---- manifest validation --------------------------------------------------
assert.deepEqual(plain(core.validateManifest(example)), { ok: true, errors: [] }, "example manifest is valid");
assert.equal(core.validateManifest(null).ok, false);
assert.equal(core.validateManifest({}).ok, false);
{
  const m = plain(example); m.revision = 0;
  assert.ok(core.validateManifest(m).errors.some((e) => /revision/.test(e)));
}
{
  const m = plain(example); m.categories[0].required = false; // no required category
  assert.ok(core.validateManifest(m).errors.some((e) => /exactly one category must be required/.test(e)));
}
{
  const m = plain(example); m.services[0].category = "necessary";
  assert.ok(core.validateManifest(m).errors.some((e) => /required category/.test(e)), "optional services cannot hide in the required category");
}
{
  const m = plain(example); m.services[0].destination.consent = ["ad_storage", "bogus"];
  assert.ok(core.validateManifest(m).errors.some((e) => /Consent Mode keys/.test(e)));
}
{
  const m = plain(example); delete m.text.en.bar.reject;
  assert.ok(core.validateManifest(m).errors.some((e) => /bar\.reject missing/.test(e)));
}
{
  const m = plain(example); m.services.push({ id: "twice", category: "marketing", provider: "x", destination: { type: "gtag", tagId: "AW-0", consent: ["ad_storage"] }, embed: { host: "x.invalid" } });
  assert.ok(core.validateManifest(m).errors.some((e) => /exactly one of destination or embed/.test(e)));
}

// ---- tiers ----------------------------------------------------------------
assert.equal(core.tierOf(example), "bar");
{
  const m = plain(example); m.services = m.services.filter((s) => s.embed);
  assert.equal(core.tierOf(m), "contextual", "only embeds → contextual");
  m.services = [];
  assert.equal(core.tierOf(m), "none", "no optional services → nothing rendered");
}

// ---- storage format -------------------------------------------------------
const now = 1_800_000_000;
assert.equal(core.serialize(["marketing", "measurement"], 3, now), "v1;r=3;g=marketing,measurement;t=1800000000");
assert.deepEqual(plain(core.parse("v1;r=3;g=marketing,measurement;t=1800000000")), { revision: 3, granted: ["marketing", "measurement"], at: 1800000000 });
assert.deepEqual(plain(core.parse("v1;r=1;g=;t=5")), { revision: 1, granted: [], at: 5 });
assert.equal(core.parse("garbage"), null);
assert.equal(core.parse(""), null);
assert.ok(!/uuid|random/i.test(core.serialize(["marketing"], 1, now)), "no generated identifier in the stored value");

// ---- decide ---------------------------------------------------------------
const d = (extra) => plain(core.decide({ manifest: example, now, signal: false, bot: false, stored: null, ...extra }));
assert.deepEqual(d({}), { tier: "bar", prompt: true, granted: { measurement: false, marketing: false, embeds: false }, persist: "none" }, "fresh visitor: prompt, nothing granted");
assert.deepEqual(d({ stored: core.parse(core.serialize(["measurement"], 1, now - 10)) }).granted, { measurement: true, marketing: false, embeds: false }, "partial grant honoured");
assert.deepEqual(d({ stored: core.parse(core.serialize(["measurement", "marketing"], 1, now - 10)) }).granted, { measurement: true, marketing: true, embeds: false });
assert.equal(d({ stored: core.parse(core.serialize([], 1, now - 10)) }).prompt, false, "stored refusal: no prompt");
assert.deepEqual(d({ stored: core.parse(core.serialize(["marketing"], 1, now - 10)), signal: true }), { tier: "bar", prompt: false, granted: { measurement: false, marketing: false, embeds: false }, persist: "refuse" }, "GPC/DNT overrides an older grant and persists a refusal");
assert.equal(d({ bot: true }).prompt, false, "bots: no prompt");
assert.equal(d({ bot: true }).granted.marketing, false);
assert.equal(d({ stored: core.parse(core.serialize(["marketing"], 1, now - 181 * 86400)) }).prompt, true, "expired grant re-asks");
assert.equal(d({ stored: core.parse(core.serialize([], 1, now - 179 * 86400)) }).prompt, false, "refusal inside the window stays");
assert.equal(d({ stored: core.parse(core.serialize(["marketing"], 0, now - 10)) }).prompt, true, "a material purpose revision re-asks");
assert.equal(d({ stored: core.parse(core.serialize(["marketing"], 1, now - 10)), revoked: true }).granted.marketing, false, "a revocation outranks a surviving grant");
{
  const m = plain(example); m.services = m.services.filter((s) => s.embed);
  assert.equal(core.decide({ manifest: m, now, signal: false, bot: false, stored: null }).prompt, false, "contextual tier never prompts with a bar");
}

// ---- Consent Mode signals -------------------------------------------------
{
  const sig = plain(core.consentModeSignals(example, { measurement: true, marketing: false, embeds: false }));
  assert.equal(sig.defaults.ad_storage, "denied");
  assert.equal(sig.update.analytics_storage, "granted");
  assert.equal(sig.update.ad_storage, "denied", "marketing not granted → ad keys stay denied");
  assert.equal(sig.update.ad_personalization, "denied", "an undeclared purpose can never be granted");
  const both = plain(core.consentModeSignals(example, { measurement: true, marketing: true, embeds: false }));
  assert.equal(both.update.ad_storage, "granted");
  assert.equal(both.update.ad_user_data, "granted");
  assert.equal(both.update.ad_personalization, "denied");
}

// ---- createCore with a fake environment -----------------------------------
function fakeEnv(opts = {}) {
  const state = { cookies: {}, session: {}, local: { _gcl_ls: "seeded" }, signal: false, bot: false, now, cleared: [] };
  return {
    state,
    now: () => state.now,
    readCookie: (n) => { if (opts.readThrows) throw new Error("jar"); return state.cookies[n] ?? null; },
    writeCookie: (n, v) => { if (opts.writeThrows) throw new Error("jar"); if (opts.writeDrops) return true; state.cookies[n] = v; return true; },
    clearCookie: (p) => { state.cleared.push(p); Object.keys(state.cookies).forEach((k) => { if (new RegExp("^" + p.replace(/\*/g, ".*") + "$").test(k)) delete state.cookies[k]; }); },
    readSession: (k) => state.session[k] ?? null,
    writeSession: (k, v) => { if (opts.sessionThrows) throw new Error("session"); state.session[k] = v; return true; },
    removeSession: (k) => { delete state.session[k]; },
    removeLocal: (k) => { delete state.local[k]; },
    signal: () => state.signal,
    bot: () => state.bot,
  };
}

{
  const env = fakeEnv();
  const c = core.createCore(example, env);
  assert.equal(c.valid, true);
  assert.equal(c.tier, "bar");
  assert.equal(c.boot().prompt, true);
  assert.equal(c.authorized("necessary"), true, "the required category is always authorised");
  assert.equal(c.authorized("marketing"), false);
  // partial grant: measurement only
  assert.equal(c.grant(["measurement"]).ok, true);
  assert.equal(c.authorized("measurement"), true);
  assert.equal(c.authorized("marketing"), false);
  assert.equal(c.signals().update.analytics_storage, "granted");
  assert.equal(c.signals().update.ad_storage, "denied");
  // extend to marketing, then drop measurement: only measurement storage is cleaned
  assert.equal(c.grant(["measurement", "marketing"]).ok, true);
  env.state.cookies._gcl_au = "x"; env.state.cookies._ga = "y";
  assert.equal(c.grant(["marketing"]).ok, true);
  assert.equal(c.authorized("measurement"), false);
  assert.equal(c.authorized("marketing"), true);
  assert.ok(!("_ga" in env.state.cookies), "dropping measurement clears its declared cookies");
  assert.ok("_gcl_au" in env.state.cookies, "marketing storage untouched while marketing stays granted");
  // withdraw everything: all declared storage of optional categories goes
  assert.equal(c.withdraw(), true);
  assert.ok(!("_gcl_au" in env.state.cookies) && !("_gcl_ls" in env.state.local), "withdrawal clears cookies and local storage of every optional category");
  assert.equal(c.current().prompt, false, "a stored refusal does not re-prompt");
  assert.equal(c.authorized("marketing"), false);
}

{
  // GPC: boot persists a refusal over an older grant; grant() is refused while the signal is active
  const env = fakeEnv();
  env.state.cookies.consent = core.serialize(["marketing"], 1, now - 10);
  env.state.signal = true;
  const c = core.createCore(example, env);
  const d0 = c.boot();
  assert.equal(d0.granted.marketing, false);
  assert.ok(env.state.cookies.consent.includes("g=;"), "refusal persisted over the older grant");
  assert.equal(c.grant(["marketing"]).ok, false, "no grant while a privacy signal is active");
  env.state.signal = false;
  assert.equal(c.authorized("marketing"), false, "signal disappearance does not revive the superseded grant");
}

{
  // Storage failure: dropped cookie writes → grant fails closed; refusal falls back to the session flag
  const env = fakeEnv({ writeDrops: true });
  const c = core.createCore(example, env);
  const r = c.grant(["marketing"]);
  assert.equal(r.ok, false, "a grant that cannot be read back is no grant");
  assert.equal(c.authorized("marketing"), false);
  assert.equal(env.state.session[c.revokeKey], "1", "refusal recorded in the session when the cookie jar drops writes");
}
{
  // Throwing cookie jar: nothing loads, nothing throws out of the core
  const env = fakeEnv({ readThrows: true, writeThrows: true });
  const c = core.createCore(example, env);
  assert.doesNotThrow(() => c.boot());
  assert.equal(c.authorized("marketing"), false);
  assert.equal(c.grant(["marketing"]).ok, false);
  assert.doesNotThrow(() => c.withdraw());
}
{
  // Session revocation from a previous page outranks a surviving grant cookie
  const env = fakeEnv();
  env.state.cookies.consent = core.serialize(["marketing"], 1, now - 10);
  env.state.session["consent_revoked"] = "1";
  const c = core.createCore(example, env);
  assert.equal(c.boot().granted.marketing, false);
  assert.equal(c.authorized("marketing"), false);
  // an explicit new grant clears the revocation
  assert.equal(c.grant(["marketing"]).ok, true);
  assert.equal(c.authorized("marketing"), true);
  assert.equal(env.state.session["consent_revoked"], undefined);
}

{
  // Embeds: load once vs remembered permission
  const env = fakeEnv();
  const c = core.createCore(example, env);
  c.boot();
  assert.equal(c.authorizedService("video"), false);
  assert.equal(c.loadOnce("video"), true);
  assert.equal(c.authorizedService("video"), true, "load once authorises this page view");
  assert.equal(c.authorized("embeds"), false, "…without persisting a category grant");
  const c2 = core.createCore(example, env);
  assert.equal(c2.authorizedService("video"), false, "load once does not carry into the next page view");
  assert.equal(c2.grant(["embeds"]).ok, true);
  assert.equal(c2.authorizedService("video"), true, "remembered permission covers the service");
  assert.equal(c2.authorizedService("ads"), false, "…but no other category");
  env.state.signal = true;
  assert.equal(c2.authorizedService("video"), false, "a privacy signal blocks embeds too");
  assert.equal(c2.loadOnce("video"), false);
}

{
  // Bots: nothing authorised, nothing prompted, nothing persisted
  const env = fakeEnv();
  env.state.bot = true;
  const c = core.createCore(example, env);
  assert.equal(c.boot().prompt, false);
  assert.equal(c.grant(["marketing"]).ok, false);
  assert.deepEqual(env.state.cookies, {});
}

{
  // Invalid manifest: gate closed, no prompt, no authorisation, no exceptions
  const env = fakeEnv();
  const c = core.createCore({ version: 1 }, env);
  assert.equal(c.valid, false);
  assert.ok(c.errors.length > 0);
  assert.equal(c.tier, "none");
  assert.equal(c.boot().prompt, false);
  assert.equal(c.authorized("marketing"), false);
  assert.equal(c.grant(["marketing"]).ok, false);
  assert.deepEqual(env.state.cookies, {});
}

// ---- browser part invariants (static) -------------------------------------
assert.equal((source.match(/googletagmanager\.com/g) || []).length, 1, "exactly one gated reference to Google's host");
assert.ok(/gtag\("consent", "default", sig\.defaults\)/.test(source) && /gtag\("consent", "update", sig\.update\)/.test(source), "Consent Mode basic: default denied, update after the grant");
assert.ok(/if \(!core\.authorized\(s\.category\)\) return;/.test(source), "the destination loader re-checks authorisation");
assert.ok(/cookie_domain: location\.hostname/.test(source), "destination cookies stay on the consenting host");
assert.ok(/if \(d\.prompt && !env\.bot\(\)\) renderBar\(\);/.test(source), "hiding the bar from bots never touches the loader");
assert.ok(!/uuid|crypto\.randomUUID/.test(source), "no generated identifiers anywhere");

console.log("consent-gate core: ok");
