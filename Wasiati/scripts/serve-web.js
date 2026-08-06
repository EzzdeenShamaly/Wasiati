// Static server for the built Flutter web app, with caching switched OFF.
//
// Why this exists: Flutter's generated service worker precaches main.dart.js, so a browser
// that has visited the app once keeps serving the OLD bundle after a rebuild — the fixes are
// in the build, on disk, and the tab still shows yesterday's app. That is indistinguishable
// from "nothing got fixed", and it cost a round of confusion to diagnose.
//
// So: no-store on everything, and flutter_service_worker.js is served as an empty script so
// no service worker can install and start caching in the first place. Dev only.
//
//   node scripts/serve-web.js [port]

const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = Number(process.argv[2] || 8090);
// Optional 2nd arg: which build directory to serve (so a canvaskit and a wasm build can run
// side by side on different ports). Defaults to the standard build/web.
const ROOT = process.argv[3]
  ? path.resolve(process.argv[3])
  : path.join(__dirname, '..', 'app', 'apps', 'wasiati', 'build', 'web');

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.map': 'application/json; charset=utf-8',
};

http
  .createServer((req, res) => {
    const url = decodeURIComponent((req.url || '/').split('?')[0]);

    // Neutralise the service worker. Returning 404 would leave an already-installed one
    // registered; an empty script lets the browser replace it with a no-op and move on.
    if (url === '/flutter_service_worker.js') {
      res.writeHead(200, {
        'Content-Type': 'application/javascript; charset=utf-8',
        'Cache-Control': 'no-store, no-cache, must-revalidate',
      });
      return res.end('self.addEventListener("install",()=>self.skipWaiting());\n' +
        'self.addEventListener("activate",e=>e.waitUntil(caches.keys().then(k=>Promise.all(k.map(c=>caches.delete(c))))));\n');
    }

    // Dev convenience: the newest login code, big enough to read at a glance.
    //
    // MFA is mandatory (mandatory-mfa.spec.ts), and there is no real SMS in dev — codes go
    // to the backend's dev outbox as raw JSON. Signing in as the demo user therefore meant
    // reading a 6-digit number out of a JSON blob, every time. This just surfaces it.
    if (url === '/code') {
      http
        .get('http://localhost:4000/dev/sms', (r) => {
          let body = '';
          r.on('data', (d) => (body += d));
          r.on('end', () => {
            let code = null;
            let to = '';
            let when = '';
            try {
              const list = JSON.parse(body);
              const msgs = Array.isArray(list) ? list : list.messages || [];
              const newest = msgs.slice().sort((a, b) => new Date(b.sentAt) - new Date(a.sentAt))[0];
              if (newest) {
                const m = String(newest.body).match(/(\d{6})/);
                code = m && m[1];
                to = newest.to || '';
                when = newest.sentAt || '';
              }
            } catch (_) {}
            res.writeHead(200, {
              'Content-Type': 'text/html; charset=utf-8',
              'Cache-Control': 'no-store',
            });
            res.end(
              `<!doctype html><meta charset="utf-8"><title>Login code</title>
<meta http-equiv="refresh" content="3">
<style>body{font:16px system-ui;display:grid;place-items:center;height:100vh;margin:0;
background:#F5EFE1;color:#1C2333}code{font-size:64px;letter-spacing:.14em;font-weight:700}
small{color:#6b7280}</style>
<div style="text-align:center">
<div><code>${code || '—'}</code></div>
<p><small>${code ? `to ${to} · ${when}` : 'no code yet — sign in first'}</small></p>
<p><small>refreshes every 3s</small></p></div>`,
            );
          });
        })
        .on('error', () => {
          res.writeHead(502, { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' });
          res.end('backend not reachable on :4000');
        });
      return;
    }

    let rel = url === '/' ? 'index.html' : url.replace(/^\/+/, '');
    let file = path.join(ROOT, rel);

    // Keep the served tree inside build/web, whatever the request says.
    if (!file.startsWith(ROOT)) {
      res.writeHead(403).end('forbidden');
      return;
    }

    // SPA deep links (/wills/x/review) are routes, not files — hand them the shell.
    if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      file = path.join(ROOT, 'index.html');
    }

    fs.readFile(file, (err, buf) => {
      if (err) {
        res.writeHead(500).end(String(err));
        return;
      }
      res.writeHead(200, {
        'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream',
        'Cache-Control': 'no-store, no-cache, must-revalidate, max-age=0',
        Pragma: 'no-cache',
      });
      res.end(buf);
    });
  })
  .listen(PORT, () => {
    console.log(`serving ${ROOT}`);
    console.log(`  http://localhost:${PORT}   (no cache, no service worker)`);
  });
