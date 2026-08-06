// Wasiati landing — billing toggle + LIVE pricing from the catalog.
// CSP-safe (script-src 'self'; connect-src allows the API — see _headers).
//
// WHY THIS FETCHES INSTEAD OF HARD-CODING:
// These cards used to carry hard-coded prices, and they drifted badly from what checkout
// actually charges (the page said $499 one-time; the catalog sells that plan for $99).
// `GET /pricing` is the only source of truth — it is public (no auth) and prices the
// caller's own region automatically: an explicit ?region= for anonymous visitors, else
// Cloudflare's CF-IPCountry header. So a Saudi visitor gets SAR and a Canadian gets CAD
// without this file knowing anything about regions.
//
// RULES ENFORCED HERE — all driven by the payload, never by copy in the HTML:
//  · A price is NEVER hard-coded. If the fetch fails we show no price at all and let the
//    CTA carry the visitor to the app. A missing price is recoverable; a WRONG price is a
//    customer charged something other than what they agreed to.
//  · A (tier, interval) the backend marks `purchasable: false`, or does not sell in this
//    region, is never offered as buyable. Ultimate has no one-time row and is refused
//    server-side, so the one-time cycle explains itself rather than showing a price.
//  · A tier absent from the region is hidden outright (Ultimate does not exist in KSA/QA —
//    burial is state-provided there, so there is nothing to pre-plan).
//  · The "Most popular" badge and the yearly saving are computed from the data.
//
// Prices are formatted in the page's own language (see `money`): Arabic digits on /ar/,
// Latin on the English page. On the English page that output is identical to formatMoney()
// in app/apps/wasiati/lib/features/commerce/domain/commerce_models.dart, so the landing and
// the app never render the same row differently.
(function () {
  var sec = document.querySelector('.pricing');
  if (!sec) return;

  // ---------------------------------------------------------------- billing toggle
  var opts = sec.querySelectorAll('.bill-opt');

  function select(btn) {
    sec.setAttribute('data-bill', btn.getAttribute('data-bill'));
    Array.prototype.forEach.call(opts, function (b) {
      var on = b === btn;
      b.classList.toggle('is-active', on);
      b.setAttribute('aria-selected', String(on));
    });
  }

  Array.prototype.forEach.call(opts, function (btn) {
    btn.addEventListener('click', function () { select(btn); });
    // Arrow-key navigation between the tabs (a11y).
    btn.addEventListener('keydown', function (e) {
      if (e.key !== 'ArrowRight' && e.key !== 'ArrowLeft') return;
      e.preventDefault();
      var arr = Array.prototype.slice.call(opts);
      var next = arr[(arr.indexOf(btn) + (e.key === 'ArrowRight' ? 1 : arr.length - 1)) % arr.length];
      next.focus();
      select(next);
    });
  });

  // ---------------------------------------------------------------- live catalog
  var host = location.hostname;
  var isLocal = host === 'localhost' || host === '127.0.0.1';
  // Mirrors applinks.js: production talks to the API host; a locally served landing
  // talks to the dev backend on :4000.
  var API = isLocal ? location.protocol + '//' + host + ':4000' : 'https://api.wasiati.com';

  var CELL = { ONE_TIME: '.p-once', MONTH: '.p-monthly', YEAR: '.p-yearly' };

  // Money is rendered in the PAGE's own language: the Arabic site gets Arabic-Indic digits
  // and ر.س (٣٤٩ ر.س), the English site Latin digits and $ ($349.00). Intl handles the
  // digits, the decimal/thousands marks and the RTL bidi marks — hand-rolling those is how
  // you end up with a mangled price.
  //
  // `-u-nu-arab` requests the Arabic-Indic numbering system the Arabic design uses; plain
  // 'ar' would render Latin digits.
  var LANG = (document.documentElement.lang || 'en').toLowerCase();
  var IS_AR = LANG.indexOf('ar') === 0;
  var LOCALE = IS_AR ? 'ar-u-nu-arab' : LANG;

  function money(minor, currency) {
    var code = String(currency).toUpperCase();
    try {
      var opts = { style: 'currency', currency: code };
      if (IS_AR) {
        // The Arabic design writes whole prices (٣٤٩ ر.س · ١٬٠١٥ ر.س); fils show only when
        // a price actually has them (٢٤٫٩٩ ر.س). The English page keeps a fixed 2dp so it
        // renders the same as the app.
        opts.minimumFractionDigits = 0;
        opts.maximumFractionDigits = 2;
      }
      var nf = new Intl.NumberFormat(LOCALE, opts);
      // ICU spells the Arabic abbreviation with a trailing abbreviation dot (ر.س.); the
      // design uses ر.س. Strip ONLY that dot, and do it via formatToParts so the digits,
      // separators and bidi marks stay exactly as ICU wrote them — never regex the whole
      // formatted string. Latin symbols ($ · CA$ · SAR) carry no trailing dot, so this is
      // a no-op for them.
      return nf.formatToParts(minor / 100).map(function (p) {
        return p.type === 'currency' ? p.value.replace(/\.$/, '') : p.value;
      }).join('');
    } catch (e) {
      // Fallback mirrors formatMoney() in
      // app/apps/wasiati/lib/features/commerce/domain/commerce_models.dart. On the English
      // page Intl already agrees with it exactly, so this only matters if Intl is missing.
      var major = (minor / 100).toFixed(2);
      switch (code) {
        case 'SAR': return 'SAR ' + major;
        case 'QAR': return 'QAR ' + major;
        case 'CAD': return 'CA$' + major;
        default: return '$' + major;
      }
    }
  }

  // Plain number in the page's language too, so "17" reads ١٧ in Arabic.
  function num(n) {
    try { return new Intl.NumberFormat(LOCALE).format(n); } catch (e) { return String(n); }
  }

  // Each price cell is `<span class="p-*">AMOUNT<span class="per">once</span></span>`.
  // Replace the amount, keep (or drop) the cadence suffix.
  function setCell(span, text, keepPer) {
    var per = span.querySelector('.per');
    span.textContent = text;
    if (per && keepPer) span.appendChild(per);
  }

  function eachCell(card, fn) {
    Object.keys(CELL).forEach(function (interval) {
      var span = card.querySelector(CELL[interval]);
      if (span) fn(span, interval);
    });
  }

  // No number beats a wrong number: drop the prices and the cadence toggle, leave the
  // cards, features and CTAs intact. The section note already tells the visitor prices
  // are set for their region at checkout.
  function priceless() {
    Array.prototype.forEach.call(sec.querySelectorAll('.plan'), function (card) {
      var price = card.querySelector('.price');
      if (price) price.style.display = 'none';
    });
    var toggle = sec.querySelector('.bill-toggle');
    if (toggle) toggle.style.display = 'none';
  }

  function render(catalog) {
    var plans = (catalog && catalog.plans) || [];
    if (!plans.length) { priceless(); return; }

    // Index by tier -> interval, dropping anything checkout would refuse.
    var byTier = {};
    plans.forEach(function (p) {
      if (!p || p.purchasable === false) return;
      if (!byTier[p.tier]) byTier[p.tier] = {};
      byTier[p.tier][p.interval] = p;
    });

    var subOnly = sec.getAttribute('data-label-sub-only') || 'Subscription only';
    var priced = 0;

    Array.prototype.forEach.call(sec.querySelectorAll('.plan[data-tier]'), function (card) {
      var rows = byTier[card.getAttribute('data-tier')];

      // Tier not sold in this region at all — hide the card entirely.
      if (!rows || !Object.keys(rows).length) { card.hidden = true; return; }
      card.hidden = false;
      priced++;

      eachCell(card, function (span, interval) {
        var row = rows[interval];
        if (row) setCell(span, money(row.unitAmount, row.currency), true);
        // Sold, but not on this cycle: say so rather than show a price that cannot be
        // bought. Dropping `.per` avoids reading "Subscription only once".
        else setCell(span, subOnly, false);
      });

      // The data decides WHICH tier is badged — the backend moves "Most popular" to the
      // tier people actually subscribe to. The WORD stays the page's own, because the
      // badge string on the plan is English-only and this file also serves /ar/.
      var isBadged = Object.keys(rows).some(function (k) { return !!rows[k].badge; });
      var badgeEl = card.querySelector('.badge');
      if (badgeEl) badgeEl.style.display = isBadged ? '' : 'none';
      card.classList.toggle('popular', isBadged);
    });

    if (!priced) { priceless(); return; }

    // Yearly saving, derived from the real numbers. Use the SMALLEST saving across tiers
    // so the headline claim is true of every plan, never overstated.
    var saveEl = sec.querySelector('.bill-opt[data-bill="yearly"] .save');
    if (saveEl) {
      var pct = null;
      Object.keys(byTier).forEach(function (t) {
        var m = byTier[t].MONTH, y = byTier[t].YEAR;
        if (!m || !y || !m.unitAmount) return;
        var p = Math.round((1 - y.unitAmount / (m.unitAmount * 12)) * 100);
        if (p > 0 && (pct === null || p < pct)) pct = p;
      });
      if (pct === null) saveEl.style.display = 'none';
      else {
        saveEl.style.display = '';
        saveEl.textContent = (sec.getAttribute('data-label-save') || 'SAVE {pct}%').replace('{pct}', num(pct));
      }
    }

    // The dots were built for the cards that existed at load; a hidden tier changes that.
    document.dispatchEvent(new CustomEvent('wasiati:plans-updated'));
  }

  fetch(API + '/pricing', { credentials: 'omit' })
    .then(function (r) { return r.ok ? r.json() : Promise.reject(new Error('HTTP ' + r.status)); })
    .then(render)
    .catch(function () { priceless(); });
})();
