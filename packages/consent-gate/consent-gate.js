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
  var MIN_REFUSAL_DAYS = 183; // at least six calendar months
  var REVOKE_SUFFIX = "_revoked";
  var FIRED_PREFIX = "consent_fired_";
  var BOT = /bot|crawl|spider|slurp|headless|lighthouse|pagespeed|preview/i;
  var CONSENT_MODE_KEYS = ["ad_storage", "ad_user_data", "ad_personalization", "analytics_storage", "functionality_storage", "personalization_storage", "security_storage"];
  var GTAG_HOSTS = ["www.googletagmanager.com", "googleads.g.doubleclick.net", "www.google.com", "www.google-analytics.com", "pagead2.googlesyndication.com"];
  var ID = /^[a-z][a-z0-9-]{0,31}$/;
  var TAG_ID = /^[A-Z]{1,4}-[A-Za-z0-9_-]{1,40}$/;
  var HOSTNAME = /^(?=.{1,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/;
  var COOKIE_NAME = /^[A-Za-z0-9_.-]{1,64}\*?$/;
  var INT = /^[0-9]{1,12}$/;

  // ---------------------------------------------------------------- core --

  function isObject(v) { return v !== null && typeof v === "object" && !Array.isArray(v); }
  function isNonEmptyString(v, max) { return typeof v === "string" && v.length > 0 && v.length <= (max || 200); }

  // safeUrl: absolute https URL or a same-origin path. Anything else is inert.
  function safeUrl(value) {
    if (!isNonEmptyString(value, 2048)) return null;
    if (/^\/(?!\/)/.test(value)) return value;
    var m = /^https:\/\/([^\/?#]+)([\/?#].*)?$/i.exec(value);
    if (!m) return null;
    var host = m[1].toLowerCase().replace(/:\d+$/, "");
    return HOSTNAME.test(host) ? value : null;
  }
  function urlHost(value) {
    var m = /^https?:\/\/([^\/?#]+)/i.exec(String(value || ""));
    return m ? m[1].toLowerCase().replace(/:\d+$/, "") : null;
  }
  function hostMatches(host, declared) { return host === declared || (host && host.slice(-(declared.length + 1)) === "." + declared); }

  // validateManifest returns { ok, errors }. An invalid manifest closes the
  // gate: nothing optional ever loads, nothing is rendered.
  function validateManifest(m) {
    var errors = [];
    if (!isObject(m)) return { ok: false, errors: ["manifest must be an object"] };
    if (m.version !== 1) errors.push("version must be 1");
    if (!(Number.isInteger(m.revision) && m.revision >= 1 && m.revision < 1e9)) errors.push("revision must be a positive integer");
    if (!(Number.isInteger(m.textVersion) && m.textVersion >= 1 && m.textVersion < 1e9)) errors.push("textVersion must be a positive integer");
    if (!isNonEmptyString(m.controller, 200)) errors.push("controller must name the controller");
    if (!(isNonEmptyString(m.scope, 253) && HOSTNAME.test(m.scope.toLowerCase()) || m.scope === "localhost")) errors.push("scope must be the surface's host name");
    if (m.cookieName !== undefined && !/^[A-Za-z0-9_-]{1,64}$/.test(String(m.cookieName))) errors.push("cookieName must be a short token");
    if (m.permissionDays !== undefined && !(Number.isInteger(m.permissionDays) && m.permissionDays >= 1 && m.permissionDays <= 365)) errors.push("permissionDays must be 1..365");
    if (m.refusalDays !== undefined && !(Number.isInteger(m.refusalDays) && m.refusalDays >= MIN_REFUSAL_DAYS && m.refusalDays <= 730)) errors.push("refusalDays must be at least " + MIN_REFUSAL_DAYS);
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
            if (!isObject(c) || !isNonEmptyString(c.sendTo, 120) || typeof d.tagId !== "string" || c.sendTo.indexOf(d.tagId + "/") !== 0 || !/^[A-Za-z0-9_-]+$/.test(c.sendTo.slice(d.tagId.length + 1))) errors.push("service " + s.id + " conversion.sendTo must be <tagId>/<label> of this destination");
            if (c.value !== undefined && !(typeof c.value === "number" && isFinite(c.value) && c.value >= 0)) errors.push("service " + s.id + " conversion.value must be a non-negative number");
            if (c.currency !== undefined && !/^[A-Z]{3}$/.test(String(c.currency))) errors.push("service " + s.id + " conversion.currency must be an ISO code");
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
            if (st.domain !== undefined && !(typeof st.domain === "string" && (HOSTNAME.test(st.domain.toLowerCase()) || st.domain === "localhost"))) errors.push(label + " domain invalid");
            if (st.domain !== undefined && typeof m.scope === "string" && !hostMatches(m.scope.toLowerCase(), String(st.domain).toLowerCase())) errors.push(label + " domain must be the scope host or one of its parents");
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
  function servicesIn(m, categoryId) { return m.services.filter(function (s) { return s.category === categoryId; }); }
  function serviceById(m, id) { return m.services.filter(function (s) { return s.id === id; })[0] || null; }

  // tierOf: "none" (nothing optional), "contextual" (only embeds), "bar".
  function tierOf(m) {
    var optional = optionalCategories(m).filter(function (id) { return servicesIn(m, id).length > 0; });
    if (!optional.length) return "none";
    var onlyEmbeds = optional.every(function (id) { return servicesIn(m, id).every(function (s) { return s.embed !== undefined; }); });
    return onlyEmbeds ? "contextual" : "bar";
  }

  // Stored decision: "v1;r=<revision>;v=<textVersion>;g=<categories>;s=<services>;t=<unix>".
  // g = granted optional categories, s = individually remembered services
  // (an embed's "always allow"). No identifier of any kind. Parsing is
  // strict: every field exactly once, valid tokens only, safe integers.
  function serialize(rec) {
    return "v1;r=" + rec.revision + ";v=" + rec.textVersion + ";g=" + rec.granted.slice().sort().join(",") + ";s=" + (rec.services || []).slice().sort().join(",") + ";t=" + Math.floor(rec.at);
  }
  function parse(raw) {
    if (typeof raw !== "string" || !raw || raw.length > 1024) return null;
    var parts = raw.split(";");
    if (parts[0] !== "v1" || parts.length !== 6) return null;
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
      else if (k === "g" || k === "s") {
        if (v === "") { out[k] = []; continue; }
        var list = v.split(",");
        if (!list.every(function (x) { return ID.test(x); })) return null;
        out[k] = list;
      } else return null;
    }
    if (!(seen.r && seen.v && seen.g && seen.s && seen.t)) return null;
    return { revision: out.r, textVersion: out.v, granted: out.g, services: out.s, at: out.t };
  }

  function permissionSeconds(m) { return ((m && m.permissionDays) || DEFAULT_PERMISSION_DAYS) * 86400; }
  function refusalSeconds(m) { return Math.max((m && m.refusalDays) || MIN_REFUSAL_DAYS, MIN_REFUSAL_DAYS) * 86400; }

  function emptyGrant(m) { var g = {}; optionalCategories(m).forEach(function (id) { g[id] = false; }); return g; }

  // decide: what the page may do right now. `granted` covers optional
  // categories, `services` the individually remembered services.
  function decide(input) {
    var m = input.manifest;
    var tier = input.invalid ? "none" : tierOf(m);
    var none = input.invalid ? {} : emptyGrant(m);
    var closed = { tier: tier, prompt: false, granted: none, services: [], persist: "none" };
    if (input.invalid || input.blocked || input.bot || input.revoked) return closed;
    if (input.signal) { closed.persist = "refuse"; return closed; }
    var now = input.now;
    if (!(typeof now === "number" && isFinite(now) && now > 0)) return closed;
    var stored = input.stored || null;
    if (stored && stored.revision === m.revision && stored.at <= now) {
      var age = now - stored.at;
      var anyGrant = stored.granted.length > 0 || stored.services.length > 0;
      if (anyGrant && age < permissionSeconds(m)) {
        var granted = {};
        optionalCategories(m).forEach(function (id) { granted[id] = stored.granted.indexOf(id) >= 0; });
        var services = stored.services.filter(function (id) { var s = serviceById(m, id); return !!s && !granted[s.category]; });
        return { tier: tier, prompt: false, granted: granted, services: services, persist: "none" };
      }
      if (!anyGrant && age < refusalSeconds(m)) return { tier: tier, prompt: false, granted: none, services: [], persist: "none" };
    }
    return { tier: tier, prompt: tier === "bar", granted: none, services: [], persist: "none" };
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

  // guardServedHtml: the reusable pre-consent guard. Given served HTML and the
  // requests captured before any choice, it reports every active resource
  // (script/iframe/img/link/video/audio/source/object/embed with a live URL
  // attribute) and every request that touches a declared host. Inert
  // references — the manifest JSON, data-src, plain anchors — do not count.
  function guardServedHtml(input) {
    var m = input.manifest;
    var hosts = declaredHosts(m);
    var violations = [];
    var html = String(input.html || "");
    var tag = /<(script|iframe|img|link|video|audio|source|object|embed|track)\b([^>]*)>/gi;
    var match;
    while ((match = tag.exec(html)) !== null) {
      var attrs = match[2];
      var attr = /(?:^|\s)(src|href|data|srcset|poster)\s*=\s*["']?([^"'\s>]+)/gi;
      var a;
      while ((a = attr.exec(attrs)) !== null) {
        var host = urlHost(a[2]);
        if (host && hosts.some(function (h) { return hostMatches(host, h); })) violations.push({ kind: "markup", element: match[1].toLowerCase(), attribute: a[1].toLowerCase(), url: a[2] });
      }
    }
    (input.requests || []).forEach(function (u) {
      var host = urlHost(u);
      if (host && hosts.some(function (h) { return hostMatches(host, h); })) violations.push({ kind: "request", url: String(u) });
    });
    return { ok: violations.length === 0, violations: violations, hosts: hosts };
  }

  // createCore binds the policy to an environment (cookie jar, storages,
  // signals, clock). Every accessor is exception-safe. A failing accessor
  // never authorises anything: a failing cookie or clock reads as "no
  // decision", a failing revocation read or signal read as "blocked".
  function createCore(manifest, env) {
    var validation = validateManifest(manifest);
    var invalid = !validation.ok;
    var m = invalid ? { categories: [], services: [] } : manifest;
    var cookieName = (!invalid && manifest.cookieName) || DEFAULT_COOKIE;
    var revokeKey = cookieName + REVOKE_SUFFIX;
    var revoked = false;
    var onceInstances = [];
    var listeners = [];
    var teardowns = {};

    function attempt(fn, fallback) { try { return fn(); } catch (_) { return fallback; } }
    var BLOCKED = { blocked: true };
    function now() { return attempt(function () { return env.now(); }, NaN); }
    function stored() { return attempt(function () { return parse(env.readCookie(cookieName)); }, null); }
    function sessionRevoked() { return attempt(function () { return env.readSession(revokeKey) === "1"; }, BLOCKED); }
    function signal() { return attempt(function () { return env.signal() === true; }, BLOCKED); }
    function bot() { return attempt(function () { return env.bot() === true; }, BLOCKED); }

    function record(granted, services) {
      return { revision: manifest.revision, textVersion: manifest.textVersion, granted: granted, services: services, at: now() };
    }

    function persist(granted, services) {
      if (invalid) return false;
      var rec = record(granted, services);
      if (!(isFinite(rec.at) && rec.at > 0)) return false;
      var value = serialize(rec);
      var maxAge = granted.length || services.length ? permissionSeconds(m) : refusalSeconds(m);
      var written = attempt(function () { return env.writeCookie(cookieName, value, maxAge) !== false; }, false);
      if (!written) return false;
      var back = stored();
      return !!back && serialize(back) === value;
    }

    function current() {
      if (invalid) return decide({ manifest: m, invalid: true });
      var rev = sessionRevoked();
      var sig = signal();
      var b = bot();
      if (rev === BLOCKED || sig === BLOCKED || b === BLOCKED) return decide({ manifest: m, blocked: true });
      return decide({ manifest: m, stored: stored(), now: now(), signal: sig, bot: b, revoked: revoked || rev });
    }

    function emit() { listeners.forEach(function (fn) { attempt(function () { fn(current()); }, null); }); }

    // cleanup removes exactly the storage the given services declare, at the
    // declared path and domain, plus the adapter's own session markers.
    function cleanupServices(services) {
      services.forEach(function (s) {
        (Array.isArray(s.storage) ? s.storage : []).forEach(function (st) {
          attempt(function () {
            if (st.kind === "cookie") env.clearCookie({ name: st.name, path: st.path || "/", domain: st.domain || null });
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
      var persisted = persist([], []);
      if (!persisted) persisted = attempt(function () { env.writeSession(revokeKey, "1"); return env.readSession(revokeKey) === "1"; }, false);
      else attempt(function () { env.removeSession(revokeKey); }, null);
      emit();
      return persisted;
    }

    function applyGrant(granted, services) {
      var before = current();
      var dropCats = optionalCategories(m).filter(function (id) { return before.granted[id] && granted.indexOf(id) < 0; });
      var dropSvcs = before.services.filter(function (id) { return services.indexOf(id) < 0 && !(serviceById(m, id) && granted.indexOf(serviceById(m, id).category) >= 0); });
      cleanupServices(servicesOfCategories(dropCats).concat(dropSvcs.map(function (id) { return serviceById(m, id); }).filter(Boolean)));
      if (!granted.length && !services.length) { var p = refuseAll(); return { ok: p, decision: current() }; }
      if (!persist(granted, services)) { refuseAll(); return { ok: false, decision: current() }; }
      revoked = false;
      attempt(function () { env.removeSession(revokeKey); }, null);
      emit();
      return { ok: true, decision: current() };
    }

    function canGrant() { return !invalid && signal() === false && bot() === false && isFinite(now()); }

    var core = {
      valid: !invalid,
      errors: validation.errors,
      manifest: manifest,
      tier: invalid ? "none" : tierOf(m),
      cookieName: cookieName,
      revokeKey: revokeKey,
      boot: function () {
        var d = current();
        if (d.persist === "refuse") refuseAll();
        return current();
      },
      current: current,
      // grant persists exactly the given optional categories; individually
      // remembered services outside those categories are kept.
      grant: function (ids) {
        if (!canGrant()) return { ok: false, decision: current() };
        var optional = optionalCategories(m);
        var wanted = (ids || []).filter(function (id) { return optional.indexOf(id) >= 0; });
        var keepServices = current().services.filter(function (id) { var s = serviceById(m, id); return s && wanted.indexOf(s.category) < 0; });
        return applyGrant(wanted, keepServices);
      },
      // grantService remembers one embed service (its declared purposes) for
      // the permission lifetime without granting its whole category.
      grantService: function (serviceId) {
        if (!canGrant()) return { ok: false, decision: current() };
        var s = serviceById(m, serviceId);
        if (!s || !s.embed) return { ok: false, decision: current() };
        var d = current();
        var granted = optionalCategories(m).filter(function (id) { return d.granted[id]; });
        var services = d.services.slice();
        if (services.indexOf(serviceId) < 0) services.push(serviceId);
        return applyGrant(granted, services);
      },
      refuse: function () { return refuseAll(); },
      withdraw: function () { return refuseAll(); },
      authorized: function (categoryId) {
        if (invalid) return false;
        if (categoryId === requiredCategory(m)) return true;
        return current().granted[categoryId] === true;
      },
      // loadOnce authorises one embed instance for this page view only.
      loadOnce: function (serviceId, instance) {
        if (!canGrant() || instance === undefined || instance === null) return false;
        var s = serviceById(m, serviceId);
        if (!s || !s.embed) return false;
        onceInstances.push({ service: serviceId, instance: instance });
        return true;
      },
      authorizedInstance: function (serviceId, instance) {
        if (invalid || signal() !== false || bot() !== false) return false;
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
      service: function (id) { return invalid ? null : serviceById(m, id); }
    };
    return core;
  }

  root.insprConsentCore = { VERSION: VERSION, validateManifest: validateManifest, tierOf: tierOf, parse: parse, serialize: serialize, decide: decide, consentModeSignals: consentModeSignals, declaredHosts: declaredHosts, guardServedHtml: guardServedHtml, createCore: createCore, safeUrl: safeUrl, BOT: BOT, MIN_REFUSAL_DAYS: MIN_REFUSAL_DAYS };

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
    // clearCookie deletes matching names at exactly the declared path and
    // domain (host-only when no domain is declared).
    clearCookie: function (st) {
      var names = (document.cookie ? document.cookie.split("; ") : []).map(function (c) { return c.split("=")[0]; });
      var re = new RegExp("^" + st.name.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*$/, ".*") + "$");
      names.forEach(function (n) {
        if (!re.test(n)) return;
        document.cookie = n + "=; Max-Age=0; Path=" + st.path + (st.domain ? "; Domain=" + st.domain : "");
      });
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

  // deactivate tears the browsing context down: the src goes, the document
  // is replaced by about:blank, the placeholder returns.
  function deactivate(s, node) {
    if (node.getAttribute("data-consent-active") === "1") {
      node.removeAttribute("data-consent-active");
      try { if (node.contentWindow) node.contentWindow.location.replace("about:blank"); } catch (_) { /* cross-origin: src removal suffices */ }
      node.removeAttribute("src");
      node.removeAttribute("srcdoc");
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
    once.addEventListener("click", function () { if (core.loadOnce(s.id, node)) activate(s, node); });
    always.addEventListener("click", function () { if (core.grantService(s.id).ok) renderState(); });
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
        // Served markup must not carry a live src: deferred script cannot
        // undo the request such an attribute already started.
        if (node.getAttribute("src") && node.getAttribute("data-consent-active") !== "1") { warn("integration error: embed " + s.id + " served with a live src; remove it from the markup"); node.removeAttribute("src"); node.removeAttribute("srcdoc"); }
        if (core.authorizedInstance(s.id, node)) activate(s, node); else deactivate(s, node);
      });
    });
  }

  // --- bar & sheet ---
  function removeBar() {
    if (bar && bar.parentNode) bar.parentNode.removeChild(bar);
    bar = null;
    document.removeEventListener("keydown", onEscape);
  }
  function onEscape(e) { if (e.key === "Escape" && bar) refuse(); }

  // settle applies a decision change: destinations that lost authorisation
  // are denied and, once the refusal is persisted, the page reloads (a
  // loaded tag has no reliable teardown); embeds are torn down in place.
  function settle(result, dropping) {
    renderState();
    if (dropping) denyDestinations();
    if (dropping && anyDestinationLoaded()) {
      if (result.ok) location.reload();
      else warn("refusal could not be persisted; loaded destinations were denied but the page keeps running");
    }
  }

  function acceptAll() {
    removeBar();
    var r = core.grant(core.optionalCategories());
    if (!r.ok) { settle(r, true); return; }
    settle(r, false);
  }
  function refuse() {
    removeBar();
    var persisted = core.refuse();
    settle({ ok: persisted }, true);
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
    if (!core.valid) return;
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
      });
      var save = el("button", { type: "button", class: "ic-btn", text: T.sheet.save });
      var cancel = el("button", { type: "button", class: "ic-btn", text: T.sheet.cancel });
      var privacy = safeUrl(manifest.privacyUrl);
      var mini = T.sheet.link && privacy ? [el("p", { class: "ic-mini" }, [el("a", { href: privacy, text: T.sheet.link })])] : [];
      sheet = el("dialog", { class: "ic-sheet", "aria-labelledby": "ic-sheet-title" }, [el("h2", { id: "ic-sheet-title", text: T.sheet.title }), el("p", { text: T.sheet.intro })].concat(rows, [el("div", { class: "ic-actions" }, [cancel, save])], mini));
      save.addEventListener("click", function () {
        sheet.close();
        var ids = core.optionalCategories().filter(function (id) { return boxes[id].checked; });
        var d = core.current();
        var dropping = core.optionalCategories().some(function (id) { return d.granted[id] && ids.indexOf(id) < 0; });
        removeBar();
        var r = core.grant(ids);
        settle(r, dropping || !r.ok);
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
    loadDestinations();
    renderEmbeds();
    wireControls();
  }

  function boot() {
    if (!core.valid) { warn("manifest invalid, gate closed", core.errors); return; }
    var d = core.boot();
    renderState();
    if (d.prompt && !env.bot()) renderBar();
  }

  root.insprConsent = { open: openSheet, withdraw: refuse, granted: function (id) { return core.authorized(id); }, core: core };
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot); else boot();
})(typeof globalThis !== "undefined" ? globalThis : this);
