// Wasiati landing theme toggle. Loaded blocking in <head> so the stored
// preference is applied before first paint (no flash). CSP-safe (script-src 'self').
(function () {
  var KEY = 'wasiati-theme';
  try {
    var saved = localStorage.getItem(KEY);
    if (saved === 'dark' || saved === 'light') {
      document.documentElement.setAttribute('data-theme', saved);
    }
  } catch (e) {}

  function current() {
    var attr = document.documentElement.getAttribute('data-theme');
    if (attr) return attr;
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }

  function wire() {
    var btn = document.querySelector('.toggle');
    if (!btn) return;
    // Sync aria-pressed to the ACTUAL initial theme (OS or saved), not the hardcoded
    // 'false' in the HTML — otherwise a user landing in dark mode hears "not pressed".
    btn.setAttribute('aria-pressed', String(current() === 'dark'));
    btn.addEventListener('click', function () {
      var next = current() === 'dark' ? 'light' : 'dark';
      document.documentElement.setAttribute('data-theme', next);
      try { localStorage.setItem(KEY, next); } catch (e) {}
      btn.setAttribute('aria-pressed', String(next === 'dark'));
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', wire);
  } else {
    wire();
  }
})();
