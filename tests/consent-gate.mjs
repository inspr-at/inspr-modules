#!/usr/bin/env node
// consent-gate core tests (INSPR-431). Runs under plain Node: the core has no
// DOM dependency. Browser behaviour is proven by the consuming surface's own
// browser suite (see the package README).
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import vm from "node:vm";
import assert from "node:assert/strict";

const here = dirname(fileURLToPath(import.meta.url));
const pkg = join(here, "..", "packages", "consent-gate");
const source = readFileSync(join(pkg, "consent-gate.js"), "utf8");
const sandbox = {};
vm.createContext(sandbox);
vm.runInContext(source, sandbox, { filename: "consent-gate.js" });
const core = sandbox.insprConsentCore;
assert.ok(core, "core exported without a DOM");
const plain = (v) => JSON.parse(JSON.stringify(v));
const example = JSON.parse(readFileSync(join(pkg, "example", "manifest.json"), "utf8"));
const embedded = JSON.parse(/<script type="application\/json" id="consent-manifest">\s*([\s\S]*?)\s*<\/script>/.exec(readFileSync(join(pkg, "example", "example.html"), "utf8"))[1]);
assert.deepEqual(embedded, example, "example.html embeds the example manifest verbatim");
const now = 1_800_000_000;
const rec = (granted, extra = {}) => ({ revision: 1, textVersion: 1, granted, services: [], at: now - 10, ...extra });

// ---- manifest validation --------------------------------------------------
assert.deepEqual(plain(core.validateManifest(example)), { ok: true, errors: [] }, "example manifest is valid");
const invalidCases = [
  [null, /object/],
  [{}, /version/],
  [{ ...example, revision: 0 }, /revision/],
  [{ ...example, textVersion: undefined }, /textVersion/],
  [{ ...example, controller: "" }, /controller/],
  [{ ...example, scope: "not a host" }, /scope/],
  [{ ...example, services: undefined }, /services must be an array/],
  [{ ...example, services: {} }, /services must be an array/],
  [{ ...example, categories: example.categories.map((c) => ({ ...c, required: false })) }, /exactly one category must be required/],
  [{ ...example, services: [{ ...example.services[0], category: "necessary" }] }, /required category/],
  [{ ...example, services: [{ ...example.services[0], destination: { ...example.services[0].destination, consent: ["ad_storage", "bogus"] } }] }, /Consent Mode keys/],
  [{ ...example, services: [{ ...example.services[0], destination: { ...example.services[0].destination, tagId: "" } }] }, /tagId invalid/],
  [{ ...example, services: [{ ...example.services[1], destination: { ...example.services[1].destination, conversion: { sendTo: "AW-999999999/undeclared" } } }] }, /conversion\.sendTo must be <tagId>/],
  [{ ...example, services: [{ ...example.services[1], destination: { ...example.services[1].destination, conversion: "x" } }] }, /conversion\.sendTo/],
  [{ ...example, services: [{ ...example.services[0], purposes: [] }] }, /purposes/],
  [{ ...example, services: [{ ...example.services[0], embed: { host: "x.example" } }] }, /exactly one of destination or embed/],
  [{ ...example, services: [{ ...example.services[2], embed: { host: "not a host" } }] }, /embed\.host/],
  [{ ...example, services: [{ ...example.services[1], storage: [{ kind: "cookie", name: "_gcl_*", domain: "other.invalid" }] }] }, /domain must be the scope host/],
  [{ ...example, services: [{ ...example.services[1], storage: [{ kind: "local", name: "x", path: "/" }] }] }, /apply to cookies only/],
  [{ ...example, privacyUrl: "javascript:alert(1)" }, /privacyUrl/],
  [{ ...example, privacyUrl: "http://plain.example/" }, /privacyUrl/],
  [{ ...example, refusalDays: 30 }, /refusalDays must be at least 183/],
  [{ ...example, permissionDays: 0 }, /permissionDays/],
  [{ ...example, text: { en: { ...example.text.en, bar: { ...example.text.en.bar, reject: undefined } } } }, /bar\.reject missing/],
  [{ ...example, text: { en: { ...example.text.en, services: {} } } }, /services\.video\.label missing/],
  [{ ...example, language: "fr" }, /language fr has no text/],
];
for (const [m, re] of invalidCases) {
  const v = core.validateManifest(m);
  assert.equal(v.ok, false, `invalid: ${re}`);
  assert.ok(v.errors.some((e) => re.test(e)), `expected ${re} in ${JSON.stringify(v.errors)}`);
}

// ---- URL safety -----------------------------------------------------------
assert.equal(core.safeUrl("javascript:alert(1)"), null);
assert.equal(core.safeUrl("http://plain.example/"), null);
assert.equal(core.safeUrl("//evil.example/"), null);
assert.equal(core.safeUrl("/privacy"), "/privacy");
assert.equal(core.safeUrl("https://video.example.invalid/embed/1"), "https://video.example.invalid/embed/1");

// ---- tiers ----------------------------------------------------------------
assert.equal(core.tierOf(example), "bar");
{
  const m = plain(example); m.services = m.services.filter((s) => s.embed);
  assert.equal(core.tierOf(m), "contextual");
  m.services = [];
  assert.equal(core.tierOf(m), "none");
}

// ---- storage format -------------------------------------------------------
const value = core.serialize({ revision: 3, textVersion: 2, granted: ["marketing", "measurement"], services: ["video"], at: now });
assert.equal(value, "v1;r=3;v=2;g=marketing,measurement;s=video;t=1800000000");
assert.deepEqual(plain(core.parse(value)), { revision: 3, textVersion: 2, granted: ["marketing", "measurement"], services: ["video"], at: now });
assert.deepEqual(plain(core.parse("v1;r=1;v=1;g=;s=;t=5")), { revision: 1, textVersion: 1, granted: [], services: [], at: 5 });
for (const bad of ["garbage", "", "v1;r=1garbage;v=1;g=;s=;t=1800000000garbage", "v1;r=1;v=1;g=;s=;t=1800000000;t=1", "v1;r=1;v=1;g=Bad Token;s=;t=1", "v1;r=1;v=1;g=;t=1", "v2;r=1;v=1;g=;s=;t=1", "v1;r=99999999999999;v=1;g=;s=;t=1"]) {
  assert.equal(core.parse(bad), null, `strict parse rejects ${JSON.stringify(bad)}`);
}
assert.ok(!/uuid|random/i.test(value), "no generated identifier in the stored value");

// ---- decide ---------------------------------------------------------------
const d = (extra) => plain(core.decide({ manifest: example, now, signal: false, bot: false, stored: null, ...extra }));
const noneGranted = { measurement: false, marketing: false, embeds: false };
assert.deepEqual(d({}), { tier: "bar", prompt: true, granted: noneGranted, services: [], persist: "none" }, "fresh visitor: prompt, nothing granted");
assert.deepEqual(d({ stored: rec(["measurement"]) }).granted, { measurement: true, marketing: false, embeds: false }, "partial grant honoured");
assert.deepEqual(d({ stored: rec(["measurement", "marketing"]) }).granted, { measurement: true, marketing: true, embeds: false });
assert.deepEqual(d({ stored: rec([], { services: ["video"] }) }).services, ["video"], "a remembered service is honoured without its category");
assert.deepEqual(d({ stored: rec(["embeds"], { services: ["video"] }) }).services, [], "a remembered service folds into its granted category");
assert.equal(d({ stored: rec([]) }).prompt, false, "stored refusal: no prompt");
assert.deepEqual(d({ stored: rec(["marketing"]), signal: true }), { tier: "bar", prompt: false, granted: noneGranted, services: [], persist: "refuse" }, "GPC/DNT overrides an older grant and persists a refusal");
assert.equal(d({ bot: true }).prompt, false);
assert.equal(d({ bot: true }).granted.marketing, false);
assert.equal(d({ blocked: true }).prompt, false, "a blocked accessor closes the gate silently");
assert.equal(d({ stored: rec(["marketing"], { at: now - 181 * 86400 }) }).prompt, true, "expired permission re-asks");
assert.equal(d({ stored: rec([], { at: now - 181 * 86400 }) }).prompt, false, "a refusal outlives the permission lifetime");
assert.equal(d({ stored: rec([], { at: now - 184 * 86400 }) }).prompt, true, "a refusal expires after at least six months");
assert.equal(d({ stored: rec(["marketing"], { revision: 0 }) }).prompt, true, "a material purpose revision re-asks");
assert.equal(d({ stored: rec(["marketing"], { at: now + 60 }) }).granted.marketing, false, "a future-dated decision authorises nothing");
assert.equal(d({ stored: rec(["marketing"], { at: now + 60 }) }).prompt, true);
assert.equal(d({ stored: rec(["marketing"]), now: NaN }).granted.marketing, false, "a broken clock authorises nothing");
assert.equal(d({ stored: rec(["marketing"]), revoked: true }).granted.marketing, false, "a revocation outranks a surviving grant");
{
  const m = plain(example); m.permissionDays = 7;
  assert.equal(core.decide({ manifest: m, now, signal: false, bot: false, stored: rec(["marketing"], { at: now - 8 * 86400 }) }).prompt, true, "short permission lifetime expires");
  assert.equal(core.decide({ manifest: m, now, signal: false, bot: false, stored: rec([], { at: now - 100 * 86400 }) }).prompt, false, "…while the refusal keeps its six months");
}
{
  const m = plain(example); m.services = m.services.filter((s) => s.embed);
  assert.equal(core.decide({ manifest: m, now, signal: false, bot: false, stored: null }).prompt, false, "contextual tier never prompts with a bar");
}

// ---- Consent Mode signals & hosts ----------------------------------------
{
  const sig = plain(core.consentModeSignals(example, { measurement: true, marketing: false, embeds: false }));
  assert.equal(sig.defaults.ad_storage, "denied");
  assert.equal(sig.defaults.security_storage, "denied");
  assert.equal(sig.update.analytics_storage, "granted");
  assert.equal(sig.update.ad_storage, "denied");
  assert.equal(sig.update.ad_personalization, "denied", "an undeclared purpose can never be granted");
  const both = plain(core.consentModeSignals(example, { measurement: true, marketing: true, embeds: false }));
  assert.equal(both.update.ad_storage, "granted");
  assert.equal(both.update.ad_user_data, "granted");
  assert.equal(both.update.ad_personalization, "denied");
  assert.deepEqual(plain(core.declaredHosts(example)).sort(), ["googleads.g.doubleclick.net", "pagead2.googlesyndication.com", "video.example.invalid", "www.google-analytics.com", "www.google.com", "www.googletagmanager.com"]);
}

// ---- pre-consent guard ----------------------------------------------------
{
  const inert = readFileSync(join(pkg, "example", "example.html"), "utf8");
  const g1 = core.guardServedHtml({ manifest: example, html: inert, requests: ["https://self.example/assets/consent-gate.js", "https://self.example/"] });
  assert.deepEqual(plain(g1.violations), [], "inert manifest, data-src and the gate script pass");
  assert.equal(g1.ok, true);
  const active = inert.replace('data-src="https://video.example.invalid/embed/1"', 'src="https://video.example.invalid/embed/1"');
  const g2 = core.guardServedHtml({ manifest: example, html: active, requests: [] });
  assert.equal(g2.ok, false);
  assert.deepEqual(plain(g2.violations), [{ kind: "markup", element: "iframe", attribute: "src", url: "https://video.example.invalid/embed/1" }], "a live embed src fails");
  const tracker = inert + '<script async src="https://www.googletagmanager.com/gtag/js?id=AW-000000000"></script>';
  assert.equal(core.guardServedHtml({ manifest: example, html: tracker, requests: [] }).violations[0].element, "script", "a tag loader in served HTML fails");
  const g4 = core.guardServedHtml({ manifest: example, html: inert, requests: ["https://googleads.g.doubleclick.net/pagead/viewthroughconversion/1"] });
  assert.deepEqual(plain(g4.violations), [{ kind: "request", url: "https://googleads.g.doubleclick.net/pagead/viewthroughconversion/1" }], "a pre-consent request to a declared host fails");
  assert.equal(core.guardServedHtml({ manifest: example, html: '<img src="https://sub.video.example.invalid/t.png">', requests: [] }).ok, false, "subdomains of a declared host count");
  assert.equal(core.guardServedHtml({ manifest: example, html: '<a href="https://video.example.invalid/">watch</a><link rel="stylesheet" href="/style.css">', requests: [] }).ok, true, "plain anchors and same-origin links are inert");
}

// ---- createCore with a fake environment -----------------------------------
function fakeEnv(opts = {}) {
  const state = { cookies: {}, session: {}, local: { _gcl_ls: "seeded" }, signal: false, bot: false, now, cleared: [] };
  return {
    state,
    now: () => { if (opts.clockThrows) throw new Error("clock"); return state.now; },
    readCookie: (n) => { if (opts.readThrows) throw new Error("jar"); return state.cookies[n] ?? null; },
    writeCookie: (n, v) => { if (opts.writeThrows) throw new Error("jar"); if (opts.writeDrops) return true; state.cookies[n] = v; return true; },
    clearCookie: (st) => { state.cleared.push(st); Object.keys(state.cookies).forEach((k) => { if (new RegExp("^" + st.name.replace(/\*$/, ".*") + "$").test(k)) delete state.cookies[k]; }); },
    readSession: (k) => { if (opts.sessionReadThrows) throw new Error("session"); return state.session[k] ?? null; },
    writeSession: (k, v) => { if (opts.sessionWriteThrows) throw new Error("session"); state.session[k] = v; return true; },
    removeSession: (k) => { delete state.session[k]; },
    removeLocal: (k) => { delete state.local[k]; },
    signal: () => { if (opts.signalThrows) throw new Error("signal"); return state.signal; },
    bot: () => state.bot,
  };
}

{
  const env = fakeEnv();
  const c = core.createCore(example, env);
  assert.equal(c.valid, true);
  assert.equal(c.tier, "bar");
  assert.equal(c.boot().prompt, true);
  assert.equal(c.authorized("necessary"), true);
  assert.equal(c.authorized("marketing"), false);
  assert.equal(c.grant(["measurement"]).ok, true, "partial grant: measurement only");
  assert.equal(c.authorized("measurement"), true);
  assert.equal(c.authorized("marketing"), false);
  assert.equal(c.signals().update.analytics_storage, "granted");
  assert.equal(c.signals().update.ad_storage, "denied");
  assert.equal(c.grant(["measurement", "marketing"]).ok, true);
  env.state.cookies._gcl_au = "x"; env.state.cookies._ga = "y"; env.state.session[`consent_fired_ads`] = "1";
  assert.equal(c.grant(["marketing"]).ok, true, "dropping measurement");
  assert.ok(!("_ga" in env.state.cookies), "dropping measurement clears its declared cookies");
  assert.ok("_gcl_au" in env.state.cookies, "marketing storage untouched while marketing stays granted");
  assert.deepEqual(plain(env.state.cleared.at(-1)), { name: "_ga*", path: "/", domain: null }, "cleanup passes the declared descriptor, host-only, at the declared path");
  let seen = null; c.onChange((dd) => { seen = dd; });
  assert.equal(c.withdraw(), true);
  assert.ok(seen && seen.granted.marketing === false, "listeners see the withdrawal");
  assert.ok(!("_gcl_au" in env.state.cookies) && !("_gcl_ls" in env.state.local) && !("consent_fired_ads" in env.state.session), "withdrawal clears cookies, local storage and the adapter's conversion marker");
  assert.equal(c.current().prompt, false, "a stored refusal does not re-prompt");
}

{
  // Teardown callbacks run when a service loses authorisation
  const env = fakeEnv();
  const c = core.createCore(example, env);
  const calls = [];
  c.registerTeardown("video", () => calls.push("video"));
  c.registerTeardown("ads", () => calls.push("ads"));
  assert.equal(c.grant(["embeds", "marketing"]).ok, true);
  assert.equal(c.grant(["marketing"]).ok, true);
  assert.deepEqual(calls, ["video"], "only the dropped service is torn down");
  c.withdraw();
  assert.deepEqual(calls, ["video", "ads", "video"], "withdrawal tears every service down in manifest order");
}

{
  // GPC: boot persists a refusal over an older grant; grant() is refused while the signal is active
  const env = fakeEnv();
  env.state.cookies.consent = core.serialize(rec(["marketing"]));
  env.state.signal = true;
  const c = core.createCore(example, env);
  assert.equal(c.boot().granted.marketing, false);
  assert.ok(env.state.cookies.consent.includes(";g=;s=;"), "refusal persisted over the older grant");
  assert.equal(c.grant(["marketing"]).ok, false, "no grant while a privacy signal is active");
  env.state.signal = false;
  assert.equal(c.authorized("marketing"), false, "signal disappearance does not revive the superseded grant");
}

{
  // Storage failure: dropped cookie writes → grant fails closed; refusal falls back to the session flag
  const env = fakeEnv({ writeDrops: true });
  const c = core.createCore(example, env);
  assert.equal(c.grant(["marketing"]).ok, false, "a grant that cannot be read back is no grant");
  assert.equal(c.authorized("marketing"), false);
  assert.equal(env.state.session[c.revokeKey], "1", "refusal recorded in the session when the cookie jar drops writes");
}
{
  // Withdrawal whose refusal cannot be stored anywhere reports failure (the renderer then must not reload)
  const env = fakeEnv({ writeDrops: true, sessionWriteThrows: true });
  env.state.cookies.consent = core.serialize(rec(["marketing"]));
  const c = core.createCore(example, env);
  assert.equal(c.boot().granted.marketing, true);
  assert.equal(c.grant([]).ok, false, "grant([]) reports the persistence failure");
  assert.equal(c.withdraw(), false);
  assert.equal(c.authorized("marketing"), false, "…but the in-page revocation holds");
}
{
  // Throwing accessors: nothing loads, nothing throws out of the core
  for (const opts of [{ readThrows: true, writeThrows: true }, { sessionReadThrows: true }, { signalThrows: true }, { clockThrows: true }]) {
    const env = fakeEnv(opts);
    env.state.cookies.consent = core.serialize(rec(["marketing"]));
    const c = core.createCore(example, env);
    assert.doesNotThrow(() => c.boot(), JSON.stringify(opts));
    assert.equal(c.authorized("marketing"), false, `no authorisation under ${JSON.stringify(opts)}`);
    assert.equal(c.grant(["marketing"]).ok, false);
    assert.doesNotThrow(() => c.withdraw());
  }
}
{
  // Session revocation from a previous page outranks a surviving grant cookie; a new grant clears it
  const env = fakeEnv();
  env.state.cookies.consent = core.serialize(rec(["marketing"]));
  env.state.session["consent_revoked"] = "1";
  const c = core.createCore(example, env);
  assert.equal(c.boot().granted.marketing, false);
  assert.equal(c.grant(["marketing"]).ok, true);
  assert.equal(c.authorized("marketing"), true);
  assert.equal(env.state.session["consent_revoked"], undefined);
}

{
  // Embeds: instance-bound load once, service-scoped remembered permission
  const env = fakeEnv();
  const c = core.createCore(example, env);
  c.boot();
  const a = { id: "iframe-a" }, b = { id: "iframe-b" };
  assert.equal(c.authorizedInstance("video", a), false);
  assert.equal(c.loadOnce("video", a), true);
  assert.equal(c.authorizedInstance("video", a), true, "load once authorises this instance");
  assert.equal(c.authorizedInstance("video", b), false, "…not a second instance of the same service");
  assert.equal(c.authorized("embeds"), false, "…and persists no category grant");
  assert.equal(c.grant(["measurement"]).ok, true, "saving measurement only");
  assert.equal(c.authorizedInstance("video", b), false, "does not open other embed instances");
  const c2 = core.createCore(example, env);
  assert.equal(c2.authorizedInstance("video", a), false, "load once does not carry into the next page view");
  assert.equal(c2.grantService("video").ok, true, "always allow remembers the named service");
  assert.equal(c2.authorizedService("video"), true);
  assert.equal(c2.authorized("embeds"), false, "…without granting its whole category");
  const m2 = plain(example); m2.services.push({ id: "map", category: "embeds", provider: "Example Maps", purposes: ["map"], embed: { host: "maps.example.invalid" } }); m2.text.en.services.map = { label: "Map" };
  const c3 = core.createCore(m2, env);
  assert.equal(c3.authorizedService("video"), true);
  assert.equal(c3.authorizedService("map"), false, "another provider in the same category stays closed");
  assert.equal(c3.grant(["measurement"]).ok, true, "a category grant elsewhere keeps the remembered service");
  assert.equal(c3.authorizedService("video"), true);
  assert.equal(c3.grant(["measurement", "embeds"]).ok, true);
  assert.equal(c3.authorizedService("map"), true, "granting the category opens every service in it");
  assert.equal(c3.grant(["measurement"]).ok, true, "dropping the category drops its remembered services too");
  assert.equal(c3.authorizedService("video"), false);
  env.state.signal = true;
  assert.equal(c3.loadOnce("video", a), false, "a privacy signal blocks load once");
  assert.equal(c3.authorizedInstance("video", a), false);
}

{
  // Bots: nothing authorised, nothing prompted, nothing persisted
  const env = fakeEnv();
  env.state.bot = true;
  const c = core.createCore(example, env);
  assert.equal(c.boot().prompt, false);
  assert.equal(c.grant(["marketing"]).ok, false);
  assert.equal(c.loadOnce("video", {}), false);
  assert.deepEqual(env.state.cookies, {});
}

{
  // Invalid manifest: gate closed, no prompt, no authorisation, no exceptions
  for (const bad of [{ version: 1 }, { ...example, services: undefined }, { ...example, services: {} }]) {
    const env = fakeEnv();
    const c = core.createCore(bad, env);
    assert.equal(c.valid, false);
    assert.ok(c.errors.length > 0);
    assert.equal(c.tier, "none");
    assert.doesNotThrow(() => c.boot());
    assert.equal(c.boot().prompt, false);
    assert.equal(c.authorized("marketing"), false);
    assert.equal(c.grant(["marketing"]).ok, false);
    assert.doesNotThrow(() => c.withdraw());
    assert.deepEqual(env.state.cookies, {});
  }
}

// ---- browser part invariants (static) -------------------------------------
assert.equal((source.match(/googletagmanager\.com\/gtag\/js/g) || []).length, 1, "exactly one gated reference to the tag loader");
assert.ok(/gtag\("consent", "default", sig\.defaults\)/.test(source) && /gtag\("consent", "update", sig\.update\)/.test(source), "Consent Mode basic: default denied, update after the grant");
assert.ok(/if \(!core\.authorized\(s\.category\) \|\| !core\.authorizedService\(s\.id\)\) return;/.test(source), "the destination loader re-checks authorisation");
assert.ok(/if \(!core\.authorizedService\(s\.id\)\) return;/.test(source), "a conversion re-checks authorisation before it is queued");
assert.ok(/cookie_domain: location\.hostname/.test(source), "destination cookies stay on the consenting host");
assert.ok(/if \(d\.prompt && !env\.bot\(\)\) renderBar\(\);/.test(source), "hiding the bar from bots never touches the loader");
assert.ok(/if \(result\.ok\) location\.reload\(\);/.test(source), "reload only after a persisted refusal");
assert.ok(/node\.removeAttribute\("src"\);\s*node\.removeAttribute\("srcdoc"\);/.test(source), "embed teardown removes src and srcdoc");
assert.ok(!/innerHTML/.test(source), "no innerHTML sink in the renderer");
assert.ok(!/uuid|crypto\.randomUUID/.test(source), "no generated identifiers anywhere");
assert.ok(/value: c\.value === undefined \? 1\.0 : c\.value/.test(source), "a conversion value of zero is preserved");

console.log("consent-gate core: ok");
