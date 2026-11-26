// Lecteur d'images HDR (Radiance .hdr, RGBE compressé ligne par ligne), sans bibliothèque.
// Donne une texture équirectangulaire en demi-flottants (filtrage linéaire sur tous les appareils),
// utilisable comme environnement (reflets) par le rendu habituel et par le lancer de rayons.

import * as THREE from 'three';

/** Décode un fichier .hdr ; renvoie { width, height, data (Uint16Array RGBA, demi-flottants linéaires) }. */
export function parseHdr(b) {
  let p = 0;
  const line = () => {
    let s = '';
    while (p < b.length && b[p] !== 10) s += String.fromCharCode(b[p++]);
    p++;
    return s;
  };
  if (!line().startsWith('#?')) throw new Error('HDR : en-tête inconnu');
  let l;
  while ((l = line()) !== '') {
    if (l.startsWith('FORMAT=') && l.slice(7) !== '32-bit_rle_rgbe') throw new Error('HDR : format ' + l.slice(7) + ' non pris en charge');
    if (p >= b.length) throw new Error('HDR : en-tête incomplet');
  }
  const res = line().match(/^-Y (\d+) \+X (\d+)$/);
  if (!res) throw new Error('HDR : orientation non prise en charge');
  const h = +res[1], w = +res[2];
  const rgbe = new Uint8Array(w * h * 4);
  const scan = new Uint8Array(w * 4);
  for (let y = 0; y < h; y++) {
    const rle = w >= 8 && w < 0x8000 && b[p] === 2 && b[p + 1] === 2 && !(b[p + 2] & 0x80);
    if (!rle) {
      // ligne non compressée
      rgbe.set(b.subarray(p, p + w * 4), y * w * 4);
      p += w * 4;
      continue;
    }
    if (((b[p + 2] << 8) | b[p + 3]) !== w) throw new Error('HDR : ligne de largeur inattendue');
    p += 4;
    // quatre canaux à la suite, chacun compressé par plages
    for (let c = 0; c < 4; c++) {
      let x = 0;
      while (x < w) {
        let n = b[p++];
        if (n > 128) {
          n -= 128;
          const v = b[p++];
          for (let k = 0; k < n; k++) scan[(x++) * 4 + c] = v;
        } else {
          for (let k = 0; k < n; k++) scan[(x++) * 4 + c] = b[p++];
        }
      }
    }
    rgbe.set(scan, y * w * 4);
  }
  const data = new Uint16Array(w * h * 4);
  const one = THREE.DataUtils.toHalfFloat(1);
  for (let i = 0; i < w * h; i++) {
    const e = rgbe[i * 4 + 3];
    const f = e ? Math.pow(2, e - 136) : 0; // (mantisse + 0,5) / 256 × 2^(e − 128)
    for (let c = 0; c < 3; c++) data[i * 4 + c] = THREE.DataUtils.toHalfFloat(e ? (rgbe[i * 4 + c] + 0.5) * f : 0);
    data[i * 4 + 3] = one;
  }
  return { width: w, height: h, data };
}

/** Charge un .hdr en texture d'environnement équirectangulaire. */
export async function loadHdr(url) {
  const r = await fetch(url);
  if (!r.ok) throw new Error('HDR introuvable : ' + url);
  const { width, height, data } = parseHdr(new Uint8Array(await r.arrayBuffer()));
  const t = new THREE.DataTexture(data, width, height, THREE.RGBAFormat, THREE.HalfFloatType);
  t.mapping = THREE.EquirectangularReflectionMapping;
  t.colorSpace = THREE.LinearSRGBColorSpace;
  t.minFilter = THREE.LinearFilter;
  t.magFilter = THREE.LinearFilter;
  t.generateMipmaps = false;
  t.flipY = true;
  t.needsUpdate = true;
  return t;
}
