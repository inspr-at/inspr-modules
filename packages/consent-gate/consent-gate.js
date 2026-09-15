// consent-gate — identity-free consent primitive for browser-facing surfaces.
//
// One manifest per surface declares the controller, the scope (host), the
// categories, the services (a Google tag destination or an embed, each with
// the storage it creates) and the texts. The gate renders nothing when only
// necessary storage exists, a contextual placeholder at each embed when only
// embeds need consent, and a non-modal bar with equivalent accept/reject
// choices when tracking destinations exist. Nothing optional loads before an
// affirmative, persisted, purpose-specific choice, and every load re-checks.
//
// The core (`insprConsentCore`) has no DOM dependency and is exercised by
// tests/consent-gate.mjs under plain Node. The renderer and the destination
// adapter below run only in a browser. Doctrine: AGENTS-DOMAIN-DEV
// "Pattern: web surfaces — cookies & consent".
(function (root) {
  "use strict";

  var VERSION = "1";
  var DEFAULT_COOKIE = "consent";
  var DEFAULT_PERMISSION_DAYS = 180;
  var MIN_REFUSAL_MONTHS = 6; // six UTC calendar months, whatever the day count
  var REVOKE_SUFFIX = "_revoked";
  var REVOKE_HASH = "consent-revoked";
  var FIRED_PREFIX = "consent_fired_";
  var BOT = /bot|crawl|spider|slurp|headless|lighthouse|pagespeed|preview/i;
  var CONSENT_MODE_KEYS = ["ad_storage", "ad_user_data", "ad_personalization", "analytics_storage", "functionality_storage", "personalization_storage", "security_storage"];
  var GTAG_HOSTS = ["www.googletagmanager.com", "googleads.g.doubleclick.net", "www.google.com", "www.google-analytics.com", "pagead2.googlesyndication.com"];
  var ID = /^[a-z][a-z0-9-]{0,31}$/;
  var ENTRY = /^([a-z][a-z0-9-]{0,31})@([0-9]{1,12})\.([0-9]{1,9})\.([0-9]{1,9})$/;
  var TAG_ID = /^[A-Z]{1,4}-[A-Za-z0-9_-]{1,40}$/;
  var HOSTNAME = /^(?=.{1,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/;
  var COOKIE_NAME = /^[A-Za-z0-9_.-]{1,64}\*?$/;
  var INT = /^[0-9]{1,12}$/;
  var HEX8 = /^[0-9a-f]{8}$/;

  // ---------------------------------------------------------------- core --

  function isObject(v) { return v !== null && typeof v === "object" && !Array.isArray(v); }
  function isNonEmptyString(v, max) { return typeof v === "string" && v.length > 0 && v.length <= (max || 200); }
  function isHost(v) { return typeof v === "string" && (HOSTNAME.test(v.toLowerCase()) || v === "localhost"); }

  // safeUrl: absolute https URL or a same-origin path. Anything else is inert.
  function safeUrl(value) {
    if (!isNonEmptyString(value, 2048) || /[\\\x00-\x1f\s]/.test(value)) return null;
    if (/^\/(?!\/)/.test(value)) return value;
    var m = /^https:\/\/([^\/?#]+)([\/?#].*)?$/i.exec(value);
    if (!m) return null;
    var host = m[1].toLowerCase().replace(/:\d+$/, "");
    return HOSTNAME.test(host) ? value : null;
  }
  function urlHost(value) {
    var v = String(value || "").trim();
    var m = /^(?:https?:)?\/\/([^\/?#\\]+)/i.exec(v);
    return m ? m[1].toLowerCase().replace(/^[^@]*@/, "").replace(/:\d+$/, "") : null;
  }
  function hostMatches(host, declared) { return host === declared || (host && host.slice(-(declared.length + 1)) === "." + declared); }

  // fingerprint: FNV-1a over a string. Used to bind a stored decision to the
  // manifest's controller and scope; it is a property of the surface, never
  // of the visitor.
  function fingerprint(str) {
    var h = 0x811c9dc5;
    for (var i = 0; i < str.length; i++) { h ^= str.charCodeAt(i); h = (h + ((h << 1) + (h << 4) + (h << 7) + (h << 8) + (h << 24))) >>> 0; }
    return ("0000000" + h.toString(16)).slice(-8);
  }
  function binding(m) { return fingerprint(String(m.controller) + "|" + String(m.scope).toLowerCase() + "|" + ((m.cookieName) || DEFAULT_COOKIE)); }

  // validateManifest returns { ok, errors }. An invalid manifest closes the
  // gate: nothing optional ever loads, nothing is rendered.
  function validateManifest(m) {
    var errors = [];
    if (!isObject(m)) return { ok: false, errors: ["manifest must be an object"] };
    if (m.version !== 1) errors.push("version must be 1");
    if (!(Number.isInteger(m.revision) && m.revision >= 1 && m.revision < 1e9)) errors.push("revision must be a positive integer");
    if (!(Number.isInteger(m.textVersion) && m.textVersion >= 1 && m.textVersion < 1e9)) errors.push("textVersion must be a positive integer");
    if (!isNonEmptyString(m.controller, 200)) errors.push("controller must name the controller");
    if (!isHost(m.scope)) errors.push("scope must be the surface's host name");
    if (m.cookieName !== undefined && !/^[A-Za-z0-9_-]{1,64}$/.test(String(m.cookieName))) errors.push("cookieName must be a short token");
    if (m.permissionDays !== undefined && !(Number.isInteger(m.permissionDays) && m.permissionDays >= 1 && m.permissionDays <= 365)) errors.push("permissionDays must be 1..365");
    if (m.refusalMonths !== undefined && !(Number.isInteger(m.refusalMonths) && m.refusalMonths >= MIN_REFUSAL_MONTHS && m.refusalMonths <= 24)) errors.push("refusalMonths must be at least " + MIN_REFUSAL_MONTHS);
    if (m.language !== undefined && !/^[a-z]{2}$/.test(String(m.language))) errors.push("language must be a two-letter code");
    if (m.privacyUrl !== undefined && !safeUrl(m.privacyUrl)) errors.push("privacyUrl must be an https URL or a same-origin path");
    if (!Array.isArray(m.categories) || !m.categories.length) errors.push("categories must be a non-empty array");
    var categories = Array.isArray(m.categories) ? m.categories : [];
    var ids = {};
    var requiredCount = 0;
    categories.forEach(function (c, i) {
      if (!isObject(c) || !ID.test(String(c.id))) { errors.push("categories[" + i + "].id invalid"); return; }
      if (ids[c.id]) errors.push("duplicate category id " + c.id);
      ids[c.id] = c;
      if (c.required === true) requiredCount++;
      if (c.revision !== undefined && !(Number.isInteger(c.revision) && c.revision >= 1 && c.revision < 1e9)) errors.push("category " + c.id + " revision must be a positive integer");
    });
    if (requiredCount !== 1) errors.push("exactly one category must be required (the necessary one)");
    if (!Array.isArray(m.services)) errors.push("services must be an array");
    var services = Array.isArray(m.services) ? m.services : [];
    var sids = {};
    services.forEach(function (s, i) {
      if (!isObject(s) || !ID.test(String(s.id))) { errors.push("services[" + i + "].id invalid"); return; }
      if (sids[s.id]) errors.push("duplicate service id " + s.id);
      sids[s.id] = s;
      if (!ids[s.category]) errors.push("service " + s.id + " names unknown category " + s.category);
      else if (ids[s.category].required === true) errors.push("service " + s.id + " sits in the required category; optional services need an optional category");
      if (!isNonEmptyString(s.provider, 200)) errors.push("service " + s.id + " needs a provider name");
      if (!Array.isArray(s.purposes) || !s.purposes.length || !s.purposes.every(function (p) { return isNonEmptyString(p, 120); })) errors.push("service " + s.id + " must list its purposes");
      var kinds = 0;
      if (s.destination !== undefined) {
        kinds++;
        var d = s.destination;
        if (!isObject(d) || d.type !== "gtag") errors.push("service " + s.id + " destination.type must be gtag");
        else {
          if (!(typeof d.tagId === "string" && TAG_ID.test(d.tagId))) errors.push("service " + s.id + " destination.tagId invalid");
          if (!Array.isArray(d.consent) || !d.consent.length || !d.consent.every(function (k) { return CONSENT_MODE_KEYS.indexOf(k) >= 0; })) errors.push("service " + s.id + " destination.consent must list Consent Mode keys");
          if (d.linkerAcceptIncoming !== undefined && typeof d.linkerAcceptIncoming !== "boolean") errors.push("service " + s.id + " destination.linkerAcceptIncoming must be boolean");
          if (d.conversion !== undefined) {
            var c = d.conversion;
            if (!isObject(c)) errors.push("service " + s.id + " conversion must be an object");
            else {
              if (!isNonEmptyString(c.sendTo, 120) || typeof d.tagId !== "string" || c.sendTo.indexOf(d.tagId + "/") !== 0 || !/^[A-Za-z0-9_-]+$/.test(c.sendTo.slice(d.tagId.length + 1))) errors.push("service " + s.id + " conversion.sendTo must be <tagId>/<label> of this destination");
              if (c.value !== undefined && !(typeof c.value === "number" && isFinite(c.value) && c.value >= 0)) errors.push("service " + s.id + " conversion.value must be a non-negative number");
              if (c.currency !== undefined && !/^[A-Z]{3}$/.test(String(c.currency))) errors.push("service " + s.id + " conversion.currency must be an ISO code");
            }
          }
        }
      }
      if (s.embed !== undefined) {
        kinds++;
        if (!isObject(s.embed) || !(typeof s.embed.host === "string" && HOSTNAME.test(s.embed.host.toLowerCase()))) errors.push("service " + s.id + " embed.host must be a host name");
      }
      if (kinds !== 1) errors.push("service " + s.id + " must declare exactly one of destination or embed");
      if (s.storage !== undefined) {
        if (!Array.isArray(s.storage)) errors.push("service " + s.id + " storage must be an array");
        else s.storage.forEach(function (st, j) {
          var label = "service " + s.id + " storage[" + j + "]";
          if (!isObject(st) || ["cookie", "local", "session"].indexOf(st.kind) < 0) { errors.push(label + " kind must be cookie|local|session"); return; }
          if (!(typeof st.name === "string" && (st.kind === "cookie" ? COOKIE_NAME.test(st.name) : /^[A-Za-z0-9_.:-]{1,128}$/.test(st.name)))) errors.push(label + " name invalid");
          if (st.days !== undefined && !(Number.isInteger(st.days) && st.days >= 0 && st.days <= 3650)) errors.push(label + " days invalid");
          if (st.kind === "cookie") {
            if (st.path !== undefined && !/^\/[A-Za-z0-9_\/.-]{0,200}$/.test(String(st.path))) errors.push(label + " path invalid");
            if (typeof st.name === "string" && st.name.slice(-1) === "*" && st.path !== undefined && st.path !== "/") errors.push(label + " wildcard names must use path / (other paths cannot be enumerated for cleanup; declare exact names)");
            if (st.domain !== undefined && !isHost(st.domain)) errors.push(label + " domain invalid");
            if (st.domain !== undefined && isHost(st.domain) && typeof m.scope === "string" && !hostMatches(m.scope.toLowerCase(), String(st.domain).toLowerCase())) errors.push(label + " domain must be the scope host or one of its parents");
          } else if (st.path !== undefined || st.domain !== undefined) errors.push(label + " path/domain apply to cookies only");
        });
      }
    });
    var text = isObject(m.text) ? m.text : null;
    if (!text || !Object.keys(text).length) errors.push("text must carry at least one language");
    else Object.keys(text).forEach(function (lang) {
      if (!/^[a-z]{2}$/.test(lang)) errors.push("text language keys must be two-letter codes");
      var t = text[lang];
      ["bar.text", "bar.accept", "bar.reject", "bar.settings", "sheet.title", "sheet.intro", "sheet.save", "sheet.cancel", "embed.loadOnce", "embed.always", "embed.open", "control"].forEach(function (path) {
        var v = path.split(".").reduce(function (acc, k) { return isObject(acc) ? acc[k] : undefined; }, t);
        if (!isNonEmptyString(v, 2000)) errors.push("text." + lang + "." + path + " missing");
      });
      var cats = isObject(t) && isObject(t.categories) ? t.categories : {};
      categories.forEach(function (c) { if (c && ID.test(String(c.id)) && (!isObject(cats[c.id]) || !isNonEmptyString(cats[c.id].label, 200))) errors.push("text." + lang + ".categories." + c.id + ".label missing"); });
      var svcs = isObject(t) && isObject(t.services) ? t.services : {};
      services.forEach(function (s) { if (s && s.embed && (!isObject(svcs[s.id]) || !isNonEmptyString(svcs[s.id].label, 200))) errors.push("text." + lang + ".services." + s.id + ".label missing for the embed"); });
    });
    if (m.language !== undefined && text && !text[m.language]) errors.push("language " + m.language + " has no text");
    return { ok: errors.length === 0, errors: errors };
  }

  function optionalCategories(m) { return m.categories.filter(function (c) { return c.required !== true; }).map(function (c) { return c.id; }); }
  function requiredCategory(m) { return m.categories.filter(function (c) { return c.required === true; })[0].id; }
  function categoryById(m, id) { return m.categories.filter(function (c) { return c.id === id; })[0] || null; }
  function categoryRevision(m, id) { var c = categoryById(m, id); return c && c.revision !== undefined ? c.revision : 1; }
  function servicesIn(m, categoryId) { return m.services.filter(function (s) { return s.category === categoryId; }); }
  function serviceById(m, id) { return m.services.filter(function (s) { return s.id === id; })[0] || null; }

  // tierOf: "none" (nothing optional), "contextual" (only embeds), "bar".
  function tierOf(m) {
    var optional = optionalCategories(m).filter(function (id) { return servicesIn(m, id).length > 0; });
    if (!optional.length) return "none";
    var onlyEmbeds = optional.every(function (id) { return servicesIn(m, id).every(function (s) { return s.embed !== undefined; }); });
    return onlyEmbeds ? "contextual" : "bar";
  }

  // Stored decision:
  //   "v1;b=<binding>;r=<revision>;v=<textVersion>;g=<cat@at.rev.tv,…>;s=<svc@at.rev.tv,…>;t=<unix>"
  // b binds the record to controller/scope/cookie name; every granted
  // category and remembered service carries its own grant time, the
  // category revision and the consent-text version it was given under; t is
  // the time of the last change. No identifier of any kind. Parsing is
  // strict. All times are integer seconds.
  function serializeEntries(list) { return list.slice().sort(function (a, b) { return a.id < b.id ? -1 : 1; }).map(function (e) { return e.id + "@" + e.at + "." + e.rev + "." + e.tv; }).join(","); }
  function serialize(rec) {
    return "v1;b=" + rec.binding + ";r=" + rec.revision + ";v=" + rec.textVersion + ";g=" + serializeEntries(rec.granted) + ";s=" + serializeEntries(rec.services) + ";t=" + Math.floor(rec.at);
  }
  function parseEntries(v) {
    if (v === "") return [];
    var out = [];
    var list = v.split(",");
    for (var i = 0; i < list.length; i++) {
      var m = ENTRY.exec(list[i]);
      if (!m) return null;
      out.push({ id: m[1], at: parseInt(m[2], 10), rev: parseInt(m[3], 10), tv: parseInt(m[4], 10) });
    }
    return out;
  }
  function parse(raw) {
    if (typeof raw !== "string" || !raw || raw.length > 2048) return null;
    var parts = raw.split(";");
    if (parts[0] !== "v1" || parts.length !== 7) return null;
    var seen = {};
    var out = {};
    for (var i = 1; i < parts.length; i++) {
      var eq = parts[i].indexOf("=");
      if (eq < 0) return null;
      var k = parts[i].slice(0, eq);
      var v = parts[i].slice(eq + 1);
      if (seen[k]) return null;
      seen[k] = true;
      if (k === "r" || k === "v" || k === "t") { if (!INT.test(v)) return null; out[k] = parseInt(v, 10); }
      else if (k === "b") { if (!HEX8.test(v)) return null; out.b = v; }
      else if (k === "g" || k === "s") { var e = parseEntries(v); if (!e) return null; out[k] = e; }
      else return null;
    }
    if (!(seen.b && seen.r && seen.v && seen.g && seen.s && seen.t)) return null;
    return { binding: out.b, revision: out.r, textVersion: out.v, granted: out.g, services: out.s, at: out.t };
  }

  function permissionSeconds(m) { return ((m && m.permissionDays) || DEFAULT_PERMISSION_DAYS) * 86400; }
  // refusalExpiry: the unix second at which a refusal stored at `at` may be
  // asked again — `refusalMonths` (at least six) UTC calendar months later.
  function refusalExpiry(m, at) {
    var months = Math.max((m && m.refusalMonths) || MIN_REFUSAL_MONTHS, MIN_REFUSAL_MONTHS);
    var d = new Date(at * 1000);
    var target = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + months, 1, d.getUTCHours(), d.getUTCMinutes(), d.getUTCSeconds()));
    var lastDay = new Date(Date.UTC(target.getUTCFullYear(), target.getUTCMonth() + 1, 0)).getUTCDate();
    target.setUTCDate(Math.min(d.getUTCDate(), lastDay));
    return Math.floor(target.getTime() / 1000);
  }

  function emptyGrant(m) { var g = {}; optionalCategories(m).forEach(function (id) { g[id] = false; }); return g; }

  // liveEntries: the stored entries that are still valid right now — bound
  // to the current category revision, not future-dated, not expired.
  function liveEntries(m, entries, now, resolveCategory) {
    return entries.filter(function (e) {
      var cat = resolveCategory(e.id);
      return !!cat && e.rev === categoryRevision(m, cat) && e.at <= now && now - e.at < permissionSeconds(m);
    });
  }

  // decide: what the page may do right now. `granted` covers optional
  // categories, `services` the individually remembered services, `entries`
  // the surviving stored entries (kept verbatim on the next persist).
  function decide(input) {
    var m = input.manifest;
    var tier = input.invalid ? "none" : tierOf(m);
    var none = input.invalid ? {} : emptyGrant(m);
    var closed = { tier: tier, prompt: false, granted: none, services: [], entries: { granted: [], services: [] }, persist: "none" };
    if (input.invalid || input.blocked || input.bot) return closed;
    if (input.signal) { closed.persist = "refuse"; return closed; }
    if (input.revoked) return closed;
    var now = input.now;
    if (!(typeof now === "number" && isFinite(now) && now > 0)) return closed;
    var stored = input.stored || null;
    var open = { tier: tier, prompt: tier === "bar", granted: none, services: [], entries: { granted: [], services: [] }, persist: "none" };
    if (!stored || stored.binding !== binding(m) || stored.revision !== m.revision || stored.at > now) return open;
    var optional = optionalCategories(m);
    var g = liveEntries(m, stored.granted, now, function (id) { return optional.indexOf(id) >= 0 ? id : null; });
    var s = liveEntries(m, stored.services, now, function (id) { var sv = serviceById(m, id); return sv && sv.embed ? sv.category : null; });
    if (!g.length && !s.length) {
      if (!stored.granted.length && !stored.services.length && now < refusalExpiry(m, stored.at)) return closed;
      return open;
    }
    var granted = {};
    optional.forEach(function (id) { granted[id] = g.some(function (e) { return e.id === id; }); });
    var services = s.filter(function (e) { return !granted[serviceById(m, e.id).category]; }).map(function (e) { return e.id; });
    return { tier: tier, prompt: false, granted: granted, services: services, entries: { granted: g, services: s }, persist: "none" };
  }

  // consentModeSignals: Google Consent Mode v2 defaults (all denied) and the
  // update derived from granted categories. Only keys a service declares can
  // ever be granted, so an undisclosed purpose stays denied.
  function consentModeSignals(m, granted) {
    var defaults = {};
    var update = {};
    CONSENT_MODE_KEYS.forEach(function (k) { defaults[k] = "denied"; update[k] = "denied"; });
    (m.services || []).forEach(function (s) {
      if (!s.destination || !granted[s.category]) return;
      s.destination.consent.forEach(function (k) { update[k] = "granted"; });
    });
    return { defaults: defaults, update: update };
  }

  // declaredHosts: every host a service may contact once authorised.
  function declaredHosts(m) {
    var hosts = [];
    (m.services || []).forEach(function (s) {
      if (s.destination && s.destination.type === "gtag") GTAG_HOSTS.forEach(function (h) { if (hosts.indexOf(h) < 0) hosts.push(h); });
      if (s.embed) { var h = String(s.embed.host).toLowerCase(); if (hosts.indexOf(h) < 0) hosts.push(h); }
    });
    return hosts;
  }

  // decodeEntities: enough of HTML character references to see through
  // obfuscated attribute values.
  function decodeEntities(s) {
    return String(s).replace(/&(#x[0-9a-f]+|#[0-9]+|amp|lt|gt|quot|apos|sol|colon);/gi, function (_, e) {
      var l = e.toLowerCase();
      if (l === "amp") return "&"; if (l === "lt") return "<"; if (l === "gt") return ">"; if (l === "quot") return '"'; if (l === "apos") return "'"; if (l === "sol") return "/"; if (l === "colon") return ":";
      var code = l.charAt(1) === "x" ? parseInt(l.slice(2), 16) : parseInt(l.slice(1), 10);
      return isFinite(code) && code > 0 && code < 0x110000 ? String.fromCodePoint(code) : "";
    });
  }

  // tokenizeTags: a small quote-aware scanner over served HTML. Comments are
  // skipped, raw-text elements (script, style, textarea, title) contribute
  // only their start tag, attribute values may contain ">" inside quotes,
  // attribute names are lower-cased and the last occurrence wins.
  function tokenizeTags(html) {
    var out = [];
    var i = 0;
    var n = html.length;
    while (i < n) {
      var lt = html.indexOf("<", i);
      if (lt < 0) break;
      if (html.substr(lt, 4) === "<!--") { var end = html.indexOf("-->", lt + 4); i = end < 0 ? n : end + 3; continue; }
      var nm = /^<([a-zA-Z][a-zA-Z0-9-]*)/.exec(html.slice(lt, lt + 40));
      if (!nm) { i = lt + 1; continue; }
      var name = nm[1].toLowerCase();
      var j = lt + 1 + nm[1].length;
      var attrs = {};
      while (j < n) {
        var ch = html.charAt(j);
        if (ch === ">") { j++; break; }
        if (/\s|\//.test(ch)) { j++; continue; }
        var k = j;
        while (j < n && !/[\s=\/>]/.test(html.charAt(j))) j++;
        var aname = html.slice(k, j).toLowerCase();
        while (j < n && /\s/.test(html.charAt(j))) j++;
        var value = "";
        if (html.charAt(j) === "=") {
          j++;
          while (j < n && /\s/.test(html.charAt(j))) j++;
          var q = html.charAt(j);
          if (q === '"' || q === "'") { var close = html.indexOf(q, j + 1); value = html.slice(j + 1, close < 0 ? n : close); j = close < 0 ? n : close + 1; }
          else { var v0 = j; while (j < n && !/[\s>]/.test(html.charAt(j))) j++; value = html.slice(v0, j); }
        }
        if (aname) attrs[aname] = value;
      }
      out.push({ name: name, attrs: attrs });
      if (name === "script" || name === "style" || name === "textarea" || name === "title") {
        var closeRe = new RegExp("</" + name + "\\s*>", "i");
        closeRe.lastIndex = 0;
        var rest = html.slice(j);
        var cm = closeRe.exec(rest);
        j = cm ? j + cm.index + cm[0].length : n;
      }
      i = j;
    }
    return out;
  }

  // guardServedHtml: the reusable pre-consent guard. Given served HTML and the
  // requests captured before any choice, it reports every active resource
  // (script/iframe/img/link/video/audio/source/object/embed/track with a live
  // URL attribute, srcset candidates included, protocol-relative and
  // entity-encoded URLs decoded, comments and raw-text contents ignored),
  // every gated embed served with srcdoc, and every request that touches a
  // declared host. Inert references — the manifest JSON, data-src, plain
  // anchors — do not count.
  function guardServedHtml(input) {
    var m = input.manifest;
    var hosts = declaredHosts(m);
    var violations = [];
    var active = ["script", "iframe", "img", "link", "video", "audio", "source", "object", "embed", "track"];
    function flag(element, attribute, url) {
      var host = urlHost(decodeEntities(url));
      if (host && hosts.some(function (h) { return hostMatches(host, h); })) violations.push({ kind: "markup", element: element, attribute: attribute, url: url });
    }
    tokenizeTags(String(input.html || "")).forEach(function (t) {
      if (active.indexOf(t.name) < 0) return;
      if (t.name === "iframe" && t.attrs.srcdoc !== undefined && t.attrs["data-consent-embed"] !== undefined) violations.push({ kind: "markup", element: "iframe", attribute: "srcdoc", url: "" });
      ["src", "href", "data", "poster"].forEach(function (a) { if (t.attrs[a] !== undefined) flag(t.name, a, t.attrs[a]); });
      if (t.attrs.srcset !== undefined) decodeEntities(t.attrs.srcset).split(",").forEach(function (cand) { var u = cand.trim().split(/\s+/)[0]; if (u) flag(t.name, "srcset", u); });
    });
    (input.requests || []).forEach(function (u) {
      var host = urlHost(u);
      if (host && hosts.some(function (h) { return hostMatches(host, h); })) violations.push({ kind: "request", url: String(u) });
    });
    return { ok: violations.length === 0, violations: violations, hosts: hosts };
  }

  // createCore binds the policy to an environment (cookie jar, storages,
  // signals, clock, host). Every accessor is exception-safe. A failing
  // accessor never authorises anything: a failing cookie or clock reads as
  // "no decision", a failing revocation, signal or host read as "blocked".
  function createCore(manifest, env) {
    var validation = validateManifest(manifest);
    var invalid = !validation.ok;
    var m = invalid ? { categories: [], services: [] } : manifest;
    var cookieName = (!invalid && manifest.cookieName) || DEFAULT_COOKIE;
    var revokeKey = cookieName + REVOKE_SUFFIX;
    var revoked = false; // in-page revocation; latched by a privacy signal too
    var pendingRefusal = false; // a refusal that could not be stored yet
    var onceInstances = [];
    var listeners = [];
    var teardowns = {};

    function attempt(fn, fallback) { try { return fn(); } catch (_) { return fallback; } }
    var BLOCKED = { blocked: true };
    function now() { return attempt(function () { return env.now(); }, NaN); }
    function stored() { return attempt(function () { return parse(env.readCookie(cookieName)); }, null); }
    function sessionRevoked() { return attempt(function () { return env.readSession(revokeKey) === "1"; }, BLOCKED); }
    var latching = false;
    // An observed affirmative signal is latched in the page and persisted as
    // a refusal at once, so the next document does not revive an older grant.
    function signal() {
      var v = attempt(function () { return env.signal() === true; }, BLOCKED);
      if (v === true && !revoked && !latching && !invalid) { latching = true; try { refuseAll(); } finally { latching = false; } }
      if (v === true) revoked = true;
      return v;
    }
    // storeRefusal writes the refusal as a cookie, else as a session
    // revocation; a failure is remembered and retried on every policy check.
    function storeRefusal() {
      var persisted = persist([], []);
      if (!persisted) persisted = attempt(function () { env.writeSession(revokeKey, "1"); return env.readSession(revokeKey) === "1"; }, false);
      else attempt(function () { env.removeSession(revokeKey); }, null);
      pendingRefusal = !persisted;
      return persisted;
    }
    function retryRefusal() {
      if (pendingRefusal && !latching && !invalid) { latching = true; try { storeRefusal(); } finally { latching = false; } }
    }
    function bot() { return attempt(function () { return env.bot() === true; }, BLOCKED); }
    function hostOk() {
      if (invalid || typeof env.host !== "function") return true;
      var h = attempt(function () { return String(env.host()).toLowerCase(); }, BLOCKED);
      return h !== BLOCKED && (h === String(manifest.scope).toLowerCase() || h === "localhost" || h === "127.0.0.1");
    }
    function blockedNow() {
      var rev = sessionRevoked();
      var sig = signal();
      var b = bot();
      return rev === BLOCKED || sig === BLOCKED || b === BLOCKED || !hostOk();
    }

    function persist(granted, services) {
      if (invalid) return false;
      var at = Math.floor(now());
      if (!(isFinite(at) && at > 0)) return false;
      var rec = { binding: binding(manifest), revision: manifest.revision, textVersion: manifest.textVersion, granted: granted, services: services, at: at };
      var value = serialize(rec);
      var maxAge = granted.length || services.length ? permissionSeconds(m) : Math.max(refusalExpiry(m, at) - at, 1);
      var written = attempt(function () { return env.writeCookie(cookieName, value, maxAge) !== false; }, false);
      if (!written) return false;
      var back = stored();
      return !!back && serialize(back) === value;
    }

    function current() {
      if (invalid) return decide({ manifest: m, invalid: true });
      retryRefusal();
      if (blockedNow()) return decide({ manifest: m, blocked: true });
      return decide({ manifest: m, stored: stored(), now: now(), signal: signal(), bot: bot(), revoked: revoked || sessionRevoked() === true });
    }

    function emit() { listeners.forEach(function (fn) { attempt(function () { fn(current()); }, null); }); }

    // cleanupServices removes exactly the storage the given services declare
    // — exact cookie names unconditionally at the declared path and domain,
    // wildcards for every visible match — plus the adapter's own markers,
    // and runs registered teardowns. One-time instance permissions of those
    // services are dropped.
    function cleanupServices(services) {
      var ids = services.map(function (s) { return s.id; });
      onceInstances = onceInstances.filter(function (o) { return ids.indexOf(o.service) < 0; });
      services.forEach(function (s) {
        (Array.isArray(s.storage) ? s.storage : []).forEach(function (st) {
          attempt(function () {
            if (st.kind === "cookie") env.clearCookie({ name: st.name, path: st.path || "/", domain: st.domain || null, exact: st.name.slice(-1) !== "*" });
            else if (st.kind === "local") env.removeLocal(st.name);
            else env.removeSession(st.name);
          }, null);
        });
        if (s.destination) attempt(function () { env.removeSession(FIRED_PREFIX + s.id); }, null);
        (teardowns[s.id] || []).forEach(function (fn) { attempt(fn, null); });
      });
    }
    function servicesOfCategories(ids) { return m.services.filter(function (s) { return ids.indexOf(s.category) >= 0; }); }

    // refuseAll persists a refusal (cookie, else session revocation) and
    // returns whether the refusal will be visible to the next page.
    function refuseAll() {
      revoked = true;
      onceInstances = [];
      if (invalid) return false;
      cleanupServices(m.services);
      var persisted = storeRefusal();
      emit();
      return persisted;
    }

    // applyGrant persists the wanted categories and services, keeping the
    // grant time and revision of entries that survive unchanged, and cleans
    // up everything that was dropped. ok means "authorised now".
    function applyGrant(wantedCats, wantedSvcs) {
      var before = current();
      var at = Math.floor(now());
      var dropCats = optionalCategories(m).filter(function (id) { return before.granted[id] && wantedCats.indexOf(id) < 0; });
      var dropSvcs = before.services.filter(function (id) { return wantedSvcs.indexOf(id) < 0 && wantedCats.indexOf(serviceById(m, id).category) < 0; });
      cleanupServices(servicesOfCategories(dropCats).concat(dropSvcs.map(function (id) { return serviceById(m, id); })));
      if (!wantedCats.length && !wantedSvcs.length) { var p = refuseAll(); return { ok: p, persisted: p, decision: current() }; }
      var granted = wantedCats.map(function (id) {
        var kept = before.entries.granted.filter(function (e) { return e.id === id; })[0];
        return kept ? kept : { id: id, at: at, rev: categoryRevision(m, id), tv: manifest.textVersion };
      });
      var services = wantedSvcs.filter(function (id) { return wantedCats.indexOf(serviceById(m, id).category) < 0; }).map(function (id) {
        var kept = before.entries.services.filter(function (e) { return e.id === id; })[0];
        return kept ? kept : { id: id, at: at, rev: categoryRevision(m, serviceById(m, id).category), tv: manifest.textVersion };
      });
      if (!persist(granted, services)) { var p2 = refuseAll(); return { ok: false, persisted: p2, decision: current() }; }
      revoked = false;
      pendingRefusal = false;
      attempt(function () { env.removeSession(revokeKey); }, null);
      var after = current();
      var effective = wantedCats.every(function (id) { return after.granted[id] === true; }) &&
        wantedSvcs.every(function (id) { return after.services.indexOf(id) >= 0 || after.granted[serviceById(m, id).category] === true; });
      if (!effective) { var p3 = refuseAll(); return { ok: false, persisted: p3, decision: current() }; }
      emit();
      return { ok: true, persisted: true, decision: after };
    }

    function canGrant() { return !invalid && !blockedNow() && signal() === false && bot() === false && isFinite(now()); }
    function validServiceIds(ids) { return (ids || []).filter(function (id) { var s = serviceById(m, id); return s && s.embed; }); }

    var core = {
      valid: !invalid,
      errors: validation.errors,
      manifest: manifest,
      tier: invalid ? "none" : tierOf(m),
      cookieName: cookieName,
      revokeKey: revokeKey,
      binding: invalid ? null : binding(manifest),
      boot: function () {
        var d = current();
        if (d.persist === "refuse") refuseAll();
        return current();
      },
      current: current,
      // grant persists exactly the given optional categories plus the given
      // remembered services (embed services outside those categories).
      // An empty grant is a refusal and is processed even while a privacy
      // signal or a broken accessor would refuse a new grant.
      grant: function (ids, serviceIds) {
        var optional = invalid ? [] : optionalCategories(m);
        var wanted = (ids || []).filter(function (id) { return optional.indexOf(id) >= 0; });
        var svcs = serviceIds === undefined ? (invalid ? [] : current().services.filter(function (id) { return wanted.indexOf(serviceById(m, id).category) < 0; })) : validServiceIds(serviceIds);
        if (!wanted.length && !svcs.length) { var p = refuseAll(); return { ok: p, persisted: p, decision: current() }; }
        if (!canGrant()) return { ok: false, persisted: false, decision: current() };
        return applyGrant(wanted, svcs);
      },
      // grantService remembers one embed service (its declared purposes) for
      // the permission lifetime without granting its whole category.
      grantService: function (serviceId) {
        if (!canGrant()) return { ok: false, persisted: false, decision: current() };
        var s = serviceById(m, serviceId);
        if (!s || !s.embed) return { ok: false, persisted: false, decision: current() };
        var d = current();
        var granted = optionalCategories(m).filter(function (id) { return d.granted[id]; });
        var services = d.services.slice();
        if (services.indexOf(serviceId) < 0) services.push(serviceId);
        return applyGrant(granted, services);
      },
      refuse: function () { var p = refuseAll(); return { ok: p, persisted: p, decision: current() }; },
      withdraw: function () { var p = refuseAll(); return { ok: p, persisted: p, decision: current() }; },
      authorized: function (categoryId) {
        if (invalid) return false;
        if (categoryId === requiredCategory(m)) return !blockedNow();
        return current().granted[categoryId] === true;
      },
      // loadOnce authorises one embed instance for this page view only; the
      // permission dies with its service's category or an explicit refusal.
      loadOnce: function (serviceId, instance) {
        if (!canGrant() || instance === undefined || instance === null) return false;
        var s = serviceById(m, serviceId);
        if (!s || !s.embed) return false;
        onceInstances.push({ service: serviceId, instance: instance });
        return true;
      },
      authorizedInstance: function (serviceId, instance) {
        if (invalid || blockedNow() || signal() !== false || bot() !== false || !isFinite(now()) || revoked) return false;
        if (onceInstances.some(function (o) { return o.service === serviceId && o.instance === instance; })) return true;
        return this.authorizedService(serviceId);
      },
      authorizedService: function (serviceId) {
        if (invalid) return false;
        var s = serviceById(m, serviceId);
        if (!s) return false;
        var d = current();
        return d.granted[s.category] === true || d.services.indexOf(serviceId) >= 0;
      },
      signals: function () { return consentModeSignals(m, invalid ? {} : current().granted); },
      hosts: function () { return declaredHosts(m); },
      onChange: function (fn) { listeners.push(fn); },
      // registerTeardown runs when the service loses authorisation.
      registerTeardown: function (serviceId, fn) { (teardowns[serviceId] = teardowns[serviceId] || []).push(fn); },
      optionalCategories: function () { return invalid ? [] : optionalCategories(m); },
      requiredCategory: function () { return invalid ? null : requiredCategory(m); },
      embedServices: function () { return invalid ? [] : m.services.filter(function (s) { return s.embed; }); },
      service: function (id) { return invalid ? null : serviceById(m, id); }
    };
    return core;
  }

  root.insprConsentCore = { VERSION: VERSION, validateManifest: validateManifest, tierOf: tierOf, parse: parse, serialize: serialize, decide: decide, consentModeSignals: consentModeSignals, declaredHosts: declaredHosts, guardServedHtml: guardServedHtml, tokenizeTags: tokenizeTags, createCore: createCore, safeUrl: safeUrl, binding: binding, refusalExpiry: refusalExpiry, decodeEntities: decodeEntities, BOT: BOT, MIN_REFUSAL_MONTHS: MIN_REFUSAL_MONTHS, REVOKE_HASH: REVOKE_HASH };

  if (typeof document === "undefined") return;

  // ------------------------------------------------------------ browser --

  var script = document.currentScript;
  var ds = script ? script.dataset : {};

  function readManifest() {
    if (root.insprConsentManifest) return root.insprConsentManifest;
    var sel = ds.consentManifest || "#consent-manifest";
    var el0 = document.querySelector(sel);
    if (!el0) return null;
    try { return JSON.parse(el0.textContent); } catch (_) { return null; }
  }

  var manifest = readManifest();

  var env = {
    now: function () { return Date.now() / 1000; },
    host: function () { return location.hostname; },
    readCookie: function (name) {
      var raw = document.cookie;
      var parts = raw ? raw.split("; ") : [];
      for (var i = 0; i < parts.length; i++) if (parts[i].indexOf(name + "=") === 0) return decodeURIComponent(parts[i].slice(name.length + 1));
      return null;
    },
    writeCookie: function (name, value, maxAge) {
      var secure = location.protocol === "https:" ? "; Secure" : "";
      document.cookie = name + "=" + encodeURIComponent(value) + "; Max-Age=" + maxAge + "; Path=/; SameSite=Lax" + secure;
      return true;
    },
    // clearCookie deletes at exactly the declared path and domain (host-only
    // when no domain is declared): exact names unconditionally — the
    // current document may not even see a cookie scoped to another path —
    // and wildcards for every visible match.
    clearCookie: function (st) {
      var suffix = "=; Max-Age=0; Path=" + st.path + (st.domain ? "; Domain=" + st.domain : "");
      if (st.exact) { document.cookie = st.name + suffix; return; }
      var names = (document.cookie ? document.cookie.split("; ") : []).map(function (c) { return c.split("=")[0]; });
      var re = new RegExp("^" + st.name.slice(0, -1).replace(/[.+^${}()|[\]\\]/g, "\\$&") + ".*$");
      names.forEach(function (n) { if (re.test(n)) document.cookie = n + suffix; });
    },
    readSession: function (k) { return sessionStorage.getItem(k); },
    writeSession: function (k, v) { sessionStorage.setItem(k, v); return true; },
    removeSession: function (k) { sessionStorage.removeItem(k); },
    removeLocal: function (k) { localStorage.removeItem(k); },
    signal: function () { return navigator.globalPrivacyControl === true || navigator.doNotTrack === "1" || root.doNotTrack === "1"; },
    bot: function () { return BOT.test(navigator.userAgent || ""); }
  };

  var core = createCore(manifest || {}, env);
  var lang = pickLanguage();
  var T = lang ? manifest.text[lang] : null;
  var bar = null;
  var sheet = null;
  var boxes = {};
  var svcBoxes = {};
  var loadedDestinations = {};

  function pickLanguage() {
    if (!core.valid) return null;
    var langs = Object.keys(manifest.text);
    var want = manifest.language || (document.documentElement.lang || "").slice(0, 2).toLowerCase();
    return langs.indexOf(want) >= 0 ? want : langs[0];
  }

  function el(tag, attrs, children) {
    var node = document.createElement(tag);
    Object.keys(attrs || {}).forEach(function (k) {
      if (k === "text") node.textContent = attrs[k];
      else node.setAttribute(k, attrs[k]);
    });
    (children || []).forEach(function (c) { node.appendChild(c); });
    return node;
  }
  function labelled(strong, rest) {
    var l = document.createElement("span");
    l.appendChild(el("strong", { text: strong }));
    l.appendChild(document.createTextNode(rest ? " " + rest : ""));
    return l;
  }
  function catText(id) { return (T.categories && T.categories[id]) || { label: id, description: "" }; }
  function svcText(id) { return (T.services && T.services[id]) || {}; }
  function warn(msg, extra) { try { console.warn("consent-gate: " + msg, extra || ""); } catch (_) { /* no console */ } }

  // --- destinations (Google tag with Consent Mode v2 in basic mode) ---
  function gtag() { root.dataLayer.push(arguments); }
  function anyDestinationLoaded() { return Object.keys(loadedDestinations).length > 0; }
  // lostAuthorization: a destination that is loaded but no longer authorised.
  function lostAuthorization() { return Object.keys(loadedDestinations).some(function (id) { return !core.authorizedService(id); }); }

  function loadDestinations() {
    manifest.services.forEach(function (s) {
      if (!s.destination || loadedDestinations[s.id]) return;
      if (!core.authorized(s.category) || !core.authorizedService(s.id)) return;
      loadedDestinations[s.id] = true;
      var sig = core.signals();
      root.dataLayer = root.dataLayer || [];
      root.gtag = gtag;
      gtag("consent", "default", sig.defaults);
      gtag("consent", "update", sig.update);
      gtag("js", new Date());
      var cfg = { cookie_domain: location.hostname, cookie_flags: "SameSite=Lax;Secure" };
      if (s.destination.linkerAcceptIncoming === true) cfg.linker = { accept_incoming: true };
      gtag("config", s.destination.tagId, cfg);
      fireConversion(s);
      var node = document.createElement("script");
      node.async = true;
      node.src = "https://www.googletagmanager.com/gtag/js?id=" + encodeURIComponent(s.destination.tagId);
      document.head.appendChild(node);
    });
  }

  // A conversion fires only on pages that name the service in
  // data-consent-fire, once per session, to the consented destination only.
  function fireConversion(s) {
    var fire = (ds.consentFire || "").split(/[ ,]+/).filter(Boolean);
    var c = s.destination.conversion;
    if (!c || fire.indexOf(s.id) < 0 || c.sendTo.indexOf(s.destination.tagId + "/") !== 0) return;
    if (!core.authorizedService(s.id)) return;
    var key = FIRED_PREFIX + s.id;
    try {
      if (sessionStorage.getItem(key) === "1") return;
      sessionStorage.setItem(key, "1");
    } catch (_) { /* fire once per page load */ }
    gtag("event", "conversion", { send_to: c.sendTo, value: c.value === undefined ? 1.0 : c.value, currency: c.currency || "EUR" });
  }

  function denyDestinations() {
    if (!anyDestinationLoaded()) return;
    try { gtag("consent", "update", core.signals().defaults); } catch (_) { /* best effort */ }
  }

  // --- embeds ---
  function embedNodes(s) { return Array.prototype.slice.call(document.querySelectorAll('[data-consent-embed="' + s.id + '"]')); }

  function embedUrl(s, node) {
    var url = safeUrl(node.getAttribute("data-src"));
    if (!url || url.charAt(0) === "/") return null;
    return hostMatches(urlHost(url), String(s.embed.host).toLowerCase()) ? url : null;
  }

  function activate(s, node) {
    if (node.getAttribute("data-consent-active") === "1") return;
    var url = embedUrl(s, node);
    if (!url) { warn("embed " + s.id + " has no https data-src on the declared host; left inert"); return; }
    var ph = node.previousElementSibling;
    if (ph && ph.classList.contains("ic-embed")) ph.parentNode.removeChild(ph);
    node.setAttribute("data-consent-active", "1");
    node.setAttribute("src", url);
    node.hidden = false;
  }

  // deactivate tears the browsing context down whether the gate or the
  // served markup started it: src and srcdoc go, the document is replaced,
  // the placeholder returns.
  function deactivate(s, node) {
    var live = node.getAttribute("data-consent-active") === "1" || node.hasAttribute("src") || node.hasAttribute("srcdoc");
    if (live) {
      if (node.getAttribute("data-consent-active") !== "1") warn("integration error: embed " + s.id + " served with a live src or srcdoc; remove it from the markup");
      node.removeAttribute("data-consent-active");
      node.removeAttribute("src");
      node.removeAttribute("srcdoc");
      try { if (node.contentWindow) node.contentWindow.location.replace("about:blank"); } catch (_) { /* cross-origin: attribute removal suffices */ }
    }
    node.hidden = true;
    var prev = node.previousElementSibling;
    if (!(prev && prev.classList.contains("ic-embed"))) node.parentNode.insertBefore(placeholderFor(s, node), node);
  }

  function placeholderFor(s, node) {
    var st = svcText(s.id);
    var once = el("button", { type: "button", class: "ic-btn", text: T.embed.loadOnce });
    var always = el("button", { type: "button", class: "ic-btn", text: T.embed.always });
    var open = el("a", { class: "ic-link", href: "https://" + s.embed.host + "/", rel: "noopener noreferrer", target: "_blank", text: T.embed.open + " " + s.embed.host });
    once.addEventListener("click", function () { if (reconcile()) return; if (core.loadOnce(s.id, node)) activate(s, node); });
    always.addEventListener("click", function () { if (reconcile()) return; settle(core.grantService(s.id), false); });
    return el("div", { class: "ic-embed", role: "group", "aria-label": st.label || s.provider }, [
      el("p", { class: "ic-embed-title", text: st.label || s.provider }),
      el("p", { class: "ic-embed-text", text: st.description || "" }),
      el("div", { class: "ic-actions" }, [once, always, open])
    ]);
  }

  function renderEmbeds() {
    manifest.services.forEach(function (s) {
      if (!s.embed) return;
      embedNodes(s).forEach(function (node) {
        if (core.authorizedInstance(s.id, node)) activate(s, node); else deactivate(s, node);
      });
    });
  }
  // teardownEmbeds deactivates every embed without activating anything.
  function teardownEmbeds() {
    manifest.services.forEach(function (s) { if (s.embed) embedNodes(s).forEach(function (node) { deactivate(s, node); }); });
  }

  // --- bar & sheet ---
  function removeBar() {
    if (bar && bar.parentNode) bar.parentNode.removeChild(bar);
    bar = null;
    document.removeEventListener("keydown", onEscape);
  }
  function onEscape(e) { if (e.key === "Escape" && bar) refuse(); }

  // settle applies a decision change. Destinations that lost authorisation
  // are denied; because a loaded tag has no reliable teardown the page
  // reloads — carrying a revocation marker in the URL when the refusal
  // could not be persisted, so the next document closes the gate before it
  // consults any surviving grant. Embeds are torn down in place.
  var settling = false;
  function settle(result, dropping) {
    if (settling) return;
    settling = true;
    try {
      // Decide about loaded destinations before anything new is loaded.
      var lost = dropping || result.ok === false || lostAuthorization();
      if (lost && anyDestinationLoaded()) {
        denyDestinations();
        if (result.persisted === false) {
          warn("refusal could not be persisted; reloading with a revocation marker");
          try { history.replaceState(null, "", location.pathname + location.search + "#" + REVOKE_HASH); } catch (_) { location.hash = REVOKE_HASH; }
        }
        teardownEmbeds();
        location.reload();
        return;
      }
      renderState();
    } finally { settling = false; }
  }

  // reconcile: before any user-triggered activation, settle a loaded
  // destination that lost authorisation (expiry, an observed signal, a
  // failed grant). Returns true when the page is reloading.
  function reconcile() {
    if (!lostAuthorization()) return false;
    settle({ ok: true, persisted: true }, true);
    return true;
  }

  function acceptAll() {
    removeBar();
    settle(core.grant(core.optionalCategories(), core.embedServices().map(function (s) { return s.id; })), false);
  }
  function refuse() {
    removeBar();
    settle(core.refuse(), true);
  }

  function renderBar() {
    if (bar) return;
    var reject = el("button", { type: "button", class: "ic-btn", "data-consent": "reject", text: T.bar.reject });
    var accept = el("button", { type: "button", class: "ic-btn", "data-consent": "accept", text: T.bar.accept });
    var settings = el("button", { type: "button", class: "ic-link", "data-consent-open": "", text: T.bar.settings });
    reject.addEventListener("click", refuse);
    accept.addEventListener("click", acceptAll);
    settings.addEventListener("click", openSheet);
    var text = el("p", { class: "ic-text", text: T.bar.text });
    var privacy = safeUrl(manifest.privacyUrl);
    if (T.bar.link && privacy) { text.appendChild(document.createTextNode(" ")); text.appendChild(el("a", { href: privacy, text: T.bar.link })); }
    bar = el("section", { class: "ic-bar", role: "region", "aria-label": T.sheet.title }, [text, el("div", { class: "ic-actions" }, [reject, accept, settings])]);
    document.body.appendChild(bar);
    document.addEventListener("keydown", onEscape);
  }

  function openSheet() {
    if (!core.valid || reconcile()) return;
    if (!sheet) {
      var rows = [];
      var req = core.requiredCategory();
      var reqBox = el("input", { type: "checkbox", id: "ic-cat-" + req, checked: "", disabled: "" });
      var reqLabel = el("label", { for: "ic-cat-" + req }); reqLabel.appendChild(labelled(catText(req).label, catText(req).description));
      rows.push(el("div", { class: "ic-row" }, [reqBox, reqLabel]));
      core.optionalCategories().forEach(function (id) {
        var box = el("input", { type: "checkbox", id: "ic-cat-" + id });
        boxes[id] = box;
        var label = el("label", { for: "ic-cat-" + id }); label.appendChild(labelled(catText(id).label, catText(id).description));
        rows.push(el("div", { class: "ic-row" }, [box, label]));
        // Remembered embed services show as their own rows under the
        // category, so a single provider can be revoked without touching
        // its siblings.
        core.embedServices().filter(function (s) { return s.category === id; }).forEach(function (s) {
          var sbox = el("input", { type: "checkbox", id: "ic-svc-" + s.id });
          svcBoxes[s.id] = sbox;
          var slabel = el("label", { for: "ic-svc-" + s.id }); slabel.appendChild(labelled(svcText(s.id).label || s.provider, svcText(s.id).description));
          rows.push(el("div", { class: "ic-row ic-row-service" }, [sbox, slabel]));
          // A category selects all its services; unselecting one service
          // turns the category into an explicit per-service selection.
          box.addEventListener("change", function () { sbox.checked = box.checked; });
          sbox.addEventListener("change", function () { if (!sbox.checked) box.checked = false; });
        });
      });
      var save = el("button", { type: "button", class: "ic-btn", text: T.sheet.save });
      var cancel = el("button", { type: "button", class: "ic-btn", text: T.sheet.cancel });
      var privacy = safeUrl(manifest.privacyUrl);
      var mini = T.sheet.link && privacy ? [el("p", { class: "ic-mini" }, [el("a", { href: privacy, text: T.sheet.link })])] : [];
      sheet = el("dialog", { class: "ic-sheet", "aria-labelledby": "ic-sheet-title" }, [el("h2", { id: "ic-sheet-title", text: T.sheet.title }), el("p", { text: T.sheet.intro })].concat(rows, [el("div", { class: "ic-actions" }, [cancel, save])], mini));
      save.addEventListener("click", function () {
        sheet.close();
        // Persist exactly what is displayed: a category counts as granted
        // only when it and every service row under it are selected.
        var ids = core.optionalCategories().filter(function (id) {
          return boxes[id].checked && core.embedServices().filter(function (s) { return s.category === id; }).every(function (s) { return svcBoxes[s.id].checked; });
        });
        var svcs = core.embedServices().filter(function (s) { return svcBoxes[s.id].checked && ids.indexOf(s.category) < 0; }).map(function (s) { return s.id; });
        var d = core.current();
        var dropping = core.optionalCategories().some(function (id) { return d.granted[id] && ids.indexOf(id) < 0; });
        removeBar();
        settle(core.grant(ids, svcs), dropping);
      });
      // Cancel keeps an existing decision; during the first prompt there is
      // none, and dismissing counts as refusal.
      cancel.addEventListener("click", function () { sheet.close(); if (bar) refuse(); });
      sheet.addEventListener("cancel", function () { if (bar) refuse(); });
      document.body.appendChild(sheet);
    }
    var d2 = core.current();
    var blocked = env.signal();
    core.optionalCategories().forEach(function (id) { boxes[id].checked = d2.granted[id] === true; boxes[id].disabled = blocked; });
    core.embedServices().forEach(function (s) { svcBoxes[s.id].checked = d2.granted[s.category] === true || d2.services.indexOf(s.id) >= 0; svcBoxes[s.id].disabled = blocked; });
    if (typeof sheet.showModal === "function") sheet.showModal(); else sheet.setAttribute("open", "");
  }

  function wireControls() {
    var controls = document.querySelectorAll("[data-consent-open]");
    for (var i = 0; i < controls.length; i++) {
      if (controls[i].hasAttribute("data-consent-wired")) continue;
      controls[i].setAttribute("data-consent-wired", "");
      if (!controls[i].textContent.trim() && T) controls[i].textContent = T.control;
      controls[i].addEventListener("click", openSheet);
    }
  }

  function renderState() {
    if (!core.valid) return;
    if (lostAuthorization()) { settle({ ok: true, persisted: true }, true); return; }
    loadDestinations();
    renderEmbeds();
    wireControls();
  }

  function boot() {
    if (!core.valid) { warn("manifest invalid, gate closed", core.errors); return; }
    // A revocation marker carried by the URL (a refusal that could not be
    // stored on the previous page) closes the gate before any grant is read.
    if (location.hash.indexOf(REVOKE_HASH) >= 0) {
      var r = core.refuse();
      // The marker stays until the refusal is actually stored somewhere.
      if (r.persisted) { try { history.replaceState(null, "", location.pathname + location.search); } catch (_) { /* keep the hash */ } }
    }
    var d = core.boot();
    renderState();
    if (d.prompt && !env.bot()) renderBar();
  }

  root.insprConsent = { open: openSheet, withdraw: refuse, granted: function (id) { return core.authorized(id); }, core: core };
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot); else boot();
})(typeof globalThis !== "undefined" ? globalThis : this);
