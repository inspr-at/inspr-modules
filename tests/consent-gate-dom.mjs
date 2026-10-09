#!/usr/bin/env node
// consent-gate renderer journeys under a minimal in-memory DOM (INSPR-431).
//
// This is not a browser: it models exactly the DOM surface the gate uses
// (elements, attributes, a cookie jar with path visibility, storages,
// location/history, dialog, click events) so that the renderer's decisions
// — what loads, what is torn down, when the page reloads and with which
// marker — are executable regressions. The consuming surface still owns the
// real-browser proof.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import vm from "node:vm";
import assert from "node:assert/strict";

const here = dirname(fileURLToPath(import.meta.url));
const pkg = join(here, "..", "packages", "consent-gate");
const source = readFileSync(join(pkg, "consent-gate.js"), "utf8");
const example = JSON.parse(readFileSync(join(pkg, "example", "manifest.json"), "utf8"));
const plain = (v) => JSON.parse(JSON.stringify(v));
const DAY = 86400;

// ---- minimal DOM ------------------------------------------------------------
function matches(node, sel) {
  const m = /^([a-z]+)?(#[\w-]+)?((?:\.[\w-]+)*)((?:\[[^\]]+\])*)$/.exec(sel.trim());
  if (!m) throw new Error("unsupported selector " + sel);
  if (m[1] && node.tagName !== m[1]) return false;
  if (m[2] && node.getAttribute("id") !== m[2].slice(1)) return false;
  for (const c of (m[3] || "").split(".").filter(Boolean)) if (!node.classList.contains(c)) return false;
  for (const a of (m[4] || "").match(/\[[^\]]+\]/g) || []) {
    const am = /^\[([\w-]+)(?:="([^"]*)")?\]$/.exec(a);
    if (!node.hasAttribute(am[1])) return false;
    if (am[2] !== undefined && node.getAttribute(am[1]) !== am[2]) return false;
  }
  return true;
}
class Node {
  constructor(tag) {
    this.tagName = tag; this.attrs = {}; this.children = []; this.parentNode = null; this.listeners = {};
    this.hidden = false; this.textContent = ""; this.open = false; this.checked = false; this.disabled = false; this.contentWindow = null;
    const self = this;
    this.classList = { contains: (c) => (self.attrs.class || "").split(/\s+/).includes(c) };
    this.dataset = new Proxy({}, { get: (_, k) => self.attrs["data-" + String(k).replace(/[A-Z]/g, (x) => "-" + x.toLowerCase())] });
  }
  get src() { return this.attrs.src; } set src(v) { this.attrs.src = v; }
  get async() { return this.attrs.async; } set async(v) { this.attrs.async = v; }
  setAttribute(k, v) { this.attrs[k] = String(v); if (k === "checked") this.checked = true; if (k === "disabled") this.disabled = true; }
  getAttribute(k) { return k in this.attrs ? this.attrs[k] : null; }
  removeAttribute(k) { delete this.attrs[k]; }
  hasAttribute(k) { return k in this.attrs; }
  appendChild(c) { if (c.parentNode) c.parentNode.removeChild(c); c.parentNode = this; this.children.push(c); return c; }
  insertBefore(n, ref) { if (n.parentNode) n.parentNode.removeChild(n); n.parentNode = this; const i = this.children.indexOf(ref); this.children.splice(i < 0 ? this.children.length : i, 0, n); return n; }
  removeChild(c) { const i = this.children.indexOf(c); if (i >= 0) this.children.splice(i, 1); c.parentNode = null; return c; }
  get previousElementSibling() { if (!this.parentNode) return null; const i = this.parentNode.children.indexOf(this); return i > 0 ? this.parentNode.children[i - 1] : null; }
  addEventListener(t, fn) { (this.listeners[t] = this.listeners[t] || []).push(fn); }
  removeEventListener(t, fn) { this.listeners[t] = (this.listeners[t] || []).filter((f) => f !== fn); }
  dispatch(t, ev = {}) { for (const fn of (this.listeners[t] || []).slice()) fn(ev); }
  click() { this.dispatch("click"); }
  showModal() { this.open = true; this.attrs.open = ""; }
  close() { this.open = false; delete this.attrs.open; }
  all() { return this.children.flatMap((c) => [c, ...c.all()]); }
  querySelectorAll(sel) { return this.all().filter((n) => matches(n, sel)); }
  querySelector(sel) { return this.querySelectorAll(sel)[0] || null; }
}

// boot loads the gate into a fresh page. opts: cookies (jar), session, local,
// signal, ua, path, hash, fire, now, writers ("ok" | "drop" | "throw").
function boot(manifest, opts = {}) {
  const state = { reloads: 0, warnings: [], now: opts.now ?? 1_800_000_000 };
  const jar = opts.jar || { list: [] }; // { name, value, path, domain }
  const location = { hostname: opts.host || manifest.scope, protocol: "https:", pathname: opts.path || "/", search: "", hash: opts.hash || "", reload() { state.reloads++; } };
  const history = { replaceState(_s, _t, url) { const u = new URL(url, "https://x/"); location.pathname = u.pathname; location.search = u.search; location.hash = u.hash; } };
  const writers = { mode: opts.writers || "ok" };
  const storage = (init) => { const map = new Map(Object.entries(init || {})); return { getItem: (k) => { if (writers.mode === "throw") throw new Error("storage"); return map.has(k) ? map.get(k) : null; }, setItem: (k, v) => { if (writers.mode !== "ok") throw new Error("storage"); map.set(k, String(v)); }, removeItem: (k) => { map.delete(k); }, map }; };
  const sessionStorage = storage(opts.session);
  const localStorage = storage(opts.local);
  const document = new Node("#document");
  document.head = document.appendChild(new Node("head"));
  document.body = document.appendChild(new Node("body"));
  document.documentElement = { lang: "en" };
  document.readyState = "complete";
  document.createElement = (t) => new Node(t);
  document.createTextNode = (t) => { const n = new Node("#text"); n.textContent = t; return n; };
  document.querySelector = (s) => document.body.querySelector(s) || document.head.querySelector(s);
  document.querySelectorAll = (s) => [...document.head.querySelectorAll(s), ...document.body.querySelectorAll(s)];
  document.addEventListener = () => {}; document.removeEventListener = () => {};
  document.currentScript = { dataset: { consentManifest: "#consent-manifest", consentFire: opts.fire || "" } };
  Object.defineProperty(document, "cookie", {
    get() { if (writers.mode === "throw") throw new Error("jar"); return jar.list.filter((c) => location.pathname.startsWith(c.path)).map((c) => c.name + "=" + c.value).join("; "); },
    set(str) {
      if (writers.mode === "throw") throw new Error("jar");
      const parts = str.split(";").map((x) => x.trim());
      const [name, ...rest] = parts[0].split("="); const value = rest.join("=");
      const attrs = Object.fromEntries(parts.slice(1).map((a) => { const [k, v] = a.split("="); return [k.toLowerCase(), v === undefined ? "" : v]; }));
      const path = attrs.path || "/"; const domain = attrs.domain || null;
      if (attrs["max-age"] !== undefined && !/^\d+$/.test(attrs["max-age"])) throw new Error("fractional Max-Age emitted: " + attrs["max-age"]);
      const idx = jar.list.findIndex((c) => c.name === name && c.path === path && c.domain === domain);
      if (attrs["max-age"] === "0") { if (idx >= 0) jar.list.splice(idx, 1); return; }
      if (writers.mode === "drop" && name === manifest.cookieName) return;
      const rec = { name, value, path, domain };
      if (idx >= 0) jar.list[idx] = rec; else jar.list.push(rec);
    },
  });
  // page content: an embed per embed service, a footer control, the manifest
  for (const s of manifest.services) if (s.embed) for (let i = 0; i < (opts.embedsPerService || 1); i++) { const f = new Node("iframe"); f.setAttribute("data-consent-embed", s.id); f.setAttribute("data-src", "https://" + s.embed.host + "/embed/" + (i + 1)); document.body.appendChild(f); }
  const control = new Node("button"); control.setAttribute("data-consent-open", ""); document.body.appendChild(control);
  const navigator = { userAgent: opts.ua || "Mozilla/5.0 (Macintosh) Chrome/141.0", globalPrivacyControl: !!opts.signal, doNotTrack: null };
  class FakeDate extends Date { constructor(...a) { super(...(a.length ? a : [state.now * 1000])); } static now() { return state.now * 1000; } }
  const ctx = { document, location, history, navigator, sessionStorage, localStorage, console: { warn: (...a) => state.warnings.push(a.join(" ")) }, Date: FakeDate, insprConsentManifest: manifest, dataLayer: undefined };
  ctx.window = ctx; ctx.globalThis = ctx;
  vm.createContext(ctx);
  vm.runInContext(source, ctx, { filename: "consent-gate.js" });
  const api = {
    state, jar, location, sessionStorage, localStorage, writers, document, navigator, ctx,
    bar: () => document.body.querySelector(".ic-bar"),
    sheet: () => document.body.querySelector("dialog.ic-sheet"),
    control,
    embeds: () => document.body.querySelectorAll("[data-consent-embed]"),
    scripts: () => document.head.querySelectorAll("script").map((n) => n.attrs.src),
    layer: () => (ctx.dataLayer || []).map((a) => Array.from(a).map((x) => (typeof x === "object" && x !== null ? JSON.stringify(x) : String(x))).join(" ")),
    lastConsentUpdate: () => { const l = api.layer().filter((x) => x.startsWith("consent update")); return l.length ? JSON.parse(l.at(-1).slice("consent update ".length)) : null; },
    consentCookie: () => { const c = jar.list.find((c) => c.name === manifest.cookieName); return c ? decodeURIComponent(c.value) : undefined; },
    clickButton: (text, root) => { const b = (root || document.body).querySelectorAll("button").find((n) => n.textContent === text); assert.ok(b, "button " + text); b.click(); return b; },
    box: (id) => document.body.querySelector("#" + id),
  };
  return api;
}
const withGrant = (jar, manifest, granted, services = []) => {
  const core = (() => { const c = {}; vm.createContext(c); vm.runInContext(source, c); return c.insprConsentCore; })();
  const rec = { binding: core.binding(manifest), revision: 1, textVersion: 1, granted: granted.map((id) => ({ id, at: 1_800_000_000 - 10, rev: 1, tv: 1 })), services: services.map((id) => ({ id, at: 1_800_000_000 - 10, rev: 1, tv: 1 })), at: 1_800_000_000 - 10 };
  jar.list.push({ name: manifest.cookieName, value: encodeURIComponent(core.serialize(rec)), path: "/", domain: null });
  return jar;
};

// ---- journeys ---------------------------------------------------------------
{
  // fresh visit: bar with two identical buttons, nothing loads, accept loads exactly once
  const p = boot(example);
  assert.ok(p.bar(), "bar rendered");
  const btns = p.bar().querySelectorAll("button.ic-btn");
  assert.deepEqual(btns.map((b) => b.attrs.class), ["ic-btn", "ic-btn"], "reject and accept share one class");
  assert.deepEqual(p.scripts(), [], "nothing loads before a choice");
  assert.equal(p.embeds()[0].hidden, true, "the embed is hidden behind its placeholder");
  p.clickButton("Accept");
  assert.equal(p.bar(), null);
  assert.deepEqual(p.scripts().map((u) => u.split("?")[0]), ["https://www.googletagmanager.com/gtag/js", "https://www.googletagmanager.com/gtag/js"], "both destinations load once");
  assert.equal(p.layer()[0].startsWith("consent default"), true);
  assert.deepEqual(p.lastConsentUpdate().ad_storage, "granted");
  assert.equal(p.lastConsentUpdate().ad_personalization, "denied");
  assert.equal(p.embeds()[0].attrs.src, "https://video.example.invalid/embed/1", "accept-all activates embeds");
  assert.equal(p.state.reloads, 0);
}
{
  // reject: refusal stored, nothing loads, embed stays hidden
  const p = boot(example);
  p.clickButton("Reject");
  assert.ok(p.consentCookie().includes(";g=;s=;"));
  assert.deepEqual(p.scripts(), []);
  assert.equal(p.embeds()[0].hidden, true);
}
{
  // B1-a: loaded marketing expires, then "Load once" — the tag is denied and the page reloads before anything activates
  const jar = withGrant({ list: [] }, example, ["marketing"]);
  const p = boot(example, { jar });
  assert.equal(p.scripts().length, 1, "marketing loaded from the stored grant");
  p.state.now += 181 * DAY;
  p.clickButton("Load once");
  assert.equal(p.state.reloads, 1, "reload after the loaded destination lost authorisation");
  assert.equal(p.embeds()[0].attrs.src, undefined, "the embed was not activated before the reload");
  assert.equal(p.lastConsentUpdate().ad_storage, "denied", "the loaded tag was denied");
}
{
  // B1-b: marketing + embeds granted, signal appears, settings opened — deny, tear down, reload; with broken writers the marker survives
  for (const writers of ["ok", "drop"]) {
    const jar = withGrant({ list: [] }, example, ["marketing", "embeds"]);
    const p = boot(example, { jar });
    assert.equal(p.embeds()[0].attrs.src, "https://video.example.invalid/embed/1");
    p.navigator.globalPrivacyControl = true;
    p.writers.mode = writers;
    p.control.click();
    assert.equal(p.state.reloads, 1, `reload on an observed signal (${writers})`);
    assert.equal(p.embeds()[0].attrs.src, undefined, "the embed was torn down");
    assert.equal(p.lastConsentUpdate().ad_storage, "denied");
    if (writers === "ok") assert.ok(p.consentCookie().includes(";g=;s=;"), "refusal stored");
    else assert.equal(p.location.hash, "#consent-revoked", "the marker survives when the refusal could not be stored");
  }
}
{
  // B1-c: expired marketing + "Always allow" — the reload happens before the video activates
  const jar = withGrant({ list: [] }, example, ["marketing"]);
  const p = boot(example, { jar });
  p.state.now += 181 * DAY;
  p.clickButton("Always allow");
  assert.equal(p.state.reloads, 1);
  assert.equal(p.embeds()[0].attrs.src, undefined, "nothing activated before the reload");
}
{
  // embed-only surface: an observed signal tears the live embed down without any destination or reload
  const m = plain(example); m.services = m.services.filter((s) => s.embed);
  const jar = withGrant({ list: [] }, m, ["embeds"]);
  const p = boot(m, { jar });
  assert.equal(p.bar(), null, "contextual tier: no bar");
  assert.equal(p.embeds()[0].attrs.src, "https://video.example.invalid/embed/1", "granted embed is live");
  p.navigator.globalPrivacyControl = true;
  p.control.click();
  assert.equal(p.embeds()[0].attrs.src, undefined, "the embed was torn down on the observed signal");
  assert.equal(p.embeds()[0].hidden, true);
  assert.equal(p.state.reloads, 0, "no destination loaded, so no reload");
  assert.ok(p.consentCookie().includes(";g=;s=;"));
}
{
  // next document with the revocation marker: nothing loads, the marker stays until the refusal is stored
  const jar = withGrant({ list: [] }, example, ["marketing"]);
  const p = boot(example, { jar, hash: "#consent-revoked", writers: "drop" });
  assert.deepEqual(p.scripts(), [], "the marker closes the gate before the grant is read");
  assert.equal(p.location.hash, "#consent-revoked", "the marker stays while the refusal cannot be stored");
  assert.equal(p.bar(), null, "no prompt while revoked");
  const p2 = boot(example, { jar: withGrant({ list: [] }, example, ["marketing"]), hash: "#consent-revoked" });
  assert.deepEqual(p2.scripts(), []);
  assert.equal(p2.location.hash, "", "the marker is removed once the refusal is stored");
  assert.ok(p2.consentCookie().includes(";g=;s=;"));
}
{
  // settings: unselecting the only embed provider persists an explicit refusal; selecting the category selects the service
  const jar = withGrant({ list: [] }, example, ["embeds"]);
  const p = boot(example, { jar });
  p.control.click();
  assert.equal(p.sheet().open, true);
  assert.equal(p.box("ic-cat-embeds").checked, true);
  assert.equal(p.box("ic-svc-video").checked, true);
  p.box("ic-svc-video").checked = false; p.box("ic-svc-video").dispatch("change");
  assert.equal(p.box("ic-cat-embeds").checked, false, "unselecting the provider unselects its category");
  p.clickButton("Save", p.sheet());
  assert.ok(p.consentCookie().includes(";g=;s=;"), "everything off persists a refusal");
  assert.equal(p.embeds()[0].attrs.src, undefined, "the embed was torn down");
}
{
  // served srcdoc on a gated embed is an integration error: removed, warned, placeholder shown
  const p0 = boot(example);
  const f = p0.embeds()[0];
  assert.equal(f.attrs.srcdoc, undefined);
  const m = example;
  const jar = { list: [] };
  const p = (() => { const q = boot(m, { jar }); return q; })();
  const node = p.embeds()[0];
  node.setAttribute("srcdoc", "<p>hi</p>");
  p.control.click(); // reconcile → renderEmbeds → deactivate
  assert.equal(node.attrs.srcdoc, undefined, "srcdoc removed");
  assert.ok(p.state.warnings.some((w) => /integration error/.test(w)), "warning emitted");
}
{
  // reject, then load once on two instances: both stay live, opening Privacy keeps them, a later signal clears them
  const p = boot(example, { embedsPerService: 2 });
  p.clickButton("Reject");
  const [a, b] = p.embeds();
  p.clickButton("Load once", a.previousElementSibling);
  p.clickButton("Load once", b.previousElementSibling);
  assert.equal(a.attrs.src, "https://video.example.invalid/embed/1", "first instance live");
  assert.equal(b.attrs.src, "https://video.example.invalid/embed/2", "second instance live after the first");
  p.control.click();
  assert.equal(a.attrs.src, "https://video.example.invalid/embed/1", "opening Privacy keeps a one-time instance");
  p.clickButton("Cancel", p.sheet());
  p.navigator.globalPrivacyControl = true;
  p.control.click();
  assert.equal(a.attrs.src, undefined, "a later signal tears one-time instances down");
  assert.equal(b.attrs.src, undefined);
  assert.equal(p.state.reloads, 0);
}
{
  // a stale revocation marker retires once a decision persisted; the remembered grant survives the next document
  const jar = withGrant({ list: [] }, example, ["marketing"]);
  const p = boot(example, { jar, hash: "#consent-revoked", writers: "drop" });
  assert.equal(p.location.hash, "#consent-revoked");
  p.writers.mode = "ok";
  p.clickButton("Always allow");
  assert.equal(p.embeds()[0].attrs.src, "https://video.example.invalid/embed/1", "the service grant loads the embed");
  assert.ok(p.consentCookie().includes("s=video@"), "the service grant persisted");
  assert.equal(p.location.hash, "", "the stale marker was retired by the persisted decision");
  const p2 = boot(example, { jar, hash: p.location.hash });
  assert.ok(p2.consentCookie().includes("s=video@"), "the next document keeps the remembered grant");
  assert.equal(p2.embeds()[0].attrs.src, "https://video.example.invalid/embed/1");
}
{
  // crawler: no bar, nothing loads, nothing stored
  const p = boot(example, { ua: "Mozilla/5.0 (compatible; Googlebot/2.1)" });
  assert.equal(p.bar(), null);
  assert.deepEqual(p.scripts(), []);
  assert.equal(p.consentCookie(), undefined);
}

console.log("consent-gate dom: ok");
