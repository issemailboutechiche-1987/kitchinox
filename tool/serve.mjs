// Serveur de la version de production (build/web) pour la tablette sur le réseau local.
// Compression brotli / gzip (mise en cache en mémoire), types MIME corrects, cache long pour les fichiers
// statiques, jamais de cache pour index.html et le service worker (une nouvelle version est vue tout de suite).
// Usage : node tool/serve.mjs [port] [dossier]     (par défaut : 8690 build/web)
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

const port = Number(process.argv[2] || 8690);
const root = path.resolve(process.argv[3] || 'build/web');

const types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.webp': 'image/webp',
  '.ico': 'image/x-icon',
  '.wasm': 'application/wasm',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff2': 'font/woff2',
  '.glb': 'model/gltf-binary',
  '.gltf': 'model/gltf+json',
  '.bin': 'application/octet-stream',
  '.txt': 'text/plain; charset=utf-8',
};
const compressible = new Set(['.html', '.js', '.mjs', '.json', '.css', '.svg', '.wasm', '.ttf', '.otf', '.gltf', '.bin', '.txt', '.glb']);
const cache = new Map(); // chemin|encodage → { mtime, body }

function encoded(file, ext, enc, stat) {
  const key = file + '|' + enc;
  const c = cache.get(key);
  if (c && c.mtime === stat.mtimeMs) return c.body;
  const raw = fs.readFileSync(file);
  const body = enc === 'br'
    ? zlib.brotliCompressSync(raw, { params: { [zlib.constants.BROTLI_PARAM_QUALITY]: 9 } })
    : enc === 'gzip' ? zlib.gzipSync(raw, { level: 9 }) : raw;
  cache.set(key, { mtime: stat.mtimeMs, body });
  return body;
}

http.createServer((req, res) => {
  try {
    let rel = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    if (rel.endsWith('/')) rel += 'index.html';
    let file = path.join(root, rel);
    if (!file.startsWith(root)) {
      res.writeHead(403).end();
      return;
    }
    if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) file = path.join(root, 'index.html'); // application d'une seule page
    const stat = fs.statSync(file);
    const ext = path.extname(file).toLowerCase();
    const accept = String(req.headers['accept-encoding'] || '');
    const enc = !compressible.has(ext) ? 'identity' : accept.includes('br') ? 'br' : accept.includes('gzip') ? 'gzip' : 'identity';
    // cache : l'application (js, wasm, json…) est revérifiée à chaque chargement (ETag : pas de re-téléchargement
    // si rien n'a changé) ; seuls les modèles 3D, vignettes et polices restent en cache une journée
    const etag = `"${stat.size.toString(16)}-${Math.floor(stat.mtimeMs).toString(16)}-${enc}"`;
    const longCache = /[\\/](objects|fonts)[\\/]/.test(file) || ext === '.glb' || ext === '.png' || ext === '.jpg';
    if (req.headers['if-none-match'] === etag) {
      res.writeHead(304, { ETag: etag, 'Cache-Control': longCache ? 'public, max-age=86400' : 'no-cache' }).end();
      return;
    }
    const body = encoded(file, ext, enc, stat);
    res.writeHead(200, {
      'Content-Type': types[ext] || 'application/octet-stream',
      'Content-Length': body.length,
      ETag: etag,
      'Cache-Control': longCache ? 'public, max-age=86400' : 'no-cache',
      ...(enc !== 'identity' ? { 'Content-Encoding': enc, Vary: 'Accept-Encoding' } : {}),
    });
    res.end(req.method === 'HEAD' ? undefined : body);
  } catch (e) {
    res.writeHead(500).end(String(e));
  }
}).listen(port, '0.0.0.0', () => console.log(`kitchinox servi sur http://0.0.0.0:${port} (${root})`));
