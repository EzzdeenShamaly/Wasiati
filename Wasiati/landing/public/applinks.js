// Wasiati landing — point the app links (Sign in / Create / register) at the running
// app. In production they stay as https://app.wasiati.com/…; when the landing is served
// locally for testing, rewrite them to the local Flutter app (localhost:3000) and map
// to its hash routes (/#/login). CSP-safe (script-src 'self').
(function () {
  var host = location.hostname;
  var isLocal = host === 'localhost' || host === '127.0.0.1';
  if (!isLocal) return;
  var APP = location.protocol + '//' + host + ':3000/#';
  var links = document.querySelectorAll('a[href*="app.wasiati.com"]');
  for (var i = 0; i < links.length; i++) {
    var raw = links[i].getAttribute('href') || '';
    // https://app.wasiati.com/login  ->  http://localhost:3000/#/login
    links[i].setAttribute('href', raw.replace(/https?:\/\/app\.wasiati\.com/, APP));
  }
})();
