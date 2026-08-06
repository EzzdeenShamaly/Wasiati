// Wasiati landing — mobile carousel dot indicators for the Why & Plans sliders.
// CSP-safe (script-src 'self'). Mirrors the prototype's mkDots/mkOnScroll:
// click scrolls proportionally, scroll syncs the active dot, RTL-aware.
(function () {
  function wire(slider, dotsBox) {
    if (!slider || !dotsBox) return;
    // Re-runnable: pricing.js hides any tier the visitor's region cannot buy and then
    // fires `wasiati:plans-updated`, so the dots must be rebuilt for the cards that are
    // actually left — otherwise a Saudi visitor gets a dot for a card that isn't there.
    if (slider._dotsOnScroll) slider.removeEventListener('scroll', slider._dotsOnScroll);
    dotsBox.textContent = '';

    var count = Array.prototype.filter.call(slider.children, function (c) { return !c.hidden; }).length;
    if (count < 2) return;
    var rtl = document.documentElement.dir === 'rtl';
    var label = dotsBox.getAttribute('data-dot-label') || 'Card';
    var dots = [];

    for (var i = 0; i < count; i++) {
      (function (i) {
        var b = document.createElement('button');
        b.type = 'button';
        b.setAttribute('aria-label', label + ' ' + (i + 1));
        b.addEventListener('click', function () {
          var max = slider.scrollWidth - slider.clientWidth;
          if (max <= 0) return;
          var left = max * (i / Math.max(1, count - 1)) * (rtl ? -1 : 1);
          slider.scrollTo({ left: left, behavior: 'smooth' });
        });
        dotsBox.appendChild(b);
        dots.push(b);
      })(i);
    }

    var active = -1;
    function setActive(i) {
      if (i === active) return;
      active = i;
      for (var j = 0; j < dots.length; j++) dots[j].classList.toggle('is-active', j === i);
    }
    function onScroll() {
      var max = slider.scrollWidth - slider.clientWidth;
      if (max <= 0) { setActive(0); return; }
      var i = Math.round(Math.abs(slider.scrollLeft) / max * (count - 1));
      setActive(Math.max(0, Math.min(count - 1, i)));
    }
    // Kept on the element so a rebuild can detach the previous one instead of stacking
    // a second listener on every re-wire.
    slider._dotsOnScroll = onScroll;
    slider.addEventListener('scroll', onScroll, { passive: true });
    setActive(0);
  }

  function plans() {
    wire(document.getElementById('plans-slider'), document.getElementById('plans-dots'));
  }

  wire(document.getElementById('why-slider'), document.getElementById('why-dots'));
  plans();
  document.addEventListener('wasiati:plans-updated', plans);
})();
