const http   = require('http');
const fs     = require('fs');
const path   = require('path');
const crypto = require('crypto');
const dir  = __dirname;
const mime = { '.html':'text/html', '.json':'application/json', '.js':'text/javascript', '.css':'text/css' };

// Hosts que ya pasan por Cloudflare Access (login PIN) o son locales: no piden token.
// Cualquier otro host (flujo-embed.ripaconsultora.net) exige sesion firmada para los JSON.
const TRUSTED_HOSTS = new Set(['flujo.ripaconsultora.net', 'localhost:8089', '127.0.0.1:8089']);
const FRAME_ANCESTORS = "frame-ancestors 'self' https://v0-bi-client-intranet.vercel.app https://ripaconsultora.net https://*.ripaconsultora.net";
const SESSION_TTL_SECONDS = 8 * 3600;

// Secreto compartido con la intranet (EMBED_SECRET en Vercel). Env var o archivo .embed-secret (gitignored).
function loadSecret() {
  if (process.env.EMBED_SECRET) return process.env.EMBED_SECRET.trim();
  try { return fs.readFileSync(path.join(dir, '.embed-secret'), 'utf8').trim(); } catch { return ''; }
}
const SECRET = loadSecret();

const b64url = s => Buffer.from(s).toString('base64url');
const hmac   = data => crypto.createHmac('sha256', SECRET).update(data).digest('base64url');

function signToken(payload) {
  const body = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' })) + '.' + b64url(JSON.stringify(payload));
  return body + '.' + hmac(body);
}

// JWT HS256: firma + alg + aud + exp. Devuelve claims o null.
function verifyToken(token, audience) {
  if (!SECRET || typeof token !== 'string') return null;
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  const expected = Buffer.from(hmac(parts[0] + '.' + parts[1]));
  const actual   = Buffer.from(parts[2]);
  if (expected.length !== actual.length || !crypto.timingSafeEqual(expected, actual)) return null;
  try {
    const header = JSON.parse(Buffer.from(parts[0], 'base64url').toString());
    const claims = JSON.parse(Buffer.from(parts[1], 'base64url').toString());
    if (header.alg !== 'HS256' || claims.aud !== audience) return null;
    if (typeof claims.exp !== 'number' || claims.exp < Date.now() / 1000) return null;
    return claims;
  } catch { return null; }
}

function send(res, status, msg) {
  res.writeHead(status, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end(msg);
}

if (!SECRET) console.warn('Sin EMBED_SECRET: el acceso embebido desde la intranet queda deshabilitado.');

http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const trusted = TRUSTED_HOSTS.has((req.headers.host || '').toLowerCase());
  if (!trusted) res.setHeader('Content-Security-Policy', FRAME_ANCESTORS);

  // Entrada desde la intranet: token de 5 min -> sesion de 8 h que layout.js guarda en sessionStorage.
  if (url.pathname === '/embed') {
    const claims = verifyToken(url.searchParams.get('t'), 'flujo-fondos');
    if (!claims) return send(res, 401, 'Link vencido o inválido. Volvé a abrir el dashboard desde la intranet.');
    const now = Math.floor(Date.now() / 1000);
    const session = signToken({ aud: 'flujo-session', sub: claims.sub, email: claims.email, iat: now, exp: now + SESSION_TTL_SECONDS });
    console.log(`[embed] ${new Date().toISOString()} ${claims.email || claims.sub}`);
    res.writeHead(302, { Location: '/index.html#s=' + session });
    return res.end();
  }

  let rel;
  try { rel = decodeURIComponent(url.pathname); } catch { return send(res, 400, 'Bad request'); }
  if (rel === '/') rel = '/index.html';
  const f = path.resolve(dir, '.' + rel);
  // Solo archivos del dashboard: sin salir de la carpeta, sin dotfiles, sin .ps1/.md/etc.
  if (!f.startsWith(dir + path.sep) || !mime[path.extname(f)] || path.basename(f).startsWith('.')) {
    return send(res, 404, 'Not found');
  }

  if (!trusted && path.extname(f) === '.json') {
    const m = /^Bearer (.+)$/.exec(req.headers.authorization || '');
    if (!m || !verifyToken(m[1], 'flujo-session')) return send(res, 401, 'Sesión vencida');
  }

  fs.readFile(f, (err, data) => {
    if (err) return send(res, 404, 'Not found');
    res.writeHead(200, { 'Content-Type': mime[path.extname(f)] });
    res.end(data);
  });
}).listen(8089, '127.0.0.1', () => console.log('Flujo de fondos: http://localhost:8089'));
