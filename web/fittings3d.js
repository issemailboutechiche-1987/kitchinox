// Aménagements intérieurs (paniers, tiroirs, carrousels, colonnes garde-manger…) en 3D simplifiée et paramétrique.
// Contrat : docs/fittings/CONTRAT_3D.md. Chaque famille se dessine dans le volume utile du caisson :
// repère en mm, x de 0 à w (de gauche à droite), y de 0 à h (vers le haut), z de 0 à d (du dos vers la façade).
// Les pièces sont fusionnées par matière (peu d'appels de dessin, moins de 3 000 triangles par accessoire).
//
// buildFitting(spec, w, h, d) → { group, moving, motion, travel }
//   group  : tout l'aménagement (à placer dans le repère du caisson, à l'échelle 1 mm)
//   moving : la partie qui bouge à l'ouverture (ou null)
//   motion : 'slide' (sort quand la porte est ouverte), 'drawer' (avec le tiroir), 'spin' (tourne), 'drop' (descend), null
//   travel : course en mm

import * as THREE from 'three';
import { mergeGeometries } from './vendor/utils/BufferGeometryUtils.js';

const FINISH = {
  anthracite: { color: 0x3a3d42, metalness: 0.45, roughness: 0.45 },
  chrome: { color: 0xd7dbe0, metalness: 0.9, roughness: 0.18 },
  inox: { color: 0xc2c6ca, metalness: 0.8, roughness: 0.3 },
  blanc: { color: 0xf0f0ee, metalness: 0.05, roughness: 0.5 },
  bois: { color: 0xb08058, metalness: 0, roughness: 0.6 },
};
const mats = new Map();
function mat(key) {
  let m = mats.get(key);
  if (!m) {
    const f = FINISH[key] ?? (key === 'rail' ? { color: 0x9aa0a6, metalness: 0.6, roughness: 0.35 }
      : key === 'plastic' ? { color: 0xe4e4df, metalness: 0, roughness: 0.55 }
        : key === 'dark' ? { color: 0x2b2e33, metalness: 0.2, roughness: 0.5 } : FINISH.anthracite);
    m = new THREE.MeshStandardMaterial(f);
    m.userData.cached = true; // partagé : jamais libéré avec un meuble
    mats.set(key, m);
  }
  return m;
}

/** Collecte de géométries par matière, fixes ou mobiles, fusionnées à la fin. */
class Kit {
  constructor(finish) {
    this.finish = FINISH[finish] ? finish : 'anthracite';
    this.parts = { fixed: new Map(), moving: new Map() };
  }

  put(geo, m, mv) {
    const bucket = this.parts[mv ? 'moving' : 'fixed'];
    const k = m || this.finish;
    if (!bucket.has(k)) bucket.set(k, []);
    bucket.get(k).push(geo.index ? geo.toNonIndexed() : geo);
  }

  /** Boîte entre deux coins. */
  box(x0, x1, y0, y1, z0, z1, m, mv) {
    const sx = Math.abs(x1 - x0), sy = Math.abs(y1 - y0), sz = Math.abs(z1 - z0);
    if (sx < 0.1 || sy < 0.1 || sz < 0.1) return;
    const g = new THREE.BoxGeometry(sx, sy, sz);
    g.translate((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2);
    this.put(g, m, mv);
  }

  /** Fil (cylindre fin) d'un point à un autre. */
  bar(a, b, r, m, mv) {
    const A = new THREE.Vector3(...a), B = new THREE.Vector3(...b);
    const len = A.distanceTo(B);
    if (len < 0.5) return;
    const g = new THREE.CylinderGeometry(r, r, len, 6, 1, true);
    g.applyQuaternion(new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 1, 0), B.clone().sub(A).normalize()));
    g.translate((A.x + B.x) / 2, (A.y + B.y) / 2, (A.z + B.z) / 2);
    this.put(g, m, mv);
  }

  /** Cadre rectangulaire horizontal de fil à la hauteur y. */
  rim(x0, x1, y, z0, z1, r, m, mv) {
    this.bar([x0, y, z0], [x1, y, z0], r, m, mv);
    this.bar([x0, y, z1], [x1, y, z1], r, m, mv);
    this.bar([x0, y, z0], [x0, y, z1], r, m, mv);
    this.bar([x1, y, z0], [x1, y, z1], r, m, mv);
  }

  /** Panier : fond (tôle ou fils) et bords (tôle ou fils), de hauteur h. */
  basket(x0, x1, y, h, z0, z1, wire, mv) {
    if (wire === 'solid') {
      this.box(x0, x1, y, y + 1.5, z0, z1, null, mv);
      this.box(x0, x0 + 1.5, y, y + h, z0, z1, null, mv);
      this.box(x1 - 1.5, x1, y, y + h, z0, z1, null, mv);
      this.box(x0, x1, y, y + h, z0, z0 + 1.5, null, mv);
      this.box(x0, x1, y, y + h * 0.75, z1 - 1.5, z1, null, mv);
      return;
    }
    const r = wire === 'flat' ? 2.5 : 2;
    this.rim(x0, x1, y, z0, z1, r, null, mv);
    this.rim(x0, x1, y + h, z0, z1, r, null, mv);
    if (h > 70) this.rim(x0, x1, y + h * 0.5, z0, z1, r * 0.8, null, mv);
    // fond : fils dans la profondeur ; bords : montants
    const n = Math.max(3, Math.round((x1 - x0) / 45));
    for (let i = 1; i < n; i++) this.bar([x0 + ((x1 - x0) * i) / n, y, z0], [x0 + ((x1 - x0) * i) / n, y, z1], r * 0.8, null, mv);
    const posts = Math.max(2, Math.round((z1 - z0) / 120));
    for (let i = 0; i <= posts; i++) {
      const z = z0 + ((z1 - z0) * i) / posts;
      this.bar([x0, y, z], [x0, y + h, z], r * 0.8, null, mv);
      this.bar([x1, y, z], [x1, y + h, z], r * 0.8, null, mv);
    }
    const fronts = Math.max(2, Math.round((x1 - x0) / 120));
    for (let i = 1; i < fronts; i++) {
      const x = x0 + ((x1 - x0) * i) / fronts;
      this.bar([x, y, z0], [x, y + h, z0], r * 0.8, null, mv);
      this.bar([x, y, z1], [x, y + h, z1], r * 0.8, null, mv);
    }
  }

  /** Disque (ou portion) horizontal avec son rebord : plateau tournant, haricot. */
  tray(cx, y, cz, rx, rz, theta, start, mv) {
    const g = new THREE.CylinderGeometry(1, 1, 3, 28, 1, false, start, theta);
    g.scale(rx, 1, rz);
    g.translate(cx, y + 1.5, cz);
    this.put(g, null, mv);
    const rim = new THREE.CylinderGeometry(1, 1, 40, 28, 1, true, start, theta);
    rim.scale(rx, 1, rz);
    rim.translate(cx, y + 20, cz);
    this.put(rim, 'rail', mv);
  }

  /** Coulisses fixées aux côtés du caisson, à la hauteur y, et leur partie mobile. */
  rails(w, y, d) {
    for (const x of [2, w - 2]) {
      this.box(x - 2, x + 2, y, y + 35, 10, d - 15, 'rail', false);
      this.box(x - 2, x + 2, y + 6, y + 29, 30, d - 10, 'rail', true);
    }
  }

  finish3d() {
    const group = new THREE.Group();
    const moving = new THREE.Group();
    let any = false;
    for (const [kind, bucket] of Object.entries(this.parts)) {
      for (const [k, geos] of bucket) {
        const merged = mergeGeometries(geos, false);
        for (const g of geos) g.dispose();
        if (!merged) continue;
        const mesh = new THREE.Mesh(merged, mat(k));
        mesh.castShadow = true;
        mesh.receiveShadow = true;
        mesh.userData.noMerge = true; // reste à part du regroupement des pièces fixes du meuble
        (kind === 'moving' ? moving : group).add(mesh);
        if (kind === 'moving') any = true;
      }
    }
    group.add(moving);
    return { group, moving: any ? moving : null };
  }
}

const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

/** Paniers coulissants à étages (latéraux, sous panier, ou fixés à la façade). */
function basketPullout(k, s, w, h, d) {
  const n = clamp(Math.round(s.tiers ?? 2), 1, 4);
  const mount = s.mount ?? 'side';
  const wire = s.wire ?? 'round';
  const inset = mount === 'side' ? 16 : 12;
  const x0 = inset, x1 = w - inset, z0 = 25, z1 = d - 12;
  const usable = h - 100;
  for (let i = 0; i < n; i++) {
    const y = 60 + (usable * i) / n;
    const bh = clamp((s.heights?.[i] ?? (i === 0 ? 110 : 90)), 40, usable / n - 20);
    k.basket(x0, x1, y, bh, z0, z1, wire, true);
  }
  // cadre : montants avant et arrière qui portent les étages
  const top = 60 + (usable * (n - 1)) / n + 100;
  for (const x of [x0, x1]) {
    k.bar([x, 50, z0 + 4], [x, Math.min(h - 20, top), z0 + 4], 5, 'rail', true);
    k.bar([x, 50, z1 - 4], [x, Math.min(h - 20, top), z1 - 4], 5, 'rail', true);
  }
  if (mount === 'door') k.box(x0, x1, 50, Math.min(h - 20, top), z1 - 3, z1, 'rail', true);
  if (mount === 'bottom') k.box(w / 2 - 20, w / 2 + 20, 0, 12, 20, d - 15, 'rail', false);
  else k.rails(w, 20, d);
  return { motion: 'slide', travel: clamp(d * 0.8, 200, 480) };
}

/** Tiroirs intérieurs, casseroliers, tiroir en U sous évier. */
function drawerBox(k, s, w, h, d) {
  const count = clamp(Math.round(s.count ?? 1), 1, 5);
  const bh = clamp(s.height ?? 150, 60, 260);
  const x0 = 14, x1 = w - 14, z0 = 15, z1 = d - (s.inner ? 25 : 5);
  const step = count > 1 ? (h - 40 - bh) / (count - 1) : 0;
  for (let i = 0; i < count; i++) {
    const y = 20 + step * i;
    const mv = i === 0; // le premier suit l'ouverture
    if (s.cutout === 'u') {
      // tiroir en U : passage du siphon au fond, au milieu
      const a = x0 + (x1 - x0) * 0.33, b = x1 - (x1 - x0) * 0.33, zc = z0 + (z1 - z0) * 0.45;
      k.box(x0, a, y, y + 1.5, z0, z1, null, mv);
      k.box(b, x1, y, y + 1.5, z0, z1, null, mv);
      k.box(a, b, y, y + 1.5, zc, z1, null, mv);
      k.box(x0, a, y, y + bh - 30, z0, z0 + 1.5, null, mv);
      k.box(b, x1, y, y + bh - 30, z0, z0 + 1.5, null, mv);
      k.box(a - 1.5, a, y, y + bh - 30, z0, zc, null, mv);
      k.box(b, b + 1.5, y, y + bh - 30, z0, zc, null, mv);
      k.box(a, b, y, y + bh - 30, zc - 1.5, zc, null, mv);
    } else {
      k.box(x0, x1, y, y + 1.5, z0, z1, null, mv);
      k.box(x0, x1, y, y + bh - 30, z0, z0 + 1.5, null, mv);
    }
    // côtés à double paroi (coulisse intégrée)
    k.box(x0 - 13, x0, y, y + bh, z0, z1, s.sides === 'glass' ? 'plastic' : null, mv);
    k.box(x1, x1 + 13, y, y + bh, z0, z1, s.sides === 'glass' ? 'plastic' : null, mv);
    if (s.inner) k.box(x0 - 13, x1 + 13, y, y + bh, z1 - 16, z1, 'dark', mv); // façade intérieure
  }
  return { motion: 'drawer', travel: clamp(d - 120, 200, 500) };
}

/** Colonne garde-manger : paniers sur un cadre qui sort d'un bloc, ou qui tourne. */
function tallPantry(k, s, w, h, d) {
  const n = clamp(Math.round(s.baskets ?? 5), 2, 8);
  const cols = s.double ? 2 : 1;
  for (let c = 0; c < cols; c++) {
    const za = cols === 1 ? 25 : c === 0 ? 20 : d / 2 + 5, zb = cols === 1 ? d - 12 : c === 0 ? d / 2 - 5 : d - 12;
    const mv = cols === 1 || c === 1;
    for (let i = 0; i < n; i++) {
      const y = 80 + ((h - 220) * i) / (n - 1);
      k.basket(18, w - 18, y, 90, za, zb, s.wire ?? 'round', mv);
    }
    for (const x of [18, w - 18]) for (const z of [za + 4, zb - 4]) k.bar([x, 60, z], [x, h - 40, z], 6, 'rail', mv);
  }
  k.box(w / 2 - 25, w / 2 + 25, 0, 14, 20, d - 15, 'rail', false);
  k.box(w / 2 - 25, w / 2 + 25, h - 14, h, 20, d - 15, 'rail', false);
  return s.rotating ? { motion: 'spin', travel: 0 } : { motion: 'slide', travel: clamp(d * 0.85, 250, 520) };
}

/** Plateaux tournants d'angle (3/4, 4/4, demi-lune, haricot). */
function carousel(k, s, w, h, d) {
  const L = clamp(Math.round(s.levels ?? 2), 1, 3);
  const shape = s.shape ?? '3/4';
  const r = Math.min(w, d) / 2 - 18;
  for (let i = 0; i < L; i++) {
    const y = 60 + (L > 1 ? ((h - 220) * i) / (L - 1) : 0);
    if (shape === 'half') k.tray(w / 2, y, d * 0.42, r * 1.05, r * 0.95, Math.PI, Math.PI / 2, true);
    else if (shape === 'kidney') k.tray(w / 2, y, d / 2, w / 2 - 25, d / 2 - 25, Math.PI * 2, 0, true);
    else k.tray(w / 2, y, d / 2, r, r, shape === '4/4' ? Math.PI * 2 : Math.PI * 1.5, shape === '4/4' ? 0 : Math.PI * 0.75, true);
  }
  k.bar([w / 2, 0, d / 2], [w / 2, h, d / 2], 12, 'rail', false);
  return { motion: 'spin', travel: 0 };
}

/** Angle coulissant : « magique » (2 + 2 paniers), LeMans (plateaux haricot), compact. */
function cornerPullout(k, s, w, h, d) {
  const L = clamp(Math.round(s.levels ?? 2), 1, 3);
  const type = s.type ?? 'magic';
  for (let i = 0; i < L; i++) {
    const y = 80 + (L > 1 ? ((h - 260) * i) / (L - 1) : 0);
    if (type === 'lemans') {
      k.tray(w * 0.45, y, d * 0.55, w * 0.42, d * 0.4, Math.PI * 2, 0, true);
    } else {
      k.basket(18, w * 0.5 - 8, y, 90, 30, d - 15, 'round', true); // paniers avant, sur la porte
      if (type !== 'compact') k.basket(w * 0.5 + 8, w - 18, y, 90, 25, d * 0.55, 'round', false); // paniers arrière
    }
  }
  k.bar([w * 0.25, 40, d - 20], [w * 0.25, h - 60, d - 20], 7, 'rail', true);
  k.rails(w, 20, d);
  return { motion: 'slide', travel: clamp(d * 0.75, 200, 450) };
}

/** Relevant de meuble haut : mécanismes sur les côtés, bras. */
function lift(k, s, w, h, d) {
  for (const [x0, x1] of [[0, 26], [w - 26, w]]) {
    k.box(x0, x1, h - 230, h - 20, d - 260, d - 30, 'dark', false);
    k.bar([(x0 + x1) / 2, h - 150, d - 40], [(x0 + x1) / 2, h - (s.type === 'bifold' ? 320 : 60), d - 10], 6, 'rail', false);
  }
  if (s.type === 'bifold') k.bar([26, h - 320, d - 10], [w - 26, h - 320, d - 10], 5, 'rail', false);
  return { motion: null, travel: 0 };
}

/** Étagère descendante de meuble haut. */
function pulldownShelf(k, s, w, h, d) {
  const L = clamp(Math.round(s.levels ?? 2), 1, 3);
  for (let i = 0; i < L; i++) k.basket(22, w - 22, 40 + ((h - 140) * i) / Math.max(1, L), 60, 40, d - 20, 'round', true);
  for (const x of [8, w - 8]) {
    k.bar([x, h - 40, 60], [x, 40, d - 30], 6, 'rail', true);
    k.box(x - 6, x + 6, h - 80, h - 20, 20, 120, 'dark', false);
  }
  return { motion: 'drop', travel: clamp(h * 0.45, 120, 320) };
}

/** Poubelles de tri coulissantes. */
function bins(k, s, w, h, d) {
  const n = clamp(Math.round(s.count ?? 2), 1, 4);
  const bw = (w - 40 - (n - 1) * 10) / n;
  const bh = clamp(h * 0.55, 200, 420);
  for (let i = 0; i < n; i++) {
    const x0 = 20 + i * (bw + 10), x1 = x0 + bw;
    const z0 = 40, z1 = d - 30;
    k.box(x0, x1, 22, 24, z0, z1, 'plastic', true);
    k.box(x0, x0 + 2, 22, 22 + bh, z0, z1, 'plastic', true);
    k.box(x1 - 2, x1, 22, 22 + bh, z0, z1, 'plastic', true);
    k.box(x0, x1, 22, 22 + bh, z0, z0 + 2, 'plastic', true);
    k.box(x0, x1, 22, 22 + bh, z1 - 2, z1, 'plastic', true);
    // bord : un cadre autour de l'ouverture (pas un couvercle)
    const yt = 22 + bh;
    k.box(x0 - 2, x1 + 2, yt - 6, yt, z0 - 2, z0 + 6, 'dark', true);
    k.box(x0 - 2, x1 + 2, yt - 6, yt, z1 - 6, z1 + 2, 'dark', true);
    k.box(x0 - 2, x0 + 6, yt - 6, yt, z0, z1, 'dark', true);
    k.box(x1 - 6, x1 + 2, yt - 6, yt, z0, z1, 'dark', true);
  }
  k.box(10, w - 10, 8, 20, 25, d - 15, 'rail', true);
  k.rails(w, 4, d);
  return { motion: 'slide', travel: clamp(d * 0.8, 200, 450) };
}

/** Range-couverts, porte-casseroles, porte-assiettes : un plateau à séparations dans le tiroir. */
function organizer(k, s, w, h, d) {
  const x0 = 20, x1 = w - 20, z0 = 20, z1 = d - 20, y = 25;
  k.box(x0, x1, y, y + 4, z0, z1, 'plastic', true);
  const type = s.type ?? 'cutlery';
  const cols = type === 'cutlery' ? clamp(Math.round((x1 - x0) / 90), 3, 8) : 2;
  const hh = type === 'plates' ? 90 : 50;
  for (let i = 0; i <= cols; i++) {
    const x = x0 + ((x1 - x0) * i) / cols;
    k.box(x - 2, x + 2, y, y + hh, z0, z1, 'plastic', true);
  }
  if (type === 'cutlery') k.box(x0, x1, y, y + hh, (z0 + z1) * 0.35 - 2, (z0 + z1) * 0.35 + 2, 'plastic', true);
  if (type === 'plates') for (let i = 1; i < 8; i++) k.bar([x0 + 20, y, z0 + ((z1 - z0) * i) / 8], [x0 + 20, y + 120, z0 + ((z1 - z0) * i) / 8], 4, 'rail', true);
  return { motion: 'drawer', travel: clamp(d - 120, 200, 500) };
}

/** Coulissants étroits : épices, bouteilles, porte-serviettes. */
function rack(k, s, w, h, d) {
  const type = s.type ?? 'spice';
  const n = clamp(Math.round(s.tiers ?? 2), 1, 6);
  const x0 = 15, x1 = w - 15;
  if (type === 'towel') {
    for (let i = 0; i < 3; i++) k.bar([x0 + ((x1 - x0) * (i + 0.5)) / 3, h - 60, 30], [x0 + ((x1 - x0) * (i + 0.5)) / 3, h - 60, d - 30], 5, null, true);
    k.box(x0, x1, h - 80, h - 70, d - 40, d - 20, 'rail', true);
  } else {
    for (let i = 0; i < n; i++) {
      const y = 60 + ((h - 160) * i) / n;
      k.basket(x0, x1, y, type === 'bottle' ? 120 : 70, 30, d - 15, 'round', true);
    }
    for (const z of [34, d - 19]) k.bar([w / 2, 40, z], [w / 2, h - 40, z], 7, 'rail', true);
  }
  k.rails(w, 20, d);
  return { motion: 'slide', travel: clamp(d * 0.8, 200, 480) };
}

/** Dressing : penderie, porte-pantalons, cravates, chaussures. */
function rod(k, s, w, h, d) {
  const type = s.type ?? 'rod';
  if (type === 'shoe') {
    for (let i = 0; i < 2; i++) {
      const y = 60 + i * 220;
      for (let j = 0; j < 4; j++) k.bar([20, y + j * 18, 40 + j * 60], [w - 20, y + j * 18, 40 + j * 60], 4, null, false);
    }
    return { motion: null, travel: 0 };
  }
  if (type === 'trouser' || type === 'tie') {
    const y = h - 120;
    const n = type === 'tie' ? 14 : clamp(Math.round((d - 80) / 40), 6, 14);
    for (let i = 0; i < n; i++) k.bar([20, y, 40 + ((d - 80) * i) / (n - 1)], [w * 0.7, y, 40 + ((d - 80) * i) / (n - 1)], 4, null, true);
    k.box(w * 0.7, w * 0.7 + 12, y - 40, y + 20, 20, d - 20, 'rail', true);
    k.rails(w, y - 40, d);
    return { motion: 'slide', travel: clamp(d * 0.8, 200, 480) };
  }
  if (type === 'pullout_rod') {
    k.bar([25, h - 90, d / 2], [w - 25, h - 90, d / 2], 10, null, true);
    for (const x of [12, w - 12]) k.bar([x, h - 20, 40], [x, h - 90, d / 2], 6, 'rail', true);
    return { motion: 'drop', travel: clamp(h * 0.4, 150, 450) };
  }
  k.bar([4, h - 70, d / 2], [w - 4, h - 70, d / 2], 12, null, false);
  for (const x of [4, w - 4]) k.box(x - 4, x + 4, h - 95, h - 55, d / 2 - 15, d / 2 + 15, 'rail', false);
  return { motion: null, travel: 0 };
}

const FAMILIES = {
  basket_pullout: basketPullout,
  drawer_box: drawerBox,
  tall_pantry: tallPantry,
  carousel,
  corner_pullout: cornerPullout,
  lift,
  pulldown_shelf: pulldownShelf,
  bins,
  organizer,
  rack,
  rod,
};

/** Construit l'aménagement [spec] dans un volume utile de w × h × d mm. Null si rien à dessiner. */
export function buildFitting(spec, w, h, d) {
  const f = FAMILIES[spec?.family];
  if (!f || w < 80 || h < 60 || d < 120) return null;
  const k = new Kit(spec.finish);
  const { motion, travel } = f(k, spec, w, h, d);
  const { group, moving } = k.finish3d();
  return { group, moving, motion: moving ? motion : null, travel };
}

/** Familles connues (diagnostic, tests). */
export const fittingFamilies = Object.keys(FAMILIES);
