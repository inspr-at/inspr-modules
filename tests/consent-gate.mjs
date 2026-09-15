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
const exampleHtml = readFileSync(join(pkg, "example", "example.html"), "utf8");
const embedded = JSON.parse(/<script type="application\/json" id="consent-manifest">\s*([\s\S]*?)\s*<\/script>/.exec(exampleHtml)[1]);
assert.deepEqual(embedded, example, "example.html embeds the example manifest verbatim");
const now = 1_800_000_000;
const B = core.binding(example);
const entry = (id, at = now - 10, rev = 1, tv = 1) => ({ id, at, rev, tv });
const rec = (granted, extra = {}) => ({ binding: B, revision: 1, textVersion: 1, granted: granted.map((g) => (typeof g === "string" ? entry(g) : g)), services: [], at: now - 10, ...extra });
const DAY = 86400;

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
  [{ ...example, categories: [{ id: "necessary", required: true, revision: 0 }, ...example.categories.slice(1)] }, /category necessary revision/],
  [{ ...example, services: [{ ...example.services[0], category: "necessary" }] }, /required category/],
  [{ ...example, services: [{ ...example.services[0], destination: { ...example.services[0].destination, consent: ["ad_storage", "bogus"] } }] }, /Consent Mode keys/],
  [{ ...example, services: [{ ...example.services[0], destination: { ...example.services[0].destination, tagId: "" } }] }, /tagId invalid/],
  [{ ...example, services: [{ ...example.services[1], destination: { ...example.services[1].destination, conversion: { sendTo: "AW-999999999/undeclared" } } }] }, /conversion\.sendTo must be <tagId>/],
  [{ ...example, services: [{ ...example.services[1], destination: { ...example.services[1].destination, conversion: "x" } }] }, /conversion must be an object/],
  [{ ...example, services: [{ ...example.services[1], destination: { ...example.services[1].destination, conversion: null } }] }, /conversion must be an object/],
  [{ ...example, services: [{ ...example.services[0], purposes: [] }] }, /purposes/],
  [{ ...example, services: [{ ...example.services[0], embed: { host: "x.example" } }] }, /exactly one of destination or embed/],
  [{ ...example, services: [{ ...example.services[2], embed: { host: "not a host" } }] }, /embed\.host/],
  [{ ...example, services: [{ ...example.services[1], storage: [{ kind: "cookie", name: "_gcl_*", domain: "other.invalid" }] }] }, /domain must be the scope host/],
  [{ ...example, services: [{ ...example.services[1], storage: [{ kind: "local", name: "x", path: "/" }] }] }, /apply to cookies only/],
  [{ ...example, services: [{ ...example.services[2], storage: [{ kind: "cookie", name: "video_*", path: "/app" }] }] }, /wildcard names must use path/],
  [{ ...example, privacyUrl: "javascript:alert(1)" }, /privacyUrl/],
  [{ ...example, privacyUrl: "http://plain.example/" }, /privacyUrl/],
  [{ ...example, privacyUrl: "/\\evil.example/path" }, /privacyUrl/],
  [{ ...example, refusalMonths: 3 }, /refusalMonths must be at least 6/],
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
for (const bad of ["javascript:alert(1)", "http://plain.example/", "//evil.example/", "/\\evil.example/path", "/path with space", "https://evil.example\\@x/"]) assert.equal(core.safeUrl(bad), null, `unsafe: ${bad}`);
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
assert.match(B, /^[0-9a-f]{8}$/, "binding is a manifest fingerprint");
assert.equal(core.binding({ ...example, controller: "Other" }) === B, false, "binding changes with the controller");
assert.equal(core.binding({ ...example, scope: "other.example.invalid" }) === B, false, "binding changes with the scope");
const value = core.serialize({ binding: B, revision: 3, textVersion: 2, granted: [entry("marketing", now - 5, 2), entry("measurement", now - 9, 1)], services: [entry("video", now - 1, 1)], at: now });
assert.equal(value, `v1;b=${B};r=3;v=2;g=marketing@${now - 5}.2.1,measurement@${now - 9}.1.1;s=video@${now - 1}.1.1;t=${now}`);
assert.deepEqual(plain(core.parse(value)), { binding: B, revision: 3, textVersion: 2, granted: [entry("marketing", now - 5, 2), entry("measurement", now - 9, 1)], services: [entry("video", now - 1, 1)], at: now });
assert.deepEqual(plain(core.parse(`v1;b=${B};r=1;v=1;g=;s=;t=5`)), { binding: B, revision: 1, textVersion: 1, granted: [], services: [], at: 5 });
for (const bad of ["garbage", "", `v1;b=${B};r=1garbage;v=1;g=;s=;t=1800000000garbage`, `v1;b=${B};r=1;v=1;g=;s=;t=1800000000;t=1`, `v1;b=${B};r=1;v=1;g=Bad Token;s=;t=1`, `v1;b=${B};r=1;v=1;g=marketing;s=;t=1`, `v1;b=${B};r=1;v=1;g=marketing@1.1;s=;t=1`, `v1;r=1;v=1;g=;s=;t=1`, `v1;b=nothex!;r=1;v=1;g=;s=;t=1`, `v2;b=${B};r=1;v=1;g=;s=;t=1`, `v1;b=${B};r=99999999999999;v=1;g=;s=;t=1`]) {
  assert.equal(core.parse(bad), null, `strict parse rejects ${JSON.stringify(bad)}`);
}
assert.ok(!/uuid|random/i.test(value), "no generated identifier in the stored value");

// ---- refusal retention: six UTC calendar months -----------------------------
{
  const march1 = Date.UTC(2026, 2, 1, 12, 0, 0) / 1000;
  assert.equal(core.refusalExpiry(example, march1), Date.UTC(2026, 8, 1, 12, 0, 0) / 1000, "1 March → 1 September");
  const aug31 = Date.UTC(2026, 7, 31, 0, 0, 0) / 1000;
  assert.equal(core.refusalExpiry(example, aug31), Date.UTC(2027, 1, 28, 0, 0, 0) / 1000, "31 August → 28 February (clamped)");
  const m = plain(example); m.refusalMonths = 12;
  assert.equal(core.refusalExpiry(m, march1), Date.UTC(2027, 2, 1, 12, 0, 0) / 1000, "refusalMonths extends the minimum");
}

// ---- decide ---------------------------------------------------------------
const d = (extra) => plain(core.decide({ manifest: example, now, signal: false, bot: false, stored: null, ...extra }));
const noneGranted = { measurement: false, marketing: false, embeds: false };
assert.deepEqual(d({}), { tier: "bar", prompt: true, granted: noneGranted, services: [], entries: { granted: [], services: [] }, persist: "none" }, "fresh visitor: prompt, nothing granted");
assert.deepEqual(d({ stored: rec(["measurement"]) }).granted, { measurement: true, marketing: false, embeds: false }, "partial grant honoured");
assert.deepEqual(d({ stored: rec(["measurement", "marketing"]) }).granted, { measurement: true, marketing: true, embeds: false });
assert.deepEqual(d({ stored: rec([], { services: [entry("video")] }) }).services, ["video"], "a remembered service is honoured without its category");
assert.deepEqual(d({ stored: rec(["embeds"], { services: [entry("video")] }) }).services, [], "a remembered service folds into its granted category");
assert.equal(d({ stored: rec([]) }).prompt, false, "stored refusal: no prompt");
assert.deepEqual(d({ stored: rec(["marketing"]), signal: true }).persist, "refuse", "GPC/DNT overrides an older grant and persists a refusal");
assert.equal(d({ stored: rec(["marketing"]), signal: true }).granted.marketing, false);
assert.equal(d({ bot: true }).prompt, false);
assert.equal(d({ bot: true }).granted.marketing, false);
assert.equal(d({ blocked: true }).prompt, false, "a blocked accessor closes the gate silently");
assert.equal(d({ stored: rec(["marketing"], { binding: "deadbeef" }) }).granted.marketing, false, "a record bound to another controller/scope is no decision");
assert.equal(d({ stored: rec(["marketing"], { binding: "deadbeef" }) }).prompt, true);
assert.equal(d({ stored: rec([entry("marketing", now - 181 * DAY)]) }).prompt, true, "expired permission re-asks");
assert.equal(d({ stored: rec([], { at: now - 181 * DAY }) }).prompt, false, "a refusal outlives the permission lifetime");
{
  const march1 = Date.UTC(2026, 2, 1, 12, 0, 0) / 1000;
  const aug31 = Date.UTC(2026, 7, 31, 12, 0, 0) / 1000;
  const sep1 = Date.UTC(2026, 8, 1, 12, 0, 1) / 1000;
  assert.equal(plain(core.decide({ manifest: example, now: aug31, signal: false, bot: false, stored: rec([], { at: march1 }) })).prompt, false, "a 1 March refusal is still respected on 31 August");
  assert.equal(plain(core.decide({ manifest: example, now: sep1, signal: false, bot: false, stored: rec([], { at: march1 }) })).prompt, true, "…and may be asked again after six calendar months");
}
assert.equal(d({ stored: rec(["marketing"], { revision: 0 }) }).prompt, true, "a global purpose revision re-asks everything");
{
  // per-category revision: bumping ads leaves measurement intact
  const m = plain(example); m.categories.find((c) => c.id === "marketing").revision = 2;
  const out = plain(core.decide({ manifest: m, now, signal: false, bot: false, stored: { ...rec(["measurement", "marketing"]), binding: core.binding(m) } }));
  assert.deepEqual(out.granted, { measurement: true, marketing: false, embeds: false }, "a category revision invalidates only that category");
  assert.equal(out.prompt, false);
}
{
  // per-entry expiry: an unrelated later grant does not extend an older one
  const stored = rec([entry("measurement", now - 179 * DAY)], { services: [entry("video", now - DAY)], at: now - DAY });
  const later = now + 2 * DAY;
  const out = plain(core.decide({ manifest: example, now: later, signal: false, bot: false, stored }));
  assert.equal(out.granted.measurement, false, "measurement expires on its own day 180");
  assert.deepEqual(out.services, ["video"], "…while the newer service permission lives on");
}
assert.equal(d({ stored: rec([entry("marketing", now + 60)]) }).granted.marketing, false, "a future-dated entry authorises nothing");
assert.equal(d({ stored: rec(["marketing"], { at: now + 60 }) }).prompt, true, "a future-dated record is no decision");
assert.equal(d({ stored: rec(["marketing"]), now: NaN }).granted.marketing, false, "a broken clock authorises nothing");
assert.equal(d({ stored: rec(["marketing"]), revoked: true }).granted.marketing, false, "a revocation outranks a surviving grant");
{
  const m = plain(example); m.permissionDays = 7;
  assert.equal(core.decide({ manifest: m, now, signal: false, bot: false, stored: { ...rec([entry("marketing", now - 8 * DAY)]), binding: core.binding(m) } }).prompt, true, "short permission lifetime expires");
  assert.equal(core.decide({ manifest: m, now, signal: false, bot: false, stored: { ...rec([], { at: now - 100 * DAY }), binding: core.binding(m) } }).prompt, false, "…while the refusal keeps its six months");
}
{
  const m = plain(example); m.services = m.services.filter((s) => s.embed);
  assert.equal(core.decide({ manifest: m, now, signal: false, bot: false, stored: null }).prompt, false, "contextual tier never prompts with a bar");
}

{
  // Per-entry consent-text provenance survives unrelated later grants; fractional clocks persist integer seconds
  const env = fakeEnv();
  env.state.now = now + 0.125;
  const c = core.createCore(example, env);
  assert.equal(c.grant(["measurement"]).ok, true);
  const first = core.parse(env.state.cookies.consent);
  assert.equal(first.at, now, "the record time is integer seconds");
  assert.equal(first.granted[0].at, now, "the entry time is integer seconds");
  assert.equal(first.granted[0].tv, 1);
  const m2 = plain(example); m2.textVersion = 2;
  const c2 = core.createCore(m2, env);
  assert.equal(c2.grantService("video").ok, true);
  const second = core.parse(env.state.cookies.consent);
  assert.equal(second.textVersion, 2, "the record carries the current text version");
  assert.equal(second.granted.find((e) => e.id === "measurement").tv, 1, "the older grant keeps the text version it was given under");
  assert.equal(second.services.find((e) => e.id === "video").tv, 2, "the new grant is stamped with the current one");
  // refusal cookie lifetime is a whole number of seconds
  const env3 = fakeEnv();
  env3.state.now = Date.UTC(2026, 2, 1, 12, 0, 0) / 1000 + 0.125;
  const ages = [];
  const write = env3.writeCookie;
  env3.writeCookie = (n, v, maxAge) => { ages.push(maxAge); return write(n, v); };
  const c3 = core.createCore(example, env3);
  assert.equal(c3.refuse().persisted, true);
  assert.ok(ages.every((a) => Number.isInteger(a)), `Max-Age is integral: ${ages}`);
  assert.equal(ages.at(-1), Date.UTC(2026, 8, 1, 12, 0, 0) / 1000 - Date.UTC(2026, 2, 1, 12, 0, 0) / 1000, "…and spans six calendar months");
}

{
  // A refusal that could not be stored is retried on every policy check until it reads back (B7)
  const opts = { writeDrops: true, sessionWriteThrows: true };
  const env = fakeEnv(opts);
  env.state.cookies.consent = core.serialize(rec(["marketing"]));
  const c = core.createCore(example, env);
  assert.equal(c.boot().granted.marketing, true);
  env.state.signal = true;
  assert.equal(c.authorized("marketing"), false, "the observed signal revokes in-page");
  assert.ok(env.state.cookies.consent.includes("marketing@"), "…but the refusal could not be stored yet");
  opts.writeDrops = false; opts.sessionWriteThrows = false;
  c.current();
  assert.ok(env.state.cookies.consent.includes(";g=;s=;"), "the pending refusal is stored once the writer recovers");
  env.state.signal = false;
  assert.equal(c.authorized("marketing"), false);
  assert.equal(core.createCore(example, env).boot().granted.marketing, false, "the next document sees the stored refusal");
  // and the same when the writer only recovers after the signal disappeared
  const opts2 = { writeDrops: true, sessionWriteThrows: true };
  const env2 = fakeEnv(opts2);
  env2.state.cookies.consent = core.serialize(rec(["marketing"]));
  const c2 = core.createCore(example, env2);
  c2.boot();
  env2.state.signal = true; c2.current(); env2.state.signal = false;
  opts2.writeDrops = false; opts2.sessionWriteThrows = false;
  c2.current();
  assert.ok(env2.state.cookies.consent.includes(";g=;s=;"), "a pending refusal is stored even after the signal disappeared");
  assert.equal(core.createCore(example, env2).boot().granted.marketing, false);
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
  const inert = exampleHtml;
  const g1 = core.guardServedHtml({ manifest: example, html: inert, requests: ["https://self.example/assets/consent-gate.js", "https://self.example/"] });
  assert.deepEqual(plain(g1.violations), [], "inert manifest, data-src and the gate script pass");
  assert.equal(g1.ok, true);
  const active = inert.replace('data-src="https://video.example.invalid/embed/1"', 'src="https://video.example.invalid/embed/1"');
  const g2 = core.guardServedHtml({ manifest: example, html: active, requests: [] });
  assert.deepEqual(plain(g2.violations), [{ kind: "markup", element: "iframe", attribute: "src", url: "https://video.example.invalid/embed/1" }], "a live embed src fails");
  assert.equal(core.guardServedHtml({ manifest: example, html: inert + '<script async src="https://www.googletagmanager.com/gtag/js?id=AW-000000000"></script>', requests: [] }).violations[0].element, "script", "a tag loader in served HTML fails");
  assert.deepEqual(plain(core.guardServedHtml({ manifest: example, html: inert, requests: ["https://googleads.g.doubleclick.net/pagead/viewthroughconversion/1"] }).violations), [{ kind: "request", url: "https://googleads.g.doubleclick.net/pagead/viewthroughconversion/1" }], "a pre-consent request to a declared host fails");
  assert.equal(core.guardServedHtml({ manifest: example, html: '<img src="https://sub.video.example.invalid/t.png">', requests: [] }).ok, false, "subdomains of a declared host count");
  assert.equal(core.guardServedHtml({ manifest: example, html: '<iframe src="//video.example.invalid/embed/1"></iframe>', requests: [] }).ok, false, "protocol-relative URLs count");
  assert.equal(core.guardServedHtml({ manifest: example, html: '<img srcset="/local.png 1x, https://video.example.invalid/a.png 2x">', requests: [] }).violations[0].attribute, "srcset", "every srcset candidate counts");
  assert.equal(core.guardServedHtml({ manifest: example, html: '<iframe src="https:&#47;&#47;video.example.invalid/embed/1"></iframe>', requests: [] }).ok, false, "entity-encoded URLs count");
  assert.equal(core.guardServedHtml({ manifest: example, html: "<iframe src='https:&#x2F;&#x2F;video.example.invalid/e'></iframe>", requests: [] }).ok, false, "hex entities and single quotes count");
  assert.deepEqual(plain(core.guardServedHtml({ manifest: example, html: '<iframe data-consent-embed="video" srcdoc="<p>hi</p>"></iframe>', requests: [] }).violations), [{ kind: "markup", element: "iframe", attribute: "srcdoc", url: "" }], "srcdoc on a gated embed fails");
  assert.equal(core.guardServedHtml({ manifest: example, html: '<!-- <img src="https://video.example.invalid/t.png"> --><p>ok</p>', requests: [] }).ok, true, "commented-out markup is inert");
  assert.equal(core.guardServedHtml({ manifest: example, html: '<iframe title="a > b" src="//video.example.invalid/embed/1"></iframe>', requests: [] }).ok, false, "a > inside a quoted attribute does not end the tag");
  assert.equal(core.guardServedHtml({ manifest: example, html: '<iframe srcdoc="<p>hi</p>" data-consent-embed="video"></iframe>', requests: [] }).violations[0].attribute, "srcdoc", "srcdoc is found regardless of attribute order");
  assert.equal(core.guardServedHtml({ manifest: example, html: '<script type="application/json" id="x">{"s":"<img src=\\"https://video.example.invalid/t.png\\">"}</script>', requests: [] }).ok, true, "provider markup inside a JSON script string is inert");
  assert.equal(core.guardServedHtml({ manifest: example, html: '<style>.x{background:url(https://video.example.invalid/a.png)}</style><img src=https://video.example.invalid/u.png>', requests: [] }).violations.length, 1, "raw-text contents are skipped; an unquoted src still counts");
  assert.equal(core.guardServedHtml({ manifest: example, html: '<a href="https://video.example.invalid/">watch</a><link rel="stylesheet" href="/style.css">', requests: [] }).ok, true, "plain anchors and same-origin links are inert");
}

// ---- createCore with a fake environment -----------------------------------
function fakeEnv(opts = {}) {
  const state = { cookies: {}, session: {}, local: { _gcl_ls: "seeded" }, signal: false, bot: false, now, host: example.scope, cleared: [] };
  return {
    state,
    now: () => { if (opts.clockThrows) throw new Error("clock"); return state.now; },
    host: () => { if (opts.hostThrows) throw new Error("host"); return state.host; },
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
  const firstAt = core.parse(env.state.cookies.consent).granted[0].at;
  env.state.now += 5 * DAY;
  assert.equal(c.grant(["measurement", "marketing"]).ok, true);
  const after = core.parse(env.state.cookies.consent);
  assert.equal(after.granted.find((e) => e.id === "measurement").at, firstAt, "an unchanged grant keeps its original time");
  assert.equal(after.granted.find((e) => e.id === "marketing").at, env.state.now, "a new grant is stamped now");
  env.state.cookies._gcl_au = "x"; env.state.cookies._ga = "y"; env.state.session.consent_fired_ads = "1";
  assert.equal(c.grant(["marketing"]).ok, true, "dropping measurement");
  assert.ok(!("_ga" in env.state.cookies), "dropping measurement clears its declared cookies");
  assert.ok("_gcl_au" in env.state.cookies, "marketing storage untouched while marketing stays granted");
  assert.deepEqual(plain(env.state.cleared.at(-1)), { name: "_ga*", path: "/", domain: null, exact: false }, "cleanup passes the declared descriptor, host-only, at the declared path");
  let seen = null; c.onChange((dd) => { seen = dd; });
  assert.equal(c.withdraw().persisted, true);
  assert.ok(seen && seen.granted.marketing === false, "listeners see the withdrawal");
  assert.ok(!("_gcl_au" in env.state.cookies) && !("_gcl_ls" in env.state.local) && !("consent_fired_ads" in env.state.session), "withdrawal clears cookies, local storage and the adapter's conversion marker");
  assert.equal(c.current().prompt, false, "a stored refusal does not re-prompt");
}

{
  // Exact names are cleared unconditionally at their declared path; wildcards by visible match
  const m = plain(example); m.services[2].storage = [{ kind: "cookie", name: "video_pref", path: "/app" }];
  const env = fakeEnv();
  const c = core.createCore(m, env);
  assert.equal(c.grantService("video").ok, true);
  assert.equal(c.withdraw().persisted, true);
  assert.ok(env.state.cleared.some((st) => st.name === "video_pref" && st.path === "/app" && st.exact === true), "an exact cookie name is deleted at its declared path without enumeration");
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
  // A signal observed mid-page is latched; an empty grant under a signal still persists the refusal
  const env = fakeEnv();
  env.state.cookies.consent = core.serialize(rec(["marketing"]));
  const c = core.createCore(example, env);
  assert.equal(c.boot().granted.marketing, true);
  env.state.signal = true;
  assert.equal(c.grant([]).ok, true, "an empty grant is a refusal even while a signal refuses new grants");
  assert.ok(env.state.cookies.consent.includes(";g=;s=;"));
  env.state.signal = false;
  assert.equal(c.authorized("marketing"), false, "the old grant does not revive after the signal disappears");
  const env2 = fakeEnv();
  env2.state.cookies.consent = core.serialize(rec(["marketing"]));
  const c2 = core.createCore(example, env2);
  c2.boot();
  env2.state.signal = true;
  assert.equal(c2.authorized("marketing"), false);
  assert.ok(env2.state.cookies.consent.includes(";g=;s=;"), "an observed signal persists a refusal at once, without an explicit refusal call");
  env2.state.signal = false;
  assert.equal(c2.authorized("marketing"), false, "merely observing a signal latches the in-page revocation");
  const c2next = core.createCore(example, env2);
  assert.equal(c2next.boot().granted.marketing, false, "…and the next document sees the stored refusal");
}

{
  // Storage failure: dropped cookie writes → grant fails closed; refusal falls back to the session flag
  const env = fakeEnv({ writeDrops: true });
  const c = core.createCore(example, env);
  const r = c.grant(["marketing"]);
  assert.equal(r.ok, false, "a grant that cannot be read back is no grant");
  assert.equal(r.persisted, true, "…and its refusal is recorded in the session");
  assert.equal(c.authorized("marketing"), false);
  assert.equal(env.state.session[c.revokeKey], "1");
}
{
  // Withdrawal whose refusal cannot be stored anywhere reports failure (the renderer then carries a URL marker)
  const env = fakeEnv({ writeDrops: true, sessionWriteThrows: true });
  env.state.cookies.consent = core.serialize(rec(["marketing"]));
  const c = core.createCore(example, env);
  assert.equal(c.boot().granted.marketing, true);
  const r = c.grant([]);
  assert.equal(r.ok, false); assert.equal(r.persisted, false, "grant([]) reports the persistence failure");
  assert.equal(c.withdraw().persisted, false);
  assert.equal(c.authorized("marketing"), false, "…but the in-page revocation holds");
}
{
  // Failed "always allow" refuses everything and reports it
  const env = fakeEnv();
  const c = core.createCore(example, env);
  assert.equal(c.grant(["marketing"]).ok, true);
  const inst = {};
  assert.equal(c.loadOnce("video", inst), true);
  env.state.cookies = new Proxy(env.state.cookies, { set: (t, k, v) => { if (k === "consent" && v.includes("s=video")) return true; t[k] = v; return true; } });
  const r = c.grantService("video");
  assert.equal(r.ok, false, "a service grant that cannot be read back fails");
  assert.equal(c.authorized("marketing"), false, "…and the failed grant refuses everything");
  assert.equal(c.authorizedInstance("video", inst), false, "…including one-time instances");
}
{
  // Throwing accessors: nothing loads, nothing throws out of the core
  for (const opts of [{ readThrows: true, writeThrows: true }, { sessionReadThrows: true }, { signalThrows: true }, { clockThrows: true }, { hostThrows: true }]) {
    const env = fakeEnv(opts);
    env.state.cookies.consent = core.serialize(rec(["marketing"]));
    const c = core.createCore(example, env);
    assert.doesNotThrow(() => c.boot(), JSON.stringify(opts));
    assert.equal(c.authorized("marketing"), false, `no authorisation under ${JSON.stringify(opts)}`);
    assert.equal(c.grant(["marketing"]).ok, false);
    // a one-time embed needs no storage: only broken clock, session, signal or host readers block it
    if (!opts.readThrows) assert.equal(c.loadOnce("video", {}), false, `no load-once under ${JSON.stringify(opts)}`);
    assert.doesNotThrow(() => c.withdraw());
  }
  // a failing clock after a load-once revokes the instance too
  const env = fakeEnv();
  const c = core.createCore(example, env);
  const inst = {};
  assert.equal(c.loadOnce("video", inst), true);
  env.now = () => { throw new Error("clock"); };
  assert.equal(c.authorizedInstance("video", inst), false);
}
{
  // Wrong host: the manifest scope must match the surface
  const env = fakeEnv();
  env.state.host = "other.example.invalid";
  env.state.cookies.consent = core.serialize(rec(["marketing"]));
  const c = core.createCore(example, env);
  assert.equal(c.boot().granted.marketing, false, "a record on the wrong host authorises nothing");
  assert.equal(c.grant(["marketing"]).ok, false);
  assert.equal(c.authorized("necessary"), false, "even the required category is closed on the wrong host");
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
  // Embeds: instance-bound load once, service-scoped remembered permission, scoped revocation
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
  assert.equal(c.authorizedInstance("video", a), true, "…and leaves the one-time instance alone");
  assert.equal(c.grant(["measurement", "embeds"]).ok, true);
  assert.equal(c.grant(["measurement"]).ok, true, "dropping the embeds category");
  assert.equal(c.authorizedInstance("video", a), false, "…kills the one-time permission of its services");
  const c2 = core.createCore(example, env);
  assert.equal(c2.authorizedInstance("video", a), false, "load once does not carry into the next page view");
  assert.equal(c2.grantService("video").ok, true, "always allow remembers the named service");
  assert.equal(c2.authorizedService("video"), true);
  assert.equal(c2.authorized("embeds"), false, "…without granting its whole category");
  assert.deepEqual(plain(c2.current().services), ["video"]);
  assert.equal(c2.grant(["measurement"]).ok, true, "a category-only grant keeps the remembered service by default");
  assert.equal(c2.authorizedService("video"), true);
  assert.equal(c2.grant(["measurement"], []).ok, true, "an explicit empty service list revokes it");
  assert.equal(c2.authorizedService("video"), false);
  assert.equal(c2.grant([], []).ok, true);
  assert.equal(c2.current().prompt, false, "saving everything off persists a refusal");
  const m2 = plain(example); m2.services.push({ id: "map", category: "embeds", provider: "Example Maps", purposes: ["map"], embed: { host: "maps.example.invalid" } }); m2.text.en.services.map = { label: "Map" };
  const env3 = fakeEnv();
  const c3 = core.createCore(m2, env3);
  assert.equal(c3.grantService("video").ok, true);
  assert.equal(c3.authorizedService("video"), true);
  assert.equal(c3.authorizedService("map"), false, "another provider in the same category stays closed");
  assert.equal(c3.grant(["measurement", "embeds"]).ok, true);
  assert.equal(c3.authorizedService("map"), true, "granting the category opens every service in it");
  assert.equal(c3.grant(["measurement"]).ok, true, "dropping the category drops its remembered services too");
  assert.equal(c3.authorizedService("video"), false);
  env3.state.signal = true;
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
    assert.equal(c.grantService("video").ok, false);
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
assert.ok(/if \(result\.persisted === false\) \{[\s\S]*REVOKE_HASH[\s\S]*location\.reload\(\);/.test(source), "an unpersisted refusal reloads with a URL revocation marker");
assert.ok(/if \(location\.hash\.indexOf\(REVOKE_HASH\) >= 0\) \{\s*var r = core\.refuse\(\);/.test(source), "the marker closes the gate on the next document before any grant is read");
assert.ok(/settle\(core\.grantService\(s\.id\), false\)/.test(source), "always allow settles like every other grant");
assert.ok(/node\.removeAttribute\("src"\);\s*node\.removeAttribute\("srcdoc"\);/.test(source), "embed teardown removes src and srcdoc");
assert.ok(/node\.hasAttribute\("srcdoc"\)/.test(source), "a served srcdoc is treated as live content");
assert.ok(/ic-svc-/.test(source), "remembered services have their own settings rows");
assert.ok(/sbox\.addEventListener\("change", function \(\) \{ if \(!sbox\.checked\) box\.checked = false; \}\);/.test(source), "unselecting a service unselects its category");
assert.ok(/every\(function \(s\) \{ return svcBoxes\[s\.id\]\.checked; \}\)/.test(source), "a category is persisted only when all its service rows are selected");
assert.ok(/if \(r\.persisted\) \{ try \{ history\.replaceState/.test(source), "the revocation marker is removed only after the refusal persisted");
assert.ok(/var lost = dropping \|\| result\.ok === false \|\| lostAuthorization\(\);/.test(source), "settlement checks loaded destinations against the current decision");
assert.ok(/if \(lostAuthorization\(\)\) \{ settle/.test(source), "rendering never loads more while a loaded destination lost authorisation");
assert.ok(/once\.addEventListener\("click", function \(\) \{ if \(reconcile\(\)\) return;/.test(source), "load once reconciles before activating");
assert.ok(/always\.addEventListener\("click", function \(\) \{ if \(reconcile\(\)\) return;/.test(source), "always allow reconciles before granting");
assert.ok(/if \(!core\.valid \|\| reconcile\(\)\) return;/.test(source), "opening the settings reconciles first");
assert.ok(/teardownEmbeds\(\);\s*location\.reload\(\);/.test(source), "the reload branch only tears embeds down, never activates");
assert.ok(/if \(settling\) return;/.test(source), "settlement is reentrancy-safe");
assert.ok(!/innerHTML/.test(source), "no innerHTML sink in the renderer");
assert.ok(!/uuid|crypto\.randomUUID/.test(source), "no generated identifiers anywhere");
assert.ok(/value: c\.value === undefined \? 1\.0 : c\.value/.test(source), "a conversion value of zero is preserved");

console.log("consent-gate core: ok");
