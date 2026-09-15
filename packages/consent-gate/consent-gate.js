// consent-gate — identity-free consent primitive for browser-facing surfaces.
//
// One manifest per surface declares categories, services and texts. The gate
// renders nothing when only necessary storage exists, a contextual placeholder
// at each embed when only embeds need consent, and a non-modal bar with
// equivalent accept/reject choices when tracking destinations exist. Nothing
// optional loads before an affirmative, persisted, purpose-specific choice.
//
// The core (`insprConsentCore`) has no DOM dependency and is exercised by
// tests/consent-gate.mjs under plain Node. The renderer and the destination
// adapters below run only in a browser. Doctrine: AGENTS-DOMAIN-DEV
// "Pattern: web surfaces — cookies & consent".
(function (root) {
  "use strict";

  var VERSION = "1";
  var DEFAULT_COOKIE = "consent";
  var DEFAULT_MAX_AGE_DAYS = 180;
  var REVOKE_SUFFIX = "_revoked";
  var FIRED_PREFIX = "consent_fired_";
  var BOT = /bot|crawl|spider|slurp|headless|lighthouse|pagespeed|preview/i;
  var CONSENT_MODE_KEYS = ["ad_storage", "ad_user_data", "ad_personalization", "analytics_storage", "functionality_storage", "personalization_storage"];
  var CATEGORY_ID = /^[a-z][a-z0-9-]{0,31}$/;

  // ---------------------------------------------------------------- core --

  function isObject(v) { return v !== null && typeof v === "object" && !Array.isArray(v); }

  // validateManifest returns { ok, errors }. An invalid manifest makes the
  // gate fail closed: nothing optional ever loads, no prompt is shown.
  function validateManifest(m) {
    var errors = [];
    if (!isObject(m)) return { ok: false, errors: ["manifest must be an object"] };
    if (m.version !== 1) errors.push("version must be 1");
    if (!(Number.isInteger(m.revision) && m.revision >= 1)) errors.push("revision must be a positive integer");
    if (m.cookieName !== undefined && !/^[A-Za-z0-9_-]{1,64}$/.test(String(m.cookieName))) errors.push("cookieName must be a short token");
    if (m.maxAgeDays !== undefined && !(Number.isInteger(m.maxAgeDays) && m.maxAgeDays >= 1 && m.maxAgeDays <= 365)) errors.push("maxAgeDays must be 1..365");
    var categories = Array.isArray(m.categories) ? m.categories : [];
    if (!categories.length) errors.push("categories must be a non-empty array");
    var ids = {};
    var requiredCount = 0;
    categories.forEach(function (c, i) {
      if (!isObject(c) || !CATEGORY_ID.test(String(c.id))) { errors.push("categories[" + i + "].id invalid"); return; }
      if (ids[c.id]) errors.push("duplicate category id " + c.id);
      ids[c.id] = c;
      if (c.required === true) requiredCount++;
    });
    if (requiredCount !== 1) errors.push("exactly one category must be required (the necessary one)");
    var services = Array.isArray(m.services) ? m.services : [];
    var sids = {};
    services.forEach(function (s, i) {
      if (!isObject(s) || !CATEGORY_ID.test(String(s.id))) { errors.push("services[" + i + "].id invalid"); return; }
      if (sids[s.id]) errors.push("duplicate service id " + s.id);
      sids[s.id] = s;
      if (!ids[s.category]) errors.push("service " + s.id + " names unknown category " + s.category);
      else if (ids[s.category].required === true) errors.push("service " + s.id + " sits in the required category; optional services need an optional category");
      if (typeof s.provider !== "string" || !s.provider) errors.push("service " + s.id + " needs a provider name");
      var kinds = 0;
      if (s.destination !== undefined) { kinds++; if (!isObject(s.destination) || s.destination.type !== "gtag" || typeof s.destination.tagId !== "string") errors.push("service " + s.id + " destination must be { type: \"gtag\", tagId }"); else if (!Array.isArray(s.destination.consent) || !s.destination.consent.length || !s.destination.consent.every(function (k) { return CONSENT_MODE_KEYS.indexOf(k) >= 0; })) errors.push("service " + s.id + " destination.consent must list Consent Mode keys"); }
      if (s.embed !== undefined) { kinds++; if (!isObject(s.embed) || typeof s.embed.host !== "string" || !s.embed.host) errors.push("service " + s.id + " embed needs a host"); }
      if (kinds !== 1) errors.push("service " + s.id + " must declare exactly one of destination or embed");
      if (s.storage !== undefined) {
        if (!Array.isArray(s.storage)) errors.push("service " + s.id + " storage must be an array");
        else s.storage.forEach(function (st, j) { if (!isObject(st) || ["cookie", "local", "session"].indexOf(st.kind) < 0 || typeof st.name !== "string" || !st.name) errors.push("service " + s.id + " storage[" + j + "] needs kind cookie|local|session and a name"); });
      }
    });
    var text = isObject(m.text) ? m.text : null;
    if (!text || !Object.keys(text).length) errors.push("text must carry at least one language");
    else Object.keys(text).forEach(function (lang) {
      var t = text[lang];
      ["bar.text", "bar.accept", "bar.reject", "bar.settings", "sheet.title", "sheet.intro", "sheet.save", "sheet.cancel", "embed.loadOnce", "embed.always", "embed.open", "control"].forEach(function (path) {
        var v = path.split(".").reduce(function (acc, k) { return isObject(acc) ? acc[k] : undefined; }, t);
        if (typeof v !== "string" || !v) errors.push("text." + lang + "." + path + " missing");
      });
      var cats = isObject(t.categories) ? t.categories : {};
      categories.forEach(function (c) { if (c && CATEGORY_ID.test(String(c.id)) && (!isObject(cats[c.id]) || typeof cats[c.id].label !== "string")) errors.push("text." + lang + ".categories." + c.id + ".label missing"); });
    });
    return { ok: errors.length === 0, errors: errors };
  }

  function optionalCategories(m) { return m.categories.filter(function (c) { return c.required !== true; }).map(function (c) { return c.id; }); }
  function requiredCategory(m) { return m.categories.filter(function (c) { return c.required === true; })[0].id; }
  function servicesIn(m, categoryId) { return m.services.filter(function (s) { return s.category === categoryId; }); }

  // tierOf: "none" (nothing optional), "contextual" (only embeds), "bar".
  function tierOf(m) {
    var optional = optionalCategories(m).filter(function (id) { return servicesIn(m, id).length > 0; });
    if (!optional.length) return "none";
    var onlyEmbeds = optional.every(function (id) { return servicesIn(m, id).every(function (s) { return s.embed !== undefined; }); });
    return onlyEmbeds ? "contextual" : "bar";
  }

  // Stored value: "v1;r=<revision>;g=<granted ids, comma>;t=<unix seconds>".
  // No identifier of any kind.
  function serialize(granted, revision, at) {
    return "v1;r=" + revision + ";g=" + granted.slice().sort().join(",") + ";t=" + Math.floor(at);
  }
  function parse(raw) {
    if (typeof raw !== "string" || !raw) return null;
    var parts = raw.split(";");
    if (parts[0] !== "v1") return null;
    var out = { revision: 0, granted: [], at: 0 };
    for (var i = 1; i < parts.length; i++) {
      var kv = parts[i].split("=");
      if (kv[0] === "r") out.revision = parseInt(kv[1], 10) || 0;
      else if (kv[0] === "g") out.granted = kv[1] ? kv[1].split(",").filter(function (x) { return CATEGORY_ID.test(x); }) : [];
      else if (kv[0] === "t") out.at = parseInt(kv[1], 10) || 0;
    }
    return out;
  }

  // decide: what the page may do right now. `granted` covers optional
  // categories only; the required category is always on.
  function decide(input) {
    var m = input.manifest;
    var optional = optionalCategories(m);
    var none = {};
    optional.forEach(function (id) { none[id] = false; });
    var tier = tierOf(m);
    if (input.invalid) return { tier: "none", prompt: false, granted: none, persist: "none" };
    if (input.bot) return { tier: tier, prompt: false, granted: none, persist: "none" };
    if (input.revoked) return { tier: tier, prompt: false, granted: none, persist: "none" };
    if (input.signal) return { tier: tier, prompt: false, granted: none, persist: "refuse" };
    var stored = input.stored || null;
    var maxAge = (m.maxAgeDays || DEFAULT_MAX_AGE_DAYS) * 86400;
    if (stored && stored.revision === m.revision && input.now - stored.at < maxAge) {
      var granted = {};
      optional.forEach(function (id) { granted[id] = stored.granted.indexOf(id) >= 0; });
      return { tier: tier, prompt: false, granted: granted, persist: "none" };
    }
    return { tier: tier, prompt: tier === "bar", granted: none, persist: "none" };
  }

  // consentModeSignals: Google Consent Mode v2 defaults (all denied) and the
  // update derived from granted categories. Only keys a service declares can
  // ever be granted, so an undisclosed purpose stays denied.
  function consentModeSignals(m, granted) {
    var defaults = {};
    CONSENT_MODE_KEYS.forEach(function (k) { defaults[k] = "denied"; });
    var update = {};
    CONSENT_MODE_KEYS.forEach(function (k) { update[k] = "denied"; });
    m.services.forEach(function (s) {
      if (!s.destination || !granted[s.category]) return;
      s.destination.consent.forEach(function (k) { update[k] = "granted"; });
    });
    return { defaults: defaults, update: update };
  }

  // createCore binds the policy to an environment (cookie jar, storages,
  // signals, clock). Every accessor is exception-safe; a failing store reads
  // as "no decision" and never authorises anything.
  function createCore(manifest, env) {
    var validation = validateManifest(manifest);
    var invalid = !validation.ok;
    var cookieName = (manifest && manifest.cookieName) || DEFAULT_COOKIE;
    var revokeKey = cookieName + REVOKE_SUFFIX;
    var maxAgeSec = ((manifest && manifest.maxAgeDays) || DEFAULT_MAX_AGE_DAYS) * 86400;
    var revoked = false;
    var loadedOnce = {};
    var listeners = [];

    function safe(fn, fallback) { try { return fn(); } catch (_) { return fallback; } }
    function now() { return safe(function () { return env.now(); }, 0); }
    function stored() { return safe(function () { return parse(env.readCookie(cookieName)); }, null); }
    function sessionRevoked() { return safe(function () { return env.readSession(revokeKey) === "1"; }, false); }
    function signal() { return safe(function () { return env.signal() === true; }, false); }
    function bot() { return safe(function () { return env.bot() === true; }, false); }

    function persist(grantedIds) {
      if (invalid) return false;
      var value = serialize(grantedIds, manifest.revision, now());
      var written = safe(function () { return env.writeCookie(cookieName, value, maxAgeSec) !== false; }, false);
      if (!written) return false;
      var back = stored();
      return !!back && serialize(back.granted, back.revision, back.at) === value;
    }

    function current() {
      if (invalid) return decide({ manifest: { categories: [], services: [] }, invalid: true });
      return decide({ manifest: manifest, stored: stored(), now: now(), signal: signal(), bot: bot(), revoked: revoked || sessionRevoked() });
    }

    function emit() { listeners.forEach(function (fn) { safe(function () { fn(current()); }, null); }); }

    // cleanup removes the storage every service in `categories` declares.
    function cleanup(categories) {
      if (invalid) return;
      manifest.services.forEach(function (s) {
        if (categories.indexOf(s.category) < 0 || !Array.isArray(s.storage)) return;
        s.storage.forEach(function (st) {
          safe(function () {
            if (st.kind === "cookie") env.clearCookie(st.name);
            else if (st.kind === "local") env.removeLocal(st.name);
            else if (st.kind === "session") env.removeSession(st.name);
          }, null);
        });
      });
    }

    function refuseAll() {
      revoked = true;
      loadedOnce = {};
      cleanup(optionalCategories(manifest));
      var persisted = persist([]);
      if (!persisted) persisted = safe(function () { env.writeSession(revokeKey, "1"); return env.readSession(revokeKey) === "1"; }, false);
      else safe(function () { env.removeSession(revokeKey); }, null);
      emit();
      return persisted;
    }

    return {
      valid: !invalid,
      errors: validation.errors,
      manifest: manifest,
      tier: invalid ? "none" : tierOf(manifest),
      cookieName: cookieName,
      revokeKey: revokeKey,
      boot: function () {
        var d = current();
        if (d.persist === "refuse") this.refuse();
        return current();
      },
      current: current,
      // grant persists exactly the given optional categories (others refused).
      grant: function (ids) {
        if (invalid || signal() || bot()) return { ok: false, decision: current() };
        var optional = optionalCategories(manifest);
        var wanted = ids.filter(function (id) { return optional.indexOf(id) >= 0; });
        var before = current().granted;
        var withdrawn = optional.filter(function (id) { return before[id] && wanted.indexOf(id) < 0; });
        cleanup(withdrawn);
        if (!wanted.length) return { ok: true, decision: (refuseAll(), current()) };
        if (!persist(wanted)) { refuseAll(); return { ok: false, decision: current() }; }
        revoked = false;
        safe(function () { env.removeSession(revokeKey); }, null);
        emit();
        return { ok: true, decision: current() };
      },
      refuse: function () { return refuseAll(); },
      withdraw: function () { return refuseAll(); },
      authorized: function (categoryId) {
        if (invalid) return false;
        if (categoryId === requiredCategory(manifest)) return true;
        return current().granted[categoryId] === true;
      },
      // loadOnce authorises one embed instance for this page view only.
      loadOnce: function (serviceId) {
        if (invalid || signal() || bot()) return false;
        var s = manifest.services.filter(function (x) { return x.id === serviceId && x.embed; })[0];
        if (!s) return false;
        loadedOnce[serviceId] = true;
        return true;
      },
      authorizedService: function (serviceId) {
        if (invalid) return false;
        var s = manifest.services.filter(function (x) { return x.id === serviceId; })[0];
        if (!s) return false;
        if (loadedOnce[serviceId] === true && !signal() && !bot()) return true;
        return this.authorized(s.category);
      },
      signals: function () { return invalid ? consentModeSignals({ services: [] }, {}) : consentModeSignals(manifest, current().granted); },
      onChange: function (fn) { listeners.push(fn); },
      optionalCategories: function () { return invalid ? [] : optionalCategories(manifest); },
      requiredCategory: function () { return invalid ? null : requiredCategory(manifest); }
    };
  }

  root.insprConsentCore = { VERSION: VERSION, validateManifest: validateManifest, tierOf: tierOf, parse: parse, serialize: serialize, decide: decide, consentModeSignals: consentModeSignals, createCore: createCore, BOT: BOT };

  if (typeof document === "undefined") return;

  // ------------------------------------------------------------ browser --

  var script = document.currentScript;
  var ds = script ? script.dataset : {};

  function readManifest() {
    if (root.insprConsentManifest) return root.insprConsentManifest;
    var sel = ds.consentManifest || "#consent-manifest";
    var el = document.querySelector(sel);
    if (!el) return null;
    try { return JSON.parse(el.textContent); } catch (_) { return null; }
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
    clearCookie: function (pattern) {
      var names = (document.cookie ? document.cookie.split("; ") : []).map(function (c) { return c.split("=")[0]; });
      var re = new RegExp("^" + pattern.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*") + "$");
      var labels = location.hostname.split(".");
      var domains = [""];
      for (var i = 0; i < labels.length - 1; i++) domains.push(labels.slice(i).join("."));
      names.forEach(function (n) {
        if (!re.test(n)) return;
        domains.forEach(function (d) { document.cookie = n + "=; Max-Age=0; Path=/" + (d ? "; Domain=" + d : ""); });
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
  var loadedAnything = false;

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
      else if (k === "html") node.innerHTML = attrs[k];
      else node.setAttribute(k, attrs[k]);
    });
    (children || []).forEach(function (c) { node.appendChild(c); });
    return node;
  }

  function catText(id) { return (T.categories && T.categories[id]) || { label: id, description: "" }; }
  function svcText(id) { return (T.services && T.services[id]) || {}; }

  // --- destinations (Google tag with Consent Mode v2 in basic mode) ---
  function gtag() { root.dataLayer.push(arguments); }

  function loadDestinations() {
    if (!core.valid) return;
    var d = core.current();
    manifest.services.forEach(function (s) {
      if (!s.destination || !d.granted[s.category] || loadedDestinations[s.id]) return;
      if (!core.authorized(s.category)) return;
      loadedDestinations[s.id] = true;
      loadedAnything = true;
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
  // data-consent-fire, and once per session for that service.
  function fireConversion(s) {
    var fire = (ds.consentFire || "").split(/[ ,]+/).filter(Boolean);
    if (!s.destination.conversion || fire.indexOf(s.id) < 0) return;
    var key = FIRED_PREFIX + s.id;
    try {
      if (sessionStorage.getItem(key) === "1") return;
      sessionStorage.setItem(key, "1");
    } catch (_) { /* fire once per page load */ }
    gtag("event", "conversion", { send_to: s.destination.conversion.sendTo, value: s.destination.conversion.value || 1.0, currency: s.destination.conversion.currency || "EUR" });
  }

  function denyDestinations() {
    if (!loadedAnything) return;
    try { gtag("consent", "update", core.signals().defaults); } catch (_) { /* best effort */ }
  }

  // --- embeds ---
  function embedElements(s) { return Array.prototype.slice.call(document.querySelectorAll('[data-consent-embed="' + s.id + '"]')); }

  function activateEmbed(node) {
    if (node.getAttribute("data-consent-active") === "1") return;
    node.setAttribute("data-consent-active", "1");
    var ph = node.previousElementSibling;
    if (ph && ph.classList.contains("ic-embed")) ph.parentNode.removeChild(ph);
    var src = node.getAttribute("data-src");
    if (src) node.setAttribute("src", src);
    node.hidden = false;
  }

  function placeholderFor(s, node) {
    var st = svcText(s.id);
    var once = el("button", { type: "button", class: "ic-btn", text: T.embed.loadOnce });
    var always = el("button", { type: "button", class: "ic-btn", text: T.embed.always });
    var open = el("a", { class: "ic-link", href: node.getAttribute("data-src") || ("https://" + s.embed.host), rel: "noopener noreferrer", target: "_blank", text: T.embed.open + " " + s.embed.host });
    once.addEventListener("click", function () { if (core.loadOnce(s.id)) activateEmbed(node); });
    always.addEventListener("click", function () {
      var d = core.current();
      var ids = core.optionalCategories().filter(function (id) { return d.granted[id]; });
      if (ids.indexOf(s.category) < 0) ids.push(s.category);
      if (core.grant(ids).ok) renderState();
    });
    return el("div", { class: "ic-embed", role: "group", "aria-label": st.label || s.provider }, [
      el("p", { class: "ic-embed-title", text: st.label || s.provider }),
      el("p", { class: "ic-embed-text", text: st.description || "" }),
      el("div", { class: "ic-actions" }, [once, always, open])
    ]);
  }

  function renderEmbeds() {
    manifest.services.forEach(function (s) {
      if (!s.embed) return;
      embedElements(s).forEach(function (node) {
        if (core.authorizedService(s.id)) { activateEmbed(node); return; }
        node.hidden = true;
        if (node.getAttribute("data-src") === null && node.getAttribute("src")) { node.setAttribute("data-src", node.getAttribute("src")); node.removeAttribute("src"); }
        var prev = node.previousElementSibling;
        if (!(prev && prev.classList.contains("ic-embed"))) node.parentNode.insertBefore(placeholderFor(s, node), node);
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

  function acceptAll() {
    removeBar();
    var r = core.grant(core.optionalCategories());
    if (!r.ok) { refuse(); return; }
    renderState();
  }
  function refuse() {
    removeBar();
    denyDestinations();
    var persisted = core.refuse();
    renderState();
    if (loadedAnything && persisted) location.reload();
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
    if (T.bar.link && manifest.privacyUrl) { text.appendChild(document.createTextNode(" ")); text.appendChild(el("a", { href: manifest.privacyUrl, text: T.bar.link })); }
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
      rows.push(el("div", { class: "ic-row" }, [reqBox, el("label", { for: "ic-cat-" + req, html: "<strong>" + escapeHtml(catText(req).label) + "</strong> " + escapeHtml(catText(req).description || "") })]));
      core.optionalCategories().forEach(function (id) {
        var box = el("input", { type: "checkbox", id: "ic-cat-" + id });
        boxes[id] = box;
        rows.push(el("div", { class: "ic-row" }, [box, el("label", { for: "ic-cat-" + id, html: "<strong>" + escapeHtml(catText(id).label) + "</strong> " + escapeHtml(catText(id).description || "") })]));
      });
      var save = el("button", { type: "button", class: "ic-btn", text: T.sheet.save });
      var cancel = el("button", { type: "button", class: "ic-btn", text: T.sheet.cancel });
      var mini = T.sheet.link && manifest.privacyUrl ? [el("p", { class: "ic-mini" }, [el("a", { href: manifest.privacyUrl, text: T.sheet.link })])] : [];
      sheet = el("dialog", { class: "ic-sheet", "aria-labelledby": "ic-sheet-title" }, [el("h2", { id: "ic-sheet-title", text: T.sheet.title }), el("p", { text: T.sheet.intro })].concat(rows, [el("div", { class: "ic-actions" }, [cancel, save])], mini));
      save.addEventListener("click", function () {
        sheet.close();
        var ids = core.optionalCategories().filter(function (id) { return boxes[id].checked; });
        var d = core.current();
        var dropping = core.optionalCategories().some(function (id) { return d.granted[id] && ids.indexOf(id) < 0; });
        removeBar();
        if (dropping) denyDestinations();
        var r = core.grant(ids);
        renderState();
        if (dropping && loadedAnything && r.ok) location.reload();
        if (!r.ok) refuse();
      });
      // Cancel keeps an existing decision; during the first prompt there is
      // none, and dismissing counts as refusal.
      cancel.addEventListener("click", function () { sheet.close(); if (bar) refuse(); });
      sheet.addEventListener("cancel", function () { if (bar) refuse(); });
      document.body.appendChild(sheet);
    }
    var d = core.current();
    var blocked = env.signal();
    core.optionalCategories().forEach(function (id) { boxes[id].checked = d.granted[id] === true; boxes[id].disabled = blocked; });
    if (typeof sheet.showModal === "function") sheet.showModal(); else sheet.setAttribute("open", "");
  }

  function escapeHtml(s) { return String(s).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); }

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
    if (!core.valid) {
      try { console.warn("consent-gate: manifest invalid, gate closed", core.errors); } catch (_) { /* no console */ }
      return;
    }
    var d = core.boot();
    renderState();
    if (d.prompt && !env.bot()) renderBar();
  }

  root.insprConsent = { open: openSheet, withdraw: refuse, granted: function (id) { return core.authorized(id); }, core: core };
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot); else boot();
})(typeof globalThis !== "undefined" ? globalThis : this);
