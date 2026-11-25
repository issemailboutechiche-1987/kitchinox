// Vue 3D temps réel (WebGL, three.js) de kitchinox.
// La scène arrive de Flutter en JSON (mm, repère du plan : x, y vers l'avant, z vers le haut) ;
// les images (façades, intérieurs, textures) arrivent en pixels RGBA et sont mises en cache.
// Repère three.js : X = x, Y = z (haut), Z = y — le plan est « main gauche », ce choix le respecte.

import * as THREE from 'three';
import { OrbitControls } from './vendor/OrbitControls.js';
import { RoomEnvironment } from './vendor/environments/RoomEnvironment.js';
import { mergeGeometries } from './vendor/utils/BufferGeometryUtils.js';
import { hdStart, hdState, hdStop, hdRunning } from './hd_render.js';
import { buildUsdz, openUsdz, arQuickLookSupported } from './ar_export.js';

const S = 0.001; // mm → m
const P = (x, y, z) => new THREE.Vector3(x * S, z * S, y * S);

const images = new Map(); // clé → THREE.DataTexture (source)
let renderer, scene, camera, controls, host, raf = 0;
let data = null;
const groups = new Map(); // clé de groupe → { sig, obj }
const doors = []; // { uid, pivot, kind, max }
const progress = new Map(); // partie (uid#n) → ouverture animée 0..1
let selBox = null;
let hemiLight, ambLight, fillLight, sideLight, rimLight;
let lastYaw = null, lastZoom = null, lastView = 0, baseDist = 6, lastStudio = '';
let camAnim = null; // déplacement de caméra en cours { p0, t0, p1, t1, k }
let handlers = null;
let lastT = performance.now();

// Rendu à la demande : on ne dessine que si quelque chose a changé (scène, caméra, porte en mouvement).
// Au repos, la carte graphique ne travaille plus : tablette froide, batterie épargnée.
let needsRender = 2; // images encore à dessiner
let shadowsDirty = true; // ombres à recalculer (la cuisine a changé, pas seulement la caméra)
let interacting = false; // geste en cours : résolution réduite
let lowRes = false;
const stats = { frames: 0, shadowUpdates: 0, idleSkips: 0 };

/** Demande un nouveau dessin ; [shadows] : la géométrie a changé, les ombres aussi. */
function invalidate(shadows = false) {
  needsRender = Math.max(needsRender, 2);
  if (shadows) shadowsDirty = true;
}

const fullDpr = () => Math.min(window.devicePixelRatio || 1, 2);
// pendant un geste : au plus 1 pixel par point (4 fois moins de pixels sur un écran Retina)
const gestureDpr = () => Math.min(fullDpr(), 1);
function setDpr(v) {
  if (renderer && Math.abs(renderer.getPixelRatio() - v) > 1e-3) renderer.setPixelRatio(v);
}
function gestureStart() {
  interacting = true;
  if (!lowRes) {
    lowRes = true;
    setDpr(gestureDpr());
  }
  invalidate();
}
function gestureEnd() {
  interacting = false;
  invalidate();
}

let lastSel = '';
/** Cadre à l'écran (px de la vue) de l'élément choisi : l'application y pose ses boutons flottants. */
function reportSelection() {
  let key = 'none';
  if (selBox && host) {
    const b = new THREE.Box3().setFromObject(selBox);
    if (!b.isEmpty()) {
      const w = host.clientWidth, h = host.clientHeight;
      let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity, behind = false;
      for (let k = 0; k < 8; k++) {
        const v = new THREE.Vector3(k & 1 ? b.max.x : b.min.x, k & 2 ? b.max.y : b.min.y, k & 4 ? b.max.z : b.min.z).project(camera);
        if (v.z > 1) behind = true;
        const px = (v.x + 1) / 2 * w, py = (1 - v.y) / 2 * h;
        x0 = Math.min(x0, px); x1 = Math.max(x1, px); y0 = Math.min(y0, py); y1 = Math.max(y1, py);
      }
      if (!behind && x1 > 0 && y1 > 0 && x0 < w && y0 < h) key = [x0, y0, x1, y1].map((q) => Math.round(q)).join(',');
    }
  }
  if (key === lastSel) return;
  lastSel = key;
  // toujours quatre nombres (-1 : rien de choisi) : la fonction de l'application attend quatre arguments
  if (key === 'none') handler('sel', -1, -1, -1, -1);
  else handler('sel', ...key.split(',').map(Number));
}

function handler(name, ...args) {
  const h = window.kitchen3dHandlers;
  if (h && typeof h[name] === 'function') h[name](...args);
}

// ------------------------------------------------------------------ matériaux

const texCache = new Map(); // `${key}|${rx}|${ry}|${rot}` → texture
function tex(key, repeatX, repeatY, rotate) {
  const src = images.get(key);
  if (!src) return null;
  const k = `${key}|${repeatX.toFixed(3)}|${repeatY.toFixed(3)}|${rotate ? 1 : 0}`;
  let t = texCache.get(k);
  if (!t) {
    t = src.clone();
    t.wrapS = t.wrapT = THREE.RepeatWrapping;
    t.repeat.set(repeatX, repeatY);
    if (rotate) {
      t.center.set(0.5, 0.5);
      t.rotation = Math.PI / 2;
    }
    t.needsUpdate = true;
    texCache.set(k, t);
  }
  return t;
}

/** Matériau d'une face de [w] x [h] mm (motif réel [m.tile] mm). */
function faceMat(m, w, h, vertical) {
  const p = { color: new THREE.Color(m.color), roughness: m.rough ?? 0.6, metalness: m.metal ?? 0 };
  if (m.map) {
    const tile = m.tile || 800;
    const rot = !!(vertical && m.vertical);
    p.map = rot ? tex(m.map, h / tile, w / tile, true) : tex(m.map, w / tile, h / tile, false);
  }
  return new THREE.MeshStandardMaterial(p);
}

function imageMat(key, opts = {}) {
  const src = images.get(key);
  // laqué brillant : vernis qui reflète la pièce
  const m = opts.gloss
    ? new THREE.MeshPhysicalMaterial({ roughness: 0.16, metalness: 0, clearcoat: 0.9, clearcoatRoughness: 0.06 })
    : new THREE.MeshStandardMaterial({ roughness: opts.rough ?? 0.5, metalness: 0 });
  if (src) m.map = src;
  return m;
}

// ------------------------------------------------------------------ construction

function boxMesh(b, mat) {
  const sx = b.x1 - b.x0, sy = b.z1 - b.z0, sz = b.y1 - b.y0;
  if (sx <= 0 || sy <= 0 || sz <= 0) return null;
  const g = new THREE.BoxGeometry(sx * S, sy * S, sz * S);
  // faces : +x, -x (profondeur x hauteur), +y, -y (dessus), +z, -z (largeur x hauteur)
  const mats = [
    faceMat(mat, sz, sy, true), faceMat(mat, sz, sy, true),
    faceMat(mat, sx, sz, false), faceMat(mat, sx, sz, false),
    faceMat(mat, sx, sy, true), faceMat(mat, sx, sy, true),
  ];
  const mesh = new THREE.Mesh(g, mats);
  mesh.position.copy(P((b.x0 + b.x1) / 2, (b.y0 + b.y1) / 2, (b.z0 + b.z1) / 2));
  mesh.castShadow = mesh.receiveShadow = true;
  return mesh;
}

/** Repère d'un mur : X le long du mur, Y vers le haut, Z vers l'intérieur de la pièce. */
function wallBasis(f) {
  const x = new THREE.Vector3(f.dx, 0, f.dy), y = new THREE.Vector3(0, 1, 0), z = new THREE.Vector3(f.nx, 0, f.ny);
  return new THREE.Matrix4().makeBasis(x, y, z);
}

function onWall(f, s, t, z) {
  return P(f.ox + f.dx * s + f.nx * t, f.oy + f.dy * s + f.ny * t, z);
}

function buildRoom(d) {
  const g = new THREE.Group();
  const r = d.room;
  if (d.studio) {
    // présentation : fond blanc, seule l'ombre des meubles se voit au sol
    const big = Math.max(r.w, r.d) * S * 6;
    const ground = new THREE.Mesh(new THREE.PlaneGeometry(big, big), new THREE.ShadowMaterial({ opacity: 0.16 }));
    ground.rotation.x = -Math.PI / 2;
    ground.position.set(r.w * S / 2, -0.001, r.d * S / 2);
    ground.receiveShadow = true;
    g.add(ground);
    return g;
  }
  // sol
  const fm = d.floor;
  let floor;
  if (d.floorPoly) {
    // pièce à contour libre : sol découpé selon les traits et les arcs (repère du plan : y vers l'avant)
    const sh = new THREE.Shape(d.floorPoly.map(([x, y]) => new THREE.Vector2(x * S, -y * S)));
    const geo = new THREE.ShapeGeometry(sh);
    // UV en mètres pour le motif du sol
    const uv = geo.attributes.uv;
    const pos = geo.attributes.position;
    for (let i = 0; i < uv.count; i++) uv.setXY(i, pos.getX(i) / (r.w * S), -pos.getY(i) / (r.d * S));
    floor = new THREE.Mesh(geo, faceMat(fm, r.w, r.d, false));
    floor.rotation.x = -Math.PI / 2;
  } else {
    floor = new THREE.Mesh(new THREE.PlaneGeometry(r.w * S, r.d * S), faceMat(fm, r.w, r.d, false));
    floor.rotation.x = -Math.PI / 2;
    floor.position.set(r.w * S / 2, 0, r.d * S / 2);
  }
  floor.receiveShadow = true;
  g.add(floor);
  // murs (avec ouvertures), 100 mm d'épaisseur vers l'extérieur
  for (const w of d.walls) {
    const shape = new THREE.Shape();
    shape.moveTo(0, 0);
    shape.lineTo(w.len * S, 0);
    shape.lineTo(w.len * S, r.h * S);
    shape.lineTo(0, r.h * S);
    shape.lineTo(0, 0);
    for (const o of w.openings) {
      const h = new THREE.Path();
      h.moveTo(o.s * S, o.z * S);
      h.lineTo((o.s + o.w) * S, o.z * S);
      h.lineTo((o.s + o.w) * S, (o.z + o.h) * S);
      h.lineTo(o.s * S, (o.z + o.h) * S);
      h.lineTo(o.s * S, o.z * S);
      shape.holes.push(h);
    }
    const geo = new THREE.ExtrudeGeometry(shape, { depth: 0.1, bevelEnabled: false });
    const wm = d.wall;
    const mat = new THREE.MeshStandardMaterial({ color: new THREE.Color(wm.color), roughness: wm.rough ?? 0.9 });
    if (wm.map) mat.map = tex(wm.map, 1000 / (wm.tile || 800), 1000 / (wm.tile || 800), false);
    const mesh = new THREE.Mesh(geo, mat);
    mesh.applyMatrix4(wallBasis(w));
    mesh.position.copy(onWall(w, 0, -100, 0));
    mesh.receiveShadow = true;
    mesh.userData.wall = w;
    g.add(mesh);
    // ouvertures : vitre et cadre, ou porte
    for (const o of w.openings) {
      // menuiserie selon le modèle : vantail plein (teinte du modèle) ou vitré, montants et traverses
      const metal = o.mech === 'sliding_horizontal' || (o.door && o.glazed);
      const frameMat = new THREE.MeshStandardMaterial({ color: metal ? 0x3a3d42 : 0xffffff, roughness: metal ? 0.35 : 0.4, metalness: metal ? 0.4 : 0 });
      const glassMat = new THREE.MeshPhysicalMaterial({ color: 0xbcdcf0, roughness: 0.05, transparent: true, opacity: 0.4, side: THREE.DoubleSide });
      const leafMat = o.door && !o.glazed ? new THREE.MeshStandardMaterial({ color: o.leaf ?? 0xd9cbb5, roughness: 0.55 }) : glassMat;
      const leaf = new THREE.Mesh(new THREE.BoxGeometry(o.w * S, o.h * S, o.door ? 0.04 : 0.008), leafMat);
      leaf.applyMatrix4(wallBasis(w));
      leaf.position.copy(onWall(w, o.s + o.w / 2, -40, o.z + o.h / 2));
      leaf.userData.wallOf = w.id;
      leaf.castShadow = !!o.door && !o.glazed;
      g.add(leaf);
      // poignée de porte (côté opposé aux charnières)
      if (o.door && o.mech !== 'hinged_flush_push_pull') {
        const hs = o.hinge === 'right' ? o.s + 110 : o.s + o.w - 110;
        const hnd = new THREE.Mesh(new THREE.BoxGeometry(0.12, 0.02, 0.02), new THREE.MeshStandardMaterial({ color: 0xffffff, metalness: 1, roughness: 0.15 }));
        hnd.applyMatrix4(wallBasis(w));
        hnd.position.copy(onWall(w, hs, -10, 1050));
        hnd.userData.wallOf = w.id;
        g.add(hnd);
      }
      const bars = [];
      const two = o.mech === 'hinged_double' || (!o.door && (o.mech.startsWith('casement') || o.mech === 'mixed_casement_and_fixed') && o.w >= 800);
      if (two || o.mech === 'sliding_horizontal') bars.push([o.s + o.w / 2 - 25, o.z, 50, o.h]);
      if (o.mech === 'sliding_vertical') bars.push([o.s, o.z + o.h / 2 - 25, o.w, 50]);
      if (o.mech === 'louver_pivoting') for (let i = 1; i < 10; i++) bars.push([o.s, o.z + (o.h * i) / 10 - 8, o.w, 16]);
      if (o.door && o.glazed && o.mech === 'hinged_double') for (let i = 1; i < 4; i++) bars.push([o.s, o.z + (o.h * i) / 4 - 10, o.w, 20]);
      for (const [s0, z0, sw, sh] of [[o.s, o.z, o.w, 50], [o.s, o.z + o.h - 50, o.w, 50], [o.s, o.z, 50, o.h], [o.s + o.w - 50, o.z, 50, o.h], ...bars]) {
        const fr = new THREE.Mesh(new THREE.BoxGeometry(sw * S, sh * S, 0.06), frameMat);
        fr.applyMatrix4(wallBasis(w));
        fr.position.copy(onWall(w, s0 + sw / 2, -20, z0 + sh / 2));
        fr.userData.wallOf = w.id;
        g.add(fr);
      }
    }
  }
  // crédence
  if (d.splashMat) {
    for (const sp of d.splash) {
      const w = d.walls.find((x) => x.id === sp.wall);
      if (!w) continue;
      const pw = sp.s1 - sp.s0, ph = sp.z1 - sp.z0;
      const mesh = new THREE.Mesh(new THREE.PlaneGeometry(pw * S, ph * S), faceMat(d.splashMat, pw, ph, false));
      mesh.applyMatrix4(wallBasis(w));
      mesh.position.copy(onWall(w, (sp.s0 + sp.s1) / 2, 2, (sp.z0 + sp.z1) / 2));
      mesh.receiveShadow = true;
      mesh.userData.wallOf = w.id;
      mesh.userData.splash = true; // crédence : fait partie de la cuisine (AR)
      g.add(mesh);
    }
  }
  return g;
}

/** Une case de façade : volume de 18 mm, image sur la face avant, intérieur derrière. */
// miroir : métal poli qui reflète l'environnement de la pièce
const mirrorMat = new THREE.MeshStandardMaterial({ color: 0xf4f7f8, metalness: 1, roughness: 0.02 });

/** Relief d'une façade à cadre : quatre montants de [fw] mm en avant du panneau, et un panneau central bombé si [raised]. */
function frameRelief(w, h, fw, raised, front, edge, uid) {
  const g = new THREE.Group();
  const slab = (x0, x1, y0, y1, up) => {
    const geo = new THREE.BoxGeometry((x1 - x0) * S, (y1 - y0) * S, up);
    const uv = geo.attributes.uv;
    const u0 = x0 / w, u1 = x1 / w, v0 = y0 / h, v1 = y1 / h;
    for (let i = 16; i < 20; i++) uv.setXY(i, u0 + (u1 - u0) * uv.getX(i), v0 + (v1 - v0) * uv.getY(i));
    // chants dans la teinte de la façade : le relief accroche la lumière
    const m = new THREE.Mesh(geo, [front, front, front, front, front, edge]);
    m.position.set(((x0 + x1) / 2 - w / 2) * S, ((y0 + y1) / 2 - h / 2) * S, 0.009 + up / 2);
    m.castShadow = m.receiveShadow = true;
    m.userData.uid = uid;
    g.add(m);
  };
  slab(0, fw, 0, h, 0.006);
  slab(w - fw, w, 0, h, 0.006);
  slab(fw, w - fw, 0, fw, 0.006);
  slab(fw, w - fw, h - fw, h, 0.006);
  const k = fw + 40;
  if (raised && w - 2 * k > 60 && h - 2 * k > 60) slab(k, w - k, k, h - k, 0.004);
  return g;
}

/** Porte vitrée : quatre montants (la matière de la façade devant et derrière) et une vitre transparente. */
function glassPanel(w, h, fw, front, edge, uid, muntins) {
  const g = new THREE.Group();
  const bar = (x0, x1, y0, y1) => {
    const geo = new THREE.BoxGeometry((x1 - x0) * S, (y1 - y0) * S, 0.018);
    const uv = geo.attributes.uv;
    // portion de l'image de façade sous ce montant ; au dos, la même, retournée
    const u0 = x0 / w, u1 = x1 / w, v0 = y0 / h, v1 = y1 / h;
    for (let i = 16; i < 20; i++) uv.setXY(i, u0 + (u1 - u0) * uv.getX(i), v0 + (v1 - v0) * uv.getY(i));
    for (let i = 20; i < 24; i++) uv.setXY(i, u1 + (u0 - u1) * uv.getX(i), v0 + (v1 - v0) * uv.getY(i));
    const m = new THREE.Mesh(geo, [edge, edge, edge, edge, front, front]);
    m.position.set(((x0 + x1) / 2 - w / 2) * S, ((y0 + y1) / 2 - h / 2) * S, 0);
    m.castShadow = m.receiveShadow = true;
    m.userData.uid = uid;
    g.add(m);
  };
  bar(0, fw, 0, h);
  bar(w - fw, w, 0, h);
  bar(fw, w - fw, 0, fw);
  bar(fw, w - fw, h - fw, h);
  if (muntins) {
    const iw = w - 2 * fw, ih = h - 2 * fw, nx = iw > 300 ? 2 : 1, ny = Math.min(6, Math.max(1, Math.round(ih / 280)));
    for (let k = 1; k < nx; k++) bar(fw + iw * k / nx - 9, fw + iw * k / nx + 9, fw, h - fw);
    for (let k = 1; k < ny; k++) bar(fw, w - fw, fw + ih * k / ny - 9, fw + ih * k / ny + 9);
  }
  const pane = new THREE.Mesh(new THREE.BoxGeometry((w - 2 * fw) * S, (h - 2 * fw) * S, 0.004), glass);
  pane.userData.uid = uid;
  pane.renderOrder = 2; // après l'intérieur du meuble
  g.add(pane);
  return g;
}

/** Poignées en volume (barre, bouton, coquille, cuir, profil sur chant), posées sur la façade de w × h mm. */
function buildGrips(list, w, h, uid) {
  const g = new THREE.Group();
  const front = 0.0095; // face avant du panneau (18 mm, centré)
  for (const q of list) {
    const mat = new THREE.MeshStandardMaterial({ color: q.c, roughness: q.k === 'leather' ? 0.8 : 0.32, metalness: q.k === 'leather' ? 0 : 0.65 });
    const add = (geo, x, y, z, rx = 0, ry = 0, rz = 0) => {
      const m = new THREE.Mesh(geo, mat);
      m.position.set(x, y, z);
      m.rotation.set(rx, ry, rz);
      m.castShadow = true;
      m.userData.uid = uid;
      g.add(m);
      return m;
    };
    const x = (q.x - w / 2) * S, y = (h / 2 - q.y) * S;
    const turn = q.v ? 0 : Math.PI / 2; // cylindre vertical ou couché
    switch (q.k) {
      case 'knob': {
        const r = Math.max(10, q.size > 10 && q.size < 60 ? q.size / 2 : 15) * S;
        add(new THREE.CylinderGeometry(r * 0.45, r * 0.55, 0.018, 20), x, y, front + 0.009, Math.PI / 2);
        add(new THREE.CylinderGeometry(r, r * 0.8, 0.012, 28), x, y, front + 0.023, Math.PI / 2);
        break;
      }
      case 'cup': {
        const len = 0.095;
        const geo = new THREE.CylinderGeometry(0.024, 0.024, len, 20, 1, true, 0, Math.PI);
        const m = add(geo, x, y, front, 0, 0, Math.PI / 2);
        m.material = mat.clone();
        m.material.side = THREE.DoubleSide;
        m.rotation.set(0, 0, Math.PI / 2);
        m.rotateY(-Math.PI / 2);
        break;
      }
      case 'leather':
        add(new THREE.BoxGeometry(0.025, 0.07, 0.004), x, y - 0.022, front + 0.012, -0.18);
        add(new THREE.CylinderGeometry(0.005, 0.005, 0.016, 14), x, y + 0.008, front + 0.008, Math.PI / 2);
        break;
      case 'edge':
      case 'edgeFull':
      case 'jProfile': {
        const len = Math.max(20, q.len) * S, d = q.k === 'jProfile' ? 0.024 : 0.02;
        const a = q.v ? [0.004, len, d] : [len, 0.004, d], b = q.v ? [0.014, len, 0.003] : [len, 0.014, 0.003];
        add(new THREE.BoxGeometry(...a), x, y, front + d / 2 - 0.002);
        add(new THREE.BoxGeometry(...b), x, y, front + d - 0.002);
        break;
      }
      default: {
        const len = Math.max(60, q.len) * S, r = (q.k === 'xxl' ? 9 : 6) * S, out = (q.k === 'xxl' ? 45 : 34) * S;
        add(new THREE.CylinderGeometry(r, r, len, 18), x, y, front + out, 0, 0, turn);
        const c = len / 2 - Math.min(0.02, len * 0.12);
        for (const k of [-c, c]) add(new THREE.CylinderGeometry(r * 0.75, r * 0.75, out, 14), q.v ? x : x + k, q.v ? y + k : y, front + out / 2, Math.PI / 2);
      }
    }
  }
  return g;
}

function buildPart(f, uid, part, depth, carcassColor) {
  const out = new THREE.Group();
  const w = part.s1 - part.s0, h = part.z1 - part.z0;
  const front = f.mirror ? mirrorMat : imageMat(part.img, { rough: 0.45, gloss: part.gloss });
  const edge = new THREE.MeshStandardMaterial({ color: part.ec ?? 0xdedbd4, roughness: 0.6 }); // chant de la façade
  const back = f.machine
    ? new THREE.MeshStandardMaterial({ color: 0xc9ced2, metalness: 0.5, roughness: 0.36 })
    : new THREE.MeshStandardMaterial({ color: carcassColor, roughness: 0.7 });
  let panel;
  if (part.glass && !f.mirror) {
    panel = glassPanel(w, h, part.glass, front, edge, uid, part.muntins);
  } else {
    // jeu réel entre deux façades : 1,5 mm de chaque côté
    const geo = new THREE.BoxGeometry(Math.max(0.01, w * S - 0.003), Math.max(0.01, h * S - 0.003), 0.018);
    panel = new THREE.Mesh(geo, [edge, edge, edge, edge, front, back]);
    panel.castShadow = panel.receiveShadow = true;
  }
  panel.userData.uid = uid;
  // repère fixe (orientation du mur, point d'articulation) puis pivot animé en local
  const frame = new THREE.Group();
  frame.applyMatrix4(wallBasis(f));
  const pivot = new THREE.Group();
  frame.add(pivot);
  let local;
  if (part.kind === 'door') {
    const hingeS = part.hinge === 'left' ? part.s0 : part.s1;
    frame.position.copy(onWall(f, hingeS, f.t, (part.z0 + part.z1) / 2));
    local = new THREE.Vector3((part.hinge === 'left' ? w / 2 : -w / 2) * S, 0, -0.009);
  } else if (part.kind === 'flapUp') {
    frame.position.copy(onWall(f, (part.s0 + part.s1) / 2, f.t, part.z1));
    local = new THREE.Vector3(0, -h / 2 * S, -0.009);
  } else if (part.kind === 'flapDown') {
    frame.position.copy(onWall(f, (part.s0 + part.s1) / 2, f.t, part.z0));
    local = new THREE.Vector3(0, h / 2 * S, -0.009);
  } else {
    frame.position.copy(onWall(f, (part.s0 + part.s1) / 2, f.t, (part.z0 + part.z1) / 2));
    local = new THREE.Vector3(0, 0, -0.009);
  }
  panel.position.copy(local);
  pivot.add(panel);
  if (f.machine && part.kind === 'flapDown') {
    // contre-porte : épaisseur inox, bandeau et bac à produit
    const inner = (bw, bh, bd, x, y, z, color, metal = 0.5) => {
      const o = new THREE.Mesh(new THREE.BoxGeometry(bw * S, bh * S, bd * S), new THREE.MeshStandardMaterial({ color, metalness: metal, roughness: 0.4 }));
      o.position.set(local.x + x * S, local.y + y * S, local.z + (z - 9) * S);
      o.castShadow = o.receiveShadow = true;
      o.userData.uid = uid;
      pivot.add(o);
    };
    inner(w - 14, h - 20, 2, 0, 0, -1.5, 0xc9ced2);
    inner(w - 60, 44, 3, 0, h / 2 - 34, -2.5, 0x2d3135, 0.2);
    inner(170, 120, 10, w * 0.12, 10, -6, 0x9aa1a7, 0.3);
    inner(60, 90, 12, w * 0.12 - 40, 10, -8, 0xe9ecee, 0.1);
  }
  if (part.grips) {
    const grips = buildGrips(part.grips, w, h, uid);
    grips.position.copy(local);
    if (part.frame) grips.position.z += 0.006; // posées sur le cadre
    pivot.add(grips);
  }
  if (part.frame && !f.mirror) {
    const relief = frameRelief(w, h, part.frame.w, part.frame.raised, front, edge, uid);
    relief.position.copy(local);
    pivot.add(relief);
  }
  out.add(frame);
  // intérieur (visible quand la case s'ouvre) et caisson du tiroir
  if (part.kind !== 'static' && part.inside) {
    const inside = new THREE.Mesh(new THREE.PlaneGeometry(w * S, h * S), imageMat(part.inside, { rough: 0.8 }));
    inside.applyMatrix4(wallBasis(f));
    // fond peint contre le dos du caisson creux (insideT : distance au mur), sinon juste derrière la façade
    const tIn = part.insideT != null ? f.t - depth + part.insideT + 0.5 : f.t - 19.5;
    inside.position.copy(onWall(f, (part.s0 + part.s1) / 2, tIn, (part.z0 + part.z1) / 2));
    inside.userData.uid = uid;
    out.add(inside);
  }
  if (part.kind === 'drawer') {
    const dd = Math.min(450, depth - 120);
    const boxMat = new THREE.MeshStandardMaterial({ color: carcassColor, roughness: 0.7, side: THREE.DoubleSide });
    const tray = new THREE.Group();
    const bw = (w - 50) * S, bh = Math.max(60, h - 70) * S, bd = dd * S;
    for (const [sx, sy, sz, px, py, pz] of [
      [bw, 0.012, bd, 0, -bh / 2, -bd / 2], // fond
      [0.012, bh, bd, -bw / 2, 0, -bd / 2], // côtés
      [0.012, bh, bd, bw / 2, 0, -bd / 2],
      [bw, bh, 0.012, 0, 0, -bd], // dos
    ]) {
      const m = new THREE.Mesh(new THREE.BoxGeometry(sx, sy, sz), boxMat);
      m.position.set(px, py, pz);
      m.castShadow = true;
      tray.add(m);
    }
    tray.position.set(0, -0.01, -0.02);
    pivot.add(tray);
  }
  if (part.kind !== 'static') doors.push({ uid, k: part.k ?? 0, pivot, kind: part.kind, hinge: part.hinge, depth, f, part });
  return out;
}

/** Lave-vaisselle intégrable derrière sa façade (repère du mur) : cuve inox, deux paniers garnis ; le panier bas sort avec la porte. */
function buildDishwasher(f, uid) {
  const q = f.machine;
  const g = new THREE.Group();
  g.applyMatrix4(wallBasis(f));
  g.position.copy(onWall(f, (q.s0 + q.s1) / 2, 0, q.z0));
  const m = new THREE.Group();
  m.scale.set(S, S, S); // mm ; x le long du mur, y vers le haut, z vers la pièce
  g.add(m);
  const w = q.s1 - q.s0 - 6, h = q.z1 - q.z0 - 6, zf = f.t - 22, z0 = 25;
  const steel = new THREE.MeshStandardMaterial({ color: 0xc3c8cc, metalness: 0.55, roughness: 0.34 });
  const shell = new THREE.MeshStandardMaterial({ color: 0x8c9297, metalness: 0.4, roughness: 0.5 });
  const wire = new THREE.MeshStandardMaterial({ color: 0xe4e7ea, metalness: 0.3, roughness: 0.4 });
  const dark = new THREE.MeshStandardMaterial({ color: 0x3a3f44, roughness: 0.7 });
  const china = new THREE.MeshStandardMaterial({ color: 0xf6f5f1, roughness: 0.3 });
  const blue = new THREE.MeshStandardMaterial({ color: 0x8fa9b8, roughness: 0.35 });
  const glass = new THREE.MeshStandardMaterial({ color: 0xdbeaf0, roughness: 0.1, transparent: true, opacity: 0.55 });
  const add = (parent, geo, mat, x, y, z, rx = 0, rz = 0) => {
    const o = new THREE.Mesh(geo, mat);
    o.position.set(x, y, z);
    o.rotation.set(rx, 0, rz);
    o.castShadow = o.receiveShadow = true;
    o.userData.uid = uid;
    parent.add(o);
    return o;
  };
  const box = (parent, x0, x1, y0, y1, za, zb, mat) => add(parent, new THREE.BoxGeometry(x1 - x0, y1 - y0, zb - za), mat, (x0 + x1) / 2, (y0 + y1) / 2, (za + zb) / 2);
  const hw = w / 2;
  // cuve : base (moteur), fond, côtés, dessus, dos
  box(m, -hw, hw, 0, 95, z0, zf - 30, dark);
  box(m, -hw, hw, 95, 103, z0, zf, steel);
  box(m, -hw, -hw + 20, 103, h, z0, zf, steel);
  box(m, hw - 20, hw, 103, h, z0, zf, steel);
  box(m, -hw, hw, h - 18, h, z0, zf, shell);
  box(m, -hw + 20, hw - 20, 103, h - 18, z0, z0 + 10, steel);
  box(m, -hw + 20, hw - 20, h - 24, h - 18, zf - 10, zf, dark); // joint
  if (q.empty) return g;
  // bras de lavage
  box(m, -hw + 70, hw - 70, 112, 122, (z0 + zf) / 2 - 20, (z0 + zf) / 2 + 20, dark);
  const rw = w - 56, rd = zf - z0 - 60;
  const rack = (parent, y, hh) => {
    const R = 2.2;
    const barX = (yy, z, len = rw) => add(parent, new THREE.CylinderGeometry(R, R, len, 6), wire, 0, yy, z, 0, Math.PI / 2);
    const barZ = (x, yy) => add(parent, new THREE.CylinderGeometry(R, R, rd, 6), wire, x, yy, z0 + 30 + rd / 2, Math.PI / 2);
    for (const yy of [y, y + hh / 2, y + hh]) {
      barX(yy, z0 + 30);
      barX(yy, z0 + 30 + rd);
      barZ(-rw / 2, yy);
      barZ(rw / 2, yy);
    }
    const n = Math.max(4, Math.round(rw / 70));
    for (let i = 1; i < n; i++) barZ(-rw / 2 + (rw * i) / n, y);
    for (let i = 0; i <= n; i++) for (const z of [z0 + 30, z0 + 30 + rd]) add(parent, new THREE.CylinderGeometry(R, R, hh, 6), wire, -rw / 2 + (rw * i) / n, y + hh / 2, z);
    box(parent, -rw / 2, rw / 2, y + hh - 4, y + hh + 14, z0 + 28 + rd, z0 + 38 + rd, shell); // poignée du panier
  };
  // panier haut : verres et tasses
  const top = new THREE.Group();
  m.add(top);
  const ty = 103 + (h - 103) * 0.56;
  rack(top, ty, 110);
  const nx = Math.max(3, Math.floor(rw / 95));
  for (let i = 0; i < nx; i++) for (let j = 0; j < 4; j++) {
    const x = -rw / 2 + (rw * (i + 0.5)) / nx, z = z0 + 30 + (rd * (j + 0.5)) / 4;
    if ((i + j) % 3 === 2) add(top, new THREE.CylinderGeometry(30, 38, 70, 18), j % 2 ? blue : china, x, ty + 40, z);
    else add(top, new THREE.CylinderGeometry(26, 33, 100, 18), glass, x, ty + 54, z);
  }
  // panier bas : assiettes debout et panier à couverts, sur glissière
  const slide = new THREE.Group();
  m.add(slide);
  const by = 128;
  rack(slide, by, 120);
  const np = Math.max(4, Math.floor(rd / 62));
  for (const side of [-1, 1]) for (let i = 0; i < np; i++) {
    if (side === 1 && i < 2) continue;
    const r = Math.min(118, rw * 0.22);
    add(slide, new THREE.CylinderGeometry(r, r * 0.7, 10, 28), (i + (side > 0 ? 1 : 0)) % 4 === 3 ? blue : china, side * rw * 0.25, by + r + 6, z0 + 30 + (rd * (i + 0.5)) / np, Math.PI / 2 - 0.18);
  }
  box(slide, rw * 0.1, rw * 0.42, by + 8, by + 110, z0 + 40, z0 + 130, dark);
  for (let i = 0; i < 7; i++) box(slide, rw * 0.13 + i * rw * 0.038, rw * 0.13 + i * rw * 0.038 + 7, by + 60, by + 190, z0 + 60 + (i % 3) * 22, z0 + 63 + (i % 3) * 22, steel);
  doors.push({ uid, k: 0, pivot: slide, kind: 'rack', travel: rd * 0.55, follows: true });
  return g;
}

function buildItem(d, uid) {
  const g = new THREE.Group();
  for (const s of d.solids.filter((x) => x.uid === uid)) {
    const m = boxMesh(s, s.mat);
    if (m) {
      m.userData.uid = uid;
      g.add(m);
    }
  }
  const carcassColor = new THREE.Color(d.solids.find((x) => x.uid === uid)?.mat?.color ?? '#f2f1ee');
  for (const f of d.fronts.filter((x) => x.uid === uid)) {
    for (const part of f.parts) g.add(buildPart(f, uid, part, f.depth, carcassColor));
    if (f.machine) g.add(buildDishwasher(f, uid));
  }
  return g;
}

// ------------------------------------------------------------------ regroupement des pièces fixes

// Un caisson est fait de boîtes dont chaque face a son matériau : sans regroupement, plus de 3 000
// appels de dessin par image pour une grande cuisine. Les pièces fixes d'un meuble sont fusionnées
// par matériau (un appel par matière) ; les portes, tiroirs et abattants (animés) restent à part.
const mergedMats = new Map(); // clé de matière → matériau commun (jamais libéré)
const canonTex = new Map(); // image source → texture sans répétition (la répétition passe dans les UV)

function canonical(t) {
  const k = t.source.uuid + '|' + t.colorSpace;
  let c = canonTex.get(k);
  if (!c) {
    c = t.clone();
    c.repeat.set(1, 1);
    c.offset.set(0, 0);
    c.rotation = 0;
    c.center.set(0, 0);
    c.wrapS = c.wrapT = THREE.RepeatWrapping;
    c.needsUpdate = true;
    canonTex.set(k, c);
  }
  return c;
}

/** Clé de matière (null : ne pas fusionner). */
function matKey(m) {
  if (!m || !m.isMeshStandardMaterial) return null;
  if (m.normalMap || m.roughnessMap || m.metalnessMap || m.aoMap || m.alphaMap || m.bumpMap || m.emissiveMap || m.lightMap) return null;
  const ph = m.isMeshPhysicalMaterial ? [m.clearcoat, m.clearcoatRoughness, m.transmission, m.ior, m.sheen] : '';
  return [m.type, m.color.getHexString(), m.roughness, m.metalness, m.map ? m.map.source.uuid + m.map.colorSpace : '',
    m.transparent, m.opacity, m.side, m.emissive.getHexString(), m.emissiveIntensity, m.depthWrite, m.envMapIntensity,
    m.alphaTest, m.polygonOffset, m.flatShading, ph].join('|');
}

function sharedMat(m, key) {
  let c = mergedMats.get(key);
  if (!c) {
    c = m.clone();
    if (m.map) c.map = canonical(m.map);
    c.userData.cached = true;
    mergedMats.set(key, c);
  }
  return c;
}

/** Tranche [start, start+count) d'une géométrie non indexée : position, normale, UV (null si autre format). */
function slice(geo, start, count) {
  const out = new THREE.BufferGeometry();
  for (const name of ['position', 'normal', 'uv']) {
    const a = geo.attributes[name];
    if (!a || a.isInterleavedBufferAttribute || !(a.array instanceof Float32Array)) return null;
    out.setAttribute(name, new THREE.BufferAttribute(a.array.slice(start * a.itemSize, (start + count) * a.itemSize), a.itemSize));
  }
  return out;
}

/** Fusionne les pièces fixes de [root] par matériau ; [moving] : pivots animés à laisser tels quels. */
function bakeStatic(root, moving = new Set()) {
  root.updateMatrixWorld(true);
  const inv = new THREE.Matrix4().copy(root.matrixWorld).invert();
  const buckets = new Map(); // clé → { mat, geos, cast, receive, uid }
  const removed = [];
  root.traverse((o) => {
    if (!o.isMesh || o.isInstancedMesh || o.isSkinnedMesh || o.userData.cached || o.userData.noMerge) return;
    for (let a = o.parent; a && a !== root; a = a.parent) if (moving.has(a) || a.userData.door) return;
    const mats = Array.isArray(o.material) ? o.material : [o.material];
    const geo0 = o.geometry;
    if (!geo0.attributes.position || geo0.morphAttributes.position) return;
    const geo = geo0.index ? geo0.toNonIndexed() : geo0;
    const n = geo.attributes.position.count;
    const groups = Array.isArray(o.material) && geo0.groups.length ? geo0.groups : [{ start: 0, count: n, materialIndex: 0 }];
    const parts = [];
    for (const gr of groups) {
      const m = mats[gr.materialIndex ?? 0];
      const key = matKey(m);
      if (key === null) return; // une face non fusionnable : la pièce reste entière
      const count = Math.min(gr.count, n - gr.start);
      if (count <= 0) continue;
      const part = slice(geo, gr.start, count);
      if (!part) return;
      parts.push([m, key, part]);
    }
    const rel = new THREE.Matrix4().multiplyMatrices(inv, o.matrixWorld);
    for (const [m, key, part] of parts) {
      part.applyMatrix4(rel);
      // répétition et rotation de la texture reportées dans les UV
      if (m.map) {
        m.map.updateMatrix();
        const uv = part.attributes.uv, e = m.map.matrix.elements;
        for (let i = 0; i < uv.count; i++) {
          const u = uv.getX(i), v = uv.getY(i);
          uv.setXY(i, e[0] * u + e[3] * v + e[6], e[1] * u + e[4] * v + e[7]);
        }
      }
      const bkey = key + '|' + o.castShadow + '|' + o.receiveShadow;
      let b = buckets.get(bkey);
      if (!b) buckets.set(bkey, (b = { mat: sharedMat(m, key), geos: [], cast: o.castShadow, receive: o.receiveShadow, uid: o.userData.uid }));
      b.geos.push(part);
      if (b.uid !== o.userData.uid) b.uid = undefined;
    }
    if (geo !== geo0) geo.dispose();
    removed.push(o);
  });
  if (!removed.length) return root;
  const kept = new Set();
  for (const o of removed) o.parent.remove(o);
  root.traverse((o) => {
    if (o.geometry) kept.add(o.geometry);
  });
  for (const o of removed) if (!kept.has(o.geometry)) o.geometry.dispose();
  for (const b of buckets.values()) {
    const geo = b.geos.length === 1 ? b.geos[0] : mergeGeometries(b.geos, false);
    if (b.geos.length > 1) for (const g of b.geos) g.dispose();
    if (!geo) continue;
    const m = new THREE.Mesh(geo, b.mat);
    m.castShadow = b.cast;
    m.receiveShadow = b.receive;
    if (b.uid) m.userData.uid = b.uid;
    root.add(m); // géométrie déjà dans le repère du groupe
  }
  return root;
}

function buildOthers(d) {
  const g = new THREE.Group();
  for (const s of d.solids.filter((x) => !x.uid)) {
    const m = boxMesh(s, s.mat);
    if (m) g.add(m);
  }
  for (const t of d.tops) {
    const w = t.x1 - t.x0, h = t.y1 - t.y0;
    const m = new THREE.Mesh(new THREE.PlaneGeometry(w * S, h * S), imageMat(t.img, { rough: 0.25 }));
    m.rotation.x = -Math.PI / 2;
    m.position.copy(P((t.x0 + t.x1) / 2, (t.y0 + t.y1) / 2, t.z1 + 0.6));
    m.receiveShadow = true;
    g.add(m);
  }
  return g;
}

/** Éclairage : rubans LED lumineux, et sous les hauts un spot doux par élément. */
function buildLights(d) {
  const g = new THREE.Group();
  const led = new THREE.MeshStandardMaterial({ color: 0xfff1d6, emissive: 0xffe2b0, emissiveIntensity: 2.2 });
  for (const l of d.lights || []) {
    const sx = l.x1 - l.x0, sy = l.z1 - l.z0, sz = l.y1 - l.y0;
    if (sx <= 0 || sy <= 0 || sz <= 0) continue;
    const m = new THREE.Mesh(new THREE.BoxGeometry(sx * S, sy * S, sz * S), led);
    m.position.copy(P((l.x0 + l.x1) / 2, (l.y0 + l.y1) / 2, (l.z0 + l.z1) / 2));
    g.add(m);
    if (l.spot) {
      const sp = new THREE.SpotLight(0xffd9a0, 3.2, 1.6, Math.PI / 3, 0.7, 1.4);
      sp.position.copy(P(l.px, l.py, l.pz));
      sp.target.position.copy(P(l.px, l.py, l.pz - 600));
      g.add(sp, sp.target);
    }
  }
  return g;
}

// ------------------------------------------------------------------ objets de la pièce

// modèles 3D du catalogue et importés (glTF, GLB, OBJ, 3DS) : chargés à la demande et mis en cache
let gltfLoader = null;
let objLoader = null;
let tdsLoader = null;
const modelCache = new Map(); // fichier → Promise<THREE.Object3D>

function loadModel(file) {
  if (!modelCache.has(file)) {
    modelCache.set(file, (async () => {
      const lower = file.toLowerCase();
      if (lower.endsWith('.obj')) {
        if (!objLoader) {
          const { OBJLoader } = await import('./vendor/loaders/OBJLoader.js');
          objLoader = new OBJLoader();
        }
        const obj = await objLoader.loadAsync(file);
        // Assurer des matériaux et des ombres par défaut pour les objets OBJ simples
        obj.traverse((child) => {
          if (child.isMesh) {
            child.castShadow = child.receiveShadow = true;
            if (!child.material || child.material.isMeshBasicMaterial) {
              child.material = new THREE.MeshStandardMaterial({ color: 0xdcdcdc, roughness: 0.45, metalness: 0.1 });
            }
          }
        });
        return obj;
      } else if (lower.endsWith('.3ds')) {
        if (!tdsLoader) {
          const { TDSLoader } = await import('./vendor/loaders/TDSLoader.js');
          tdsLoader = new TDSLoader();
        }
        const obj3ds = await tdsLoader.loadAsync(file);
        obj3ds.traverse((child) => {
          if (child.isMesh) {
            child.castShadow = child.receiveShadow = true;
            if (!child.material) {
              child.material = new THREE.MeshStandardMaterial({ color: 0xdcdcdc, roughness: 0.45, metalness: 0.1 });
            }
          }
        });
        return obj3ds;
      } else {
        if (!gltfLoader) {
          const { GLTFLoader } = await import('./vendor/loaders/GLTFLoader.js');
          gltfLoader = new GLTFLoader();
        }
        const g = await gltfLoader.loadAsync(file);
        return g.scene;
      }
    })());
  }
  return modelCache.get(file);
}

// matériaux des sanitaires : céramique émaillée (vernis brillant), robinetterie, verre
const ceramic = new THREE.MeshPhysicalMaterial({ color: 0xf8f8f6, roughness: 0.22, clearcoat: 1, clearcoatRoughness: 0.08 });
const ceramicIn = new THREE.MeshPhysicalMaterial({ color: 0xf1f2f2, roughness: 0.18, clearcoat: 1, clearcoatRoughness: 0.05, side: THREE.DoubleSide });
const chrome = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.07, metalness: 1 });
const tapBlack = new THREE.MeshStandardMaterial({ color: 0x1f2022, roughness: 0.42, metalness: 0.2 });
const tapGold = new THREE.MeshStandardMaterial({ color: 0xd4af37, roughness: 0.18, metalness: 0.85 });
const tapSteel = new THREE.MeshStandardMaterial({ color: 0xcccccc, roughness: 0.28, metalness: 0.8 });

function getTapMat(d) {
  const fin = (d && d.style && d.style.faucet_finish) || 'chrome';
  if (fin === 'noir_mat') return tapBlack;
  if (fin === 'or_brosse' || fin === 'laiton') return tapGold;
  if (fin === 'inox_brosse') return tapSteel;
  return chrome;
}
const glass = new THREE.MeshPhysicalMaterial({ color: 0xeaf6f8, roughness: 0.03, metalness: 0, transparent: true, opacity: 0.22, clearcoat: 1, side: THREE.DoubleSide, depthWrite: false });
const greyMat = new THREE.MeshStandardMaterial({ color: 0xb9bcbd, roughness: 0.55 });
const darkMat = new THREE.MeshStandardMaterial({ color: 0x2c2f33, roughness: 0.4 });

/** Pavé en repère local (mm) : x centré sur la largeur, y depuis le bas, z du dos (0) vers l'avant. */
function lbox(g, mat, x0, x1, y0, y1, z0, z1) {
  const m = new THREE.Mesh(new THREE.BoxGeometry((x1 - x0) * S, (y1 - y0) * S, (z1 - z0) * S), mat);
  m.position.set((x0 + x1) / 2 * S, (y0 + y1) / 2 * S, (z0 + z1) / 2 * S);
  m.castShadow = m.receiveShadow = true;
  g.add(m);
  return m;
}
function lcyl(g, mat, cx, y0, y1, cz, r, seg = 32) {
  const m = new THREE.Mesh(new THREE.CylinderGeometry(r * S, r * S, (y1 - y0) * S, seg), mat);
  m.position.set(cx * S, (y0 + y1) / 2 * S, cz * S);
  m.castShadow = m.receiveShadow = true;
  g.add(m);
  return m;
}
/** Tube horizontal le long de x. */
function ltubeX(g, mat, x0, x1, y, z, r) {
  const m = new THREE.Mesh(new THREE.CylinderGeometry(r * S, r * S, (x1 - x0) * S, 20), mat);
  m.rotation.z = Math.PI / 2;
  m.position.set((x0 + x1) / 2 * S, y * S, z * S);
  m.castShadow = true;
  g.add(m);
  return m;
}

// ---- formes : tout est construit en mm dans un groupe mis à l'échelle
function mesh(geo, mat) {
  const m = new THREE.Mesh(geo, mat);
  m.castShadow = m.receiveShadow = true;
  return m;
}
/** Point d'une super-ellipse (n = 2 : ellipse, n grand : rectangle aux angles arrondis). */
function se(t, n) {
  const c = Math.cos(t), s = Math.sin(t);
  return [Math.sign(c) * Math.pow(Math.abs(c), 2 / n), Math.sign(s) * Math.pow(Math.abs(s), 2 / n)];
}
/** Contour super-elliptique en plan (x, z) → points de forme (x, -z), centre (cx, cz), demi-axes (a, b). */
function sePath(path, cx, cz, a, b, n, seg = 64, reverse = false) {
  for (let i = 0; i <= seg; i++) {
    const t = (reverse ? -1 : 1) * i / seg * Math.PI * 2;
    const [u, v] = se(t, n);
    const x = cx + a * u, y = -(cz + b * v);
    if (i === 0) path.moveTo(x, y);
    else path.lineTo(x, y);
  }
  return path;
}
function roundRectPath(path, x0, z0, x1, z1, r) {
  const y0 = -z1, y1 = -z0; // la forme est dans (x, -z)
  path.moveTo(x0 + r, y0);
  path.lineTo(x1 - r, y0);
  path.quadraticCurveTo(x1, y0, x1, y0 + r);
  path.lineTo(x1, y1 - r);
  path.quadraticCurveTo(x1, y1, x1 - r, y1);
  path.lineTo(x0 + r, y1);
  path.quadraticCurveTo(x0, y1, x0, y1 - r);
  path.lineTo(x0, y0 + r);
  path.quadraticCurveTo(x0, y0, x0 + r, y0);
  return path;
}
/** Extrusion verticale d'une forme du plan, de y0 à y0 + h, arêtes adoucies. */
function extrudeUp(shape, y0, h, bevel = 0) {
  const geo = new THREE.ExtrudeGeometry(shape, {
    depth: Math.max(1, h - 2 * bevel),
    bevelEnabled: bevel > 0,
    bevelThickness: bevel,
    bevelSize: bevel,
    bevelSegments: 4,
    curveSegments: 32,
  });
  geo.rotateX(-Math.PI / 2); // (x, y, profondeur) → (x, z, y) : y de forme = -z
  geo.translate(0, y0 + bevel, 0);
  geo.computeVertexNormals();
  return geo;
}
/** Cuve : demi super-ellipsoïde ouverte vers le haut (bord en y = top), fond aplati. */
function bowl(cx, cz, a, b, depth, top, n = 4, flat = 0.35) {
  const geo = new THREE.SphereGeometry(1, 64, 24, 0, Math.PI * 2, Math.PI / 2, Math.PI / 2);
  const p = geo.attributes.position;
  for (let i = 0; i < p.count; i++) {
    const x = p.getX(i), y = p.getY(i), z = p.getZ(i);
    const rho = Math.hypot(x, z);
    const t = Math.atan2(z, x);
    const [u, v] = se(t, n);
    // fond plat : la profondeur plafonne
    const yy = -Math.min(1, -y / (1 - flat)) * depth;
    p.setXYZ(i, cx + a * rho * u, top + yy, cz + b * rho * v);
  }
  geo.computeVertexNormals();
  return geo;
}

function mixer(m, x, y, z, spout = 150, toward = 1, mat = chrome) {
  mixerRealistic(m, x, y, z, { mat, toward, swan: true, height: spout + 150 });
}

function mixerRealistic(m, x, y, z, options = {}) {
  const toward = options.toward !== undefined ? options.toward : 1;
  const mat = options.mat || chrome;
  const height = options.height || 360;
  const isSpring = options.spring === true;
  const isSquare = options.square === true;
  const lever = options.faucetLever || 'side_pin';

  // Base collet
  m.add(at(mesh(new THREE.CylinderGeometry(24, 26, 12, 32), mat), x, y + 6, z));
  // Corps principal
  const bodyH = isSpring ? 180 : 130;
  m.add(at(mesh(new THREE.CylinderGeometry(20, 20, bodyH, 32), mat), x, y + 12 + bodyH / 2, z));

  if (lever === 'side_flat') {
    // Manette ergonomique plate / palette contemporaine
    const leverHub = mesh(new THREE.CylinderGeometry(14, 14, 22, 24), mat);
    leverHub.rotation.z = Math.PI / 2;
    leverHub.position.set(x + 22, y + 60, z);
    m.add(leverHub);
    const flatBlade = mesh(new THREE.BoxGeometry(7, 65, 16), mat);
    flatBlade.position.set(x + 35, y + 80, z - 8 * toward);
    flatBlade.rotation.x = -0.3 * toward;
    flatBlade.rotation.z = -0.35;
    m.add(flatBlade);
  } else if (lever === 'top_lever') {
    // Levier supérieur incliné vers l'avant sur le col
    const topCap = mesh(new THREE.CylinderGeometry(16, 18, 14, 28), mat);
    topCap.position.set(x, y + 12 + bodyH + 4, z + toward * 16);
    topCap.rotation.x = 0.25 * toward;
    m.add(topCap);
    const topPin = mesh(new THREE.BoxGeometry(8, 10, 65), mat);
    topPin.position.set(x, y + 12 + bodyH + 12, z + toward * 42);
    topPin.rotation.x = -0.15 * toward;
    m.add(topPin);
  } else if (lever === 'retro_cross') {
    // Double commande rétro croisillons / têtes étoiles latérales
    for (const sx of [-1, 1]) {
      const armX = x + sx * 45;
      const arm = mesh(new THREE.CylinderGeometry(8, 8, 30, 16), mat);
      arm.rotation.z = Math.PI / 2;
      arm.position.set(x + sx * 25, y + 55, z);
      m.add(arm);
      const crossHub = mesh(new THREE.CylinderGeometry(10, 10, 14, 20), mat);
      crossHub.rotation.z = Math.PI / 2;
      crossHub.position.set(armX, y + 55, z);
      m.add(crossHub);
      const c1 = mesh(new THREE.BoxGeometry(6, 32, 6), mat);
      c1.position.set(armX, y + 55, z);
      const c2 = mesh(new THREE.BoxGeometry(6, 6, 32), mat);
      c2.position.set(armX, y + 55, z);
      m.add(c1, c2);
    }
  } else {
    // Manette latérale tige fine (par défaut)
    const leverHub = mesh(new THREE.CylinderGeometry(13, 13, 26, 24), mat);
    leverHub.rotation.z = Math.PI / 2;
    leverHub.position.set(x + 22, y + 60, z);
    m.add(leverHub);
    const leverPin = mesh(new THREE.CylinderGeometry(4, 5, 65, 16), mat);
    leverPin.position.set(x + 35, y + 80, z - 10 * toward);
    leverPin.rotation.x = -0.3 * toward;
    leverPin.rotation.z = -0.35;
    m.add(leverPin);
  }

  if (isSpring) {
    // Mitigeur chef pro à ressort hélicoïdal
    const topBar = mesh(new THREE.CylinderGeometry(8, 8, 140, 20), mat);
    topBar.rotation.x = Math.PI / 2;
    topBar.position.set(x, y + 210, z + toward * 70);
    m.add(topBar);
    const curve = new THREE.CatmullRomCurve3([
      new THREE.Vector3(x, y + 180, z),
      new THREE.Vector3(x, y + height - 40, z + toward * 30),
      new THREE.Vector3(x, y + height, z + toward * 90),
      new THREE.Vector3(x, y + height - 70, z + toward * 150),
      new THREE.Vector3(x, y + height - 160, z + toward * 155),
    ]);
    const hose = mesh(new THREE.TubeGeometry(curve, 32, 7, 16, false), darkMat);
    m.add(hose);
    const springCurve = new THREE.CatmullRomCurve3([
      new THREE.Vector3(x, y + 180, z),
      new THREE.Vector3(x, y + height - 45, z + toward * 28),
      new THREE.Vector3(x, y + height - 5, z + toward * 88),
      new THREE.Vector3(x, y + height - 80, z + toward * 148),
    ]);
    const springTube = mesh(new THREE.TubeGeometry(springCurve, 28, 11, 12, false), mat);
    m.add(springTube);
    const wand = mesh(new THREE.CylinderGeometry(14, 18, 70, 24), mat);
    wand.position.set(x, y + height - 170, z + toward * 155);
    m.add(wand);
  } else if (isSquare) {
    // Bec carré contemporain biseauté
    const vLen = height - 130;
    const vBeam = mesh(new THREE.BoxGeometry(22, vLen, 22), mat);
    vBeam.position.set(x, y + 130 + vLen / 2, z);
    m.add(vBeam);
    const hLen = 170;
    const hBeam = mesh(new THREE.BoxGeometry(22, 22, hLen), mat);
    hBeam.position.set(x, y + height, z + toward * hLen / 2);
    m.add(hBeam);
    const drop = mesh(new THREE.BoxGeometry(22, 40, 22), mat);
    drop.position.set(x, y + height - 20, z + toward * (hLen - 11));
    m.add(drop);
    m.add(at(mesh(new THREE.CylinderGeometry(9, 9, 8, 20), chrome), x, y + height - 42, z + toward * (hLen - 11)));
  } else {
    // Col de cygne épuré (Swan neck fluide)
    const reach = 190;
    const curve = new THREE.CatmullRomCurve3([
      new THREE.Vector3(x, y + 120, z),
      new THREE.Vector3(x, y + height * 0.75, z + toward * 15),
      new THREE.Vector3(x, y + height, z + toward * 85),
      new THREE.Vector3(x, y + height * 0.92, z + toward * (reach - 25)),
      new THREE.Vector3(x, y + height * 0.72, z + toward * reach),
    ]);
    const spout = mesh(new THREE.TubeGeometry(curve, 32, 11, 20, false), mat);
    m.add(spout);
    const aerator = mesh(new THREE.CylinderGeometry(12, 11, 20, 24), mat);
    aerator.position.set(x, y + height * 0.72 - 8, z + toward * reach);
    m.add(aerator);
  }
}

/** Sanitaire en volume, aux cotes de l'objet (w, h, d), le dos en z = 0 (contre le mur). */
/** Lave-linge ou sèche-linge à hublot (mm, dos à z = 0) : caisse, bandeau, tiroir à lessive ou réservoir, hublot. */
function frontLoader(m, type, y0, w, h, d) {
  const dryer = type.startsWith('sl_'), built = type === 'll_encastrable';
  const g = new THREE.Group();
  g.position.y = y0;
  m.add(g);
  const white = new THREE.MeshPhysicalMaterial({ color: 0xf7f7f6, roughness: 0.38, clearcoat: 0.4 });
  const add = (geo, mat, x, y, z, rx = 0) => {
    const q = mesh(geo, mat);
    q.position.set(x, y, z);
    q.rotation.x = rx;
    g.add(q);
    return q;
  };
  const hw = w / 2, bar = Math.min(125, h * 0.15), depth = d - 22;
  add(new THREE.BoxGeometry(w - 6, h - 24, depth), white, 0, 12 + h / 2, depth / 2);
  add(new THREE.BoxGeometry(w - 4, 16, depth + 4), white, 0, h - 8, depth / 2); // dessus
  for (const x of [-hw + 50, hw - 50]) for (const z of [50, depth - 50]) add(new THREE.CylinderGeometry(20, 20, 24, 16), darkMat, x, 12, z);
  add(new THREE.BoxGeometry(w - 30, 70, 3), greyMat, 0, 60, depth + 1); // plinthe et trappe de filtre
  add(new THREE.BoxGeometry(90, 56, 4), white, -hw + 80, 60, depth + 3);
  // bandeau : tiroir (ou réservoir d'eau), programmateur, écran
  add(new THREE.BoxGeometry(w - 6, bar, 8), white, 0, h - 16 - bar / 2, depth + 4);
  add(new THREE.BoxGeometry(w - 6, 2, 10), greyMat, 0, h - 17 - bar, depth + 4);
  add(new THREE.BoxGeometry(w * 0.27, bar * 0.66, 6), white, -hw + w * 0.17, h - 16 - bar / 2, depth + 9);
  add(new THREE.BoxGeometry(w * 0.12, 8, 10), greyMat, -hw + w * 0.17, h - 16 - bar * 0.32, depth + 12);
  add(new THREE.CylinderGeometry(Math.min(34, bar * 0.28), Math.min(36, bar * 0.3), 22, 40), chrome, w * 0.02, h - 16 - bar / 2, depth + 16, Math.PI / 2);
  add(new THREE.BoxGeometry(w * 0.26, bar * 0.4, 3), darkMat, w * 0.29, h - 16 - bar / 2, depth + 9);
  if (built) {
    // porte d'habillage prête à recevoir une façade
    add(new THREE.BoxGeometry(w - 30, h - bar - 130, 6), white, 0, (h - bar - 30) / 2 + 60, depth + 4);
  }
  const cy = (h - 16 - bar + 100) / 2, r = Math.min(w * 0.34, (h - bar - 130) * 0.44);
  const ring = new THREE.MeshStandardMaterial({ color: dryer ? 0xf2f2f1 : 0xd0d4d7, metalness: dryer ? 0.1 : 0.7, roughness: 0.3 });
  add(new THREE.TorusGeometry(r, r * 0.14, 20, 64), ring, 0, cy, depth + 6);
  add(new THREE.CylinderGeometry(r * 0.96, r * 0.96, 10, 56), new THREE.MeshStandardMaterial({ color: 0x23272b, roughness: 0.4 }), 0, cy, depth + 1, Math.PI / 2);
  const bowl = add(new THREE.SphereGeometry(r * 0.82, 40, 24, 0, Math.PI * 2, 0, Math.PI / 2), new THREE.MeshPhysicalMaterial({ color: 0x3c464d, roughness: 0.05, metalness: 0.1, clearcoat: 1, transparent: true, opacity: dryer ? 0.75 : 0.6 }), 0, cy, depth + 4, Math.PI / 2);
  bowl.scale.y = 0.22;
  // tambour visible derrière le verre
  const drum = add(new THREE.TorusGeometry(r * 0.5, r * 0.06, 12, 40), chrome, 0, cy, depth + 5);
  drum.scale.z = 0.4;
  add(new THREE.BoxGeometry(16, r * 0.5, 12), dryer ? greyMat : chrome, r * 1.06, cy, depth + 20); // poignée
  if (type === 'sl_pac') for (let i = 0; i < 6; i++) add(new THREE.BoxGeometry(w * 0.3, 4, 3), darkMat, w * 0.24, 40 + i * 9, depth + 4); // grille d'échange
  if (type === 'sl_evac') add(new THREE.CylinderGeometry(52, 52, 60, 28), greyMat, 0, 200, 10, Math.PI / 2); // sortie de gaine
  if (type === 'll_sechant') add(new THREE.BoxGeometry(w * 0.2, 10, 3), new THREE.MeshStandardMaterial({ color: 0xe08a3c, roughness: 0.5 }), w * 0.29, h - 16 - bar * 0.86, depth + 9);
}

function buildFixture(o, sceneData) {
  const g = new THREE.Group();
  g.renderOrder = 2;
  try {
    const m = new THREE.Group();
    m.scale.set(S, S, S); // contenu en mm
    g.add(m);
    const { w, h, d } = o;
    const hw = w / 2;
    const tapMat = getTapMat(sceneData);
    const enamel = () => new THREE.MeshPhysicalMaterial({ color: 0xfafafa, roughness: 0.35, clearcoat: 0.6 });
    const chromeSoft = () => new THREE.MeshStandardMaterial({ color: 0xc6cacd, metalness: 0.7, roughness: 0.35 });
    // piquages sous l'appareil, entraxe 2k, repères bleu (froide) et rouge (chaude)
    const pipes = (x, k, z) => {
      for (const [q, c] of [[x - k, 0x3f7fc4], [x + k, 0xc94f3f]]) {
        m.add(at(mesh(new THREE.CylinderGeometry(10, 10, 120, 18), chrome), q, -58, z));
        m.add(at(mesh(new THREE.CylinderGeometry(15, 15, 16, 18), new THREE.MeshStandardMaterial({ color: c, roughness: 0.5 })), q, -6, z));
      }
    };
    switch (o.type) {
    case 'wc_suspendu':
    case 'bidet':
    case 'wc_sol': {
      const floor = o.type === 'wc_sol';
      const seat = floor ? 400 : h; // dessus de l'abattant
      // contour en plan : dos large et droit, avant arrondi et plus étroit (forme d'œuf)
      const egg = (scale, cz0) => {
        const s = new THREE.Shape();
        const seg = 72;
        for (let i = 0; i <= seg; i++) {
          const t = i / seg * Math.PI * 2;
          const [u, v] = se(t, 2.6);
          const front = (v + 1) / 2; // 0 au dos, 1 devant
          const x = hw * scale * u * (1 - 0.22 * front);
          const z = cz0 + (d - cz0) * scale * (v + 1) / 2;
          if (i === 0) s.moveTo(x, -z);
          else s.lineTo(x, -z);
        }
        return s;
      };
      const z0 = floor ? d * 0.3 : 0;
      const bodyBottom = floor ? 0 : seat - 340;
      const body = extrudeUp(egg(1, z0), bodyBottom, seat - 30 - bodyBottom, 18);
      // cuvette resserrée vers le bas
      const p = body.attributes.position;
      const zc = z0 + (d - z0) * 0.45;
      for (let i = 0; i < p.count; i++) {
        const y = p.getY(i);
        const k = Math.min(1, Math.max(0, (y - bodyBottom) / (seat - 30 - bodyBottom)));
        const f = floor ? 0.55 + 0.45 * Math.pow(k, 0.6) : 0.72 + 0.28 * Math.pow(k, 0.5);
        p.setX(i, p.getX(i) * f);
        p.setZ(i, zc + (p.getZ(i) - zc) * (floor ? f : 1));
      }
      body.computeVertexNormals();
      m.add(mesh(body, ceramic));
      if (o.type === 'bidet') {
        // ouverture de la vasque et mitigeur
        const rim = egg(0.72, z0 + 40);
        m.add(mesh(extrudeUp(rim, seat - 32, 3, 0), new THREE.MeshStandardMaterial({ color: 0xdfe3e5, roughness: 0.2 })));
        mixer(m, 0, seat - 30, 70, 90, 1, tapMat);
      } else {
        // abattant fermé, légèrement débordant
        m.add(mesh(extrudeUp(egg(1.02, z0 - 5), seat - 30, 32, 10), ceramic));
        // charnières chromées
        lcylMM(m, -60, seat - 18, z0 + 30, 9, 40);
        lcylMM(m, 60, seat - 18, z0 + 30, 9, 40);
      }
      if (floor) {
        // réservoir attenant, angles arrondis, bouton poussoir
        const tank = roundRectPath(new THREE.Shape(), -hw * 0.92, 0, hw * 0.92, d * 0.3, 40);
        m.add(mesh(extrudeUp(tank, 380, h - 380, 14), ceramic));
        m.add(at(mesh(new THREE.CylinderGeometry(22, 22, 10, 32), chrome), 0, h + 2, d * 0.15));
      } else if (o.type === 'wc_suspendu') {
        // plaque de commande double touche, blanche bordée de chrome
        const plate = mesh(new THREE.BoxGeometry(246, 166, 10), chrome);
        plate.position.set(0, 1060, 5);
        m.add(plate);
        const face = mesh(new THREE.BoxGeometry(236, 156, 4), new THREE.MeshPhysicalMaterial({ color: 0xffffff, roughness: 0.15, clearcoat: 1 }));
        face.position.set(0, 1060, 11);
        m.add(face);
        const k1 = mesh(new THREE.BoxGeometry(76, 110, 4), chrome);
        k1.position.set(-45, 1060, 13);
        const k2 = mesh(new THREE.BoxGeometry(110, 110, 4), chrome);
        k2.position.set(50, 1060, 13);
        m.add(k1, k2);
      }
      break;
    }
    case 'lavabo':
    case 'vasque_double': {
      // plan-vasque en céramique : dessus percé d'une ou deux cuves, chant arrondi
      const n = o.type === 'vasque_double' ? 2 : 1;
      const top = h;
      const shape = roundRectPath(new THREE.Shape(), -hw, 0, hw, d, 30);
      const holes = [];
      for (let i = 0; i < n; i++) {
        const cx = -hw + w * (i + 0.5) / n;
        const a = Math.min(w / n * 0.36, 240), b = d * 0.3;
        holes.push([cx, d * 0.56, a, b]);
        shape.holes.push(sePath(new THREE.Path(), cx, d * 0.56, a, b, 3.2, 64, true));
      }
      m.add(mesh(extrudeUp(shape, top - 40, 40, 6), ceramic));
      // jupe sous le plan
      m.add(mesh(extrudeUp(roundRectPath(new THREE.Shape(), -hw + 15, 0, hw - 15, d - 15, 24), 0, top - 40, 0), ceramic));
      for (const [cx, cz, a, b] of holes) {
        m.add(mesh(bowl(cx, cz, a, b, Math.min(140, top - 20), top - 1, 3.2, 0.3), ceramicIn));
        // bonde
        m.add(at(mesh(new THREE.CylinderGeometry(20, 20, 3, 32), tapMat), cx, top - Math.min(140, top - 20) - 0.5, cz));
        mixer(m, cx, top, d * 0.12, 130, 1, tapMat);
      }
      // siphon sous le meuble
      m.add(at(mesh(new THREE.CylinderGeometry(16, 16, 260, 20), tapMat), 0, -130, d * 0.4));
      break;
    }
    case 'baignoire': {
      // tablier droit, rebord large, cuve arrondie à fond plat
      const rimSide = 75, rimEnd = 110;
      const outer = roundRectPath(new THREE.Shape(), -hw, 0, hw, d, 22);
      const a = hw - rimEnd, b = d / 2 - rimSide;
      outer.holes.push(sePath(new THREE.Path(), 0, d / 2, a, b, 5, 96, true));
      m.add(mesh(extrudeUp(outer, 0, h, 8), ceramic));
      m.add(mesh(bowl(0, d / 2, a, b, h - 70, h - 2, 5, 0.55), ceramicIn));
      // bonde et trop-plein
      m.add(at(mesh(new THREE.CylinderGeometry(26, 26, 3, 32), tapMat), -a * 0.7, 72, d / 2));
      const ov = mesh(new THREE.CylinderGeometry(30, 30, 6, 32), tapMat);
      ov.rotation.z = Math.PI / 2;
      ov.position.set(-a - 2, h - 150, d / 2);
      m.add(ov);
      // mitigeur sur le rebord, côté bonde, bec vers la cuve
      mixer(m, -hw + rimEnd / 2, h, d / 2 - 40, 0.01, 1, tapMat);
      const bec = mesh(new THREE.CylinderGeometry(12, 12, 130, 20), tapMat);
      bec.rotation.z = Math.PI / 2;
      bec.position.set(-hw + rimEnd / 2 + 65, h + 150, d / 2 - 40);
      m.add(bec);
      break;
    }
    case 'douche':
    case 'douche_italienne': {
      const tray = o.type === 'douche';
      const base = tray ? 35 : 6;
      if (tray) {
        // receveur extra-plat, léger creux, bonde chromée
        m.add(mesh(extrudeUp(roundRectPath(new THREE.Shape(), -hw, 0, hw, d, 10), 0, base, 4), ceramic));
        m.add(at(mesh(new THREE.CylinderGeometry(55, 55, 2, 40), chrome), 0, base + 0.5, d / 2));
      } else {
        // sol carrelé en pente, caniveau linéaire au fond
        m.add(mesh(new THREE.BoxGeometry(w, base, d), greyMat).translateY(base / 2).translateZ(d / 2));
        const drain = mesh(new THREE.BoxGeometry(w - 160, 2, 70), chrome);
        drain.position.set(0, base + 1, d * 0.88);
        m.add(drain);
      }
      // paroi en verre 8 mm avec profilé mural et barre de stabilisation chromés
      const H = h;
      if (tray) {
        const pw = w * 0.62;
        const gl = mesh(new THREE.BoxGeometry(pw, H - base, 8), glass);
        gl.castShadow = false;
        gl.position.set(-hw + pw / 2, base + (H - base) / 2, d - 6);
        m.add(gl);
        m.add(at(mesh(new THREE.BoxGeometry(22, H - base, 22), chrome), -hw + 11, base + (H - base) / 2, d - 6));
        const bar = mesh(new THREE.CylinderGeometry(9, 9, d, 20), chrome);
        bar.rotation.x = Math.PI / 2;
        bar.position.set(-hw + pw - 30, H - 10, d / 2);
        m.add(bar);
      } else {
        const pd = d * 0.8;
        const gl = mesh(new THREE.BoxGeometry(8, H - base, pd), glass);
        gl.castShadow = false;
        gl.position.set(hw - 6, base + (H - base) / 2, pd / 2);
        m.add(gl);
        m.add(at(mesh(new THREE.BoxGeometry(22, H - base, 22), chrome), hw - 6, base + (H - base) / 2, 11));
        const bar = mesh(new THREE.CylinderGeometry(9, 9, w * 0.5, 20), chrome);
        bar.rotation.z = Math.PI / 2;
        bar.position.set(hw - w * 0.25, H - 10, pd - 30);
        m.add(bar);
      }
      // colonne de douche : mitigeur thermostatique, barre, tête ronde, douchette
      const cx = tray ? hw * 0.2 : -hw * 0.2;
      m.add(at(mesh(new THREE.BoxGeometry(260, 70, 60), chrome), cx, 1100, 35));
      m.add(at(mesh(new THREE.CylinderGeometry(14, 14, 1050, 24), chrome), cx, 1100 + 525, 30));
      const arm = mesh(new THREE.CylinderGeometry(11, 11, 300, 20), chrome);
      arm.rotation.x = Math.PI / 2;
      arm.position.set(cx, 2140, 180);
      m.add(arm);
      m.add(at(mesh(new THREE.CylinderGeometry(125, 125, 10, 48), chrome), cx, 2125, 320));
      m.add(at(mesh(new THREE.CylinderGeometry(118, 118, 2, 48), darkMat), cx, 2119, 320));
      const hand = mesh(new THREE.CylinderGeometry(18, 13, 230, 24), chrome);
      hand.position.set(cx + 70, 1500, 55);
      m.add(hand);
      break;
    }
    case 'seche_serviettes': {
      // deux montants et barreaux ronds chromés
      lcylMM(m, -hw + 15, h / 2, d / 2, 15, h);
      lcylMM(m, hw - 15, h / 2, d / 2, 15, h);
      const n = Math.max(6, Math.round(h / 110));
      for (let i = 0; i < n; i++) {
        const y = 40 + (h - 80) * i / (n - 1);
        const bar = mesh(new THREE.CylinderGeometry(10, 10, w - 30, 20), chrome);
        bar.rotation.z = Math.PI / 2;
        bar.position.set(0, y, d / 2);
        m.add(bar);
      }
      // fixations murales
      for (const [x, y] of [[-hw + 15, 60], [hw - 15, 60], [-hw + 15, h - 60], [hw - 15, h - 60]]) {
        const f = mesh(new THREE.CylinderGeometry(9, 9, d / 2, 16), chrome);
        f.rotation.x = Math.PI / 2;
        f.position.set(x, y, d / 4);
        m.add(f);
      }
      break;
    }
    case 'deco_fruits': {
      // corbeille tressée et fruits
      const wood = new THREE.MeshStandardMaterial({ color: 0xa8794a, roughness: 0.8, side: THREE.DoubleSide });
      const pts = [[0.02, 0], [0.62, 0], [0.82, 0.25], [1, 0.62]].map(([r, y]) => new THREE.Vector2(r * hw, y * h * 0.75));
      const bowl = mesh(new THREE.LatheGeometry(pts, 36), wood);
      bowl.position.set(0, 0, d / 2);
      m.add(bowl);
      const fruits = [[0xd9432f, 38], [0xf2a11b, 40], [0x8db33a, 37], [0xf0c93a, 36], [0xc8312b, 37], [0xf19a1a, 39], [0x7fa636, 36]];
      fruits.forEach(([c, r], i) => {
        const f = mesh(new THREE.SphereGeometry(r, 20, 16), new THREE.MeshStandardMaterial({ color: c, roughness: 0.45 }));
        const a = (i / 6) * Math.PI * 2, k = i === 6 ? 0 : hw * 0.5;
        f.position.set(Math.cos(a) * k, h * 0.42 + (i === 6 ? 42 : (i % 2) * 8), d / 2 + Math.sin(a) * k);
        m.add(f);
      });
      break;
    }
    case 'deco_vaisselle': {
      // pile d'assiettes, bols, verres, pot : variés d'un niveau à l'autre
      const white = new THREE.MeshStandardMaterial({ color: 0xf4f1ea, roughness: 0.35 });
      const clay = new THREE.MeshStandardMaterial({ color: 0xb98864, roughness: 0.7 });
      const dark = new THREE.MeshStandardMaterial({ color: 0x55615c, roughness: 0.5 });
      const kind = Math.round(h) % 3, cz = d / 2, r = Math.min(105, d * 0.44);
      const cyl = (x, y0, rr, hh, mat, top = rr) => {
        const q = mesh(new THREE.CylinderGeometry(top, rr, hh, 26), mat);
        q.position.set(x, y0 + hh / 2, cz);
        m.add(q);
      };
      const plates = (x, count) => {
        for (let i = 0; i < count; i++) cyl(x, i * 11, r * 0.62, 8, white, r);
      };
      const bowls = (x, count, mat) => {
        for (let i = 0; i < count; i++) cyl(x, i * 26, r * 0.34, 46, mat, r * 0.66);
      };
      const cups = (x0, count) => {
        for (let i = 0; i < count; i++) cyl(x0 + i * 78, 0, 26, 84, kind === 1 ? glass : white, 32);
      };
      const span = hw - r;
      if (kind === 0) {
        plates(-span * 0.75, 6);
        bowls(span * 0.1, 3, clay);
        if (w > 420) cyl(span * 0.8, 0, 46, Math.min(170, h * 0.8), dark, 34);
      } else if (kind === 1) {
        cups(-span * 0.85, Math.max(2, Math.min(5, Math.floor(w / 130))));
        if (w > 460) plates(span * 0.75, 4);
      } else {
        cyl(-span * 0.7, 0, 55, Math.min(190, h * 0.85), clay, 40);
        bowls(span * 0.05, 2, white);
        if (w > 420) plates(span * 0.8, 5);
      }
      break;
    }
    case 'deco_lessive':
    case 'deco_savon':
    case 'deco_bougies': {
      const M = (c, rough = 0.5) => new THREE.MeshStandardMaterial({ color: c, roughness: rough });
      const cyl = (x, y0, r0, hh, mat, r1 = r0, z = d / 2) => {
        const q = mesh(new THREE.CylinderGeometry(r1, r0, hh, 28), mat);
        q.position.set(x, y0 + hh / 2, z);
        m.add(q);
      };
      if (o.type === 'deco_lessive') {
        // bidon, flacon d'adoucissant, bocal de pastilles
        for (const [x, bw, bh, c, cap] of [[-hw * 0.6, 92, h, 0x5f8fb0, 0xf2f2f0], [hw * 0.18, 72, h * 0.78, 0xa9c7a5, 0xe9e2d2]]) {
          const b = mesh(extrudeUp(roundRectPath(new THREE.Shape(), x - bw / 2, d / 2 - 34, x + bw / 2, d / 2 + 34, 22), 0, bh * 0.78, 8), M(c, 0.35));
          m.add(b);
          cyl(x, bh * 0.78, 24, bh * 0.2, M(cap, 0.4), 20);
          const lab = mesh(new THREE.BoxGeometry(bw * 0.62, bh * 0.3, 2), M(0xfafafa, 0.6));
          lab.position.set(x, bh * 0.4, d / 2 + 42);
          m.add(lab);
        }
        cyl(hw * 0.78, 0, 34, h * 0.42, glass);
        cyl(hw * 0.78, 4, 30, h * 0.26, M(0xf4f4f2, 0.7));
        cyl(hw * 0.78, h * 0.42, 36, 14, M(0xb98a55, 0.6));
      } else if (o.type === 'deco_savon') {
        // distributeur, gobelet et brosses, savon
        cyl(-hw * 0.62, 0, 34, h * 0.68, M(0x8a7f73, 0.4));
        cyl(-hw * 0.62, h * 0.68, 12, h * 0.16, chrome);
        const spout = mesh(new THREE.BoxGeometry(12, 10, 52), chrome);
        spout.position.set(-hw * 0.62, h * 0.86, d / 2 + 18);
        m.add(spout);
        cyl(hw * 0.1, 0, 34, h * 0.48, M(0xf1ede6, 0.4), 38);
        for (const [dx, c, tz] of [[-14, 0x4f86a8, 0.16], [12, 0xd98a6a, -0.14]]) {
          const b = mesh(new THREE.BoxGeometry(9, 180, 7), M(c, 0.4));
          b.position.set(hw * 0.1 + dx, h * 0.24 + 72, d / 2);
          b.rotation.z = tz;
          m.add(b);
        }
        cyl(hw * 0.72, 0, 46, 10, M(0xf1ede6, 0.4), 52);
        cyl(hw * 0.72, 10, 32, 22, M(0xe8d9b8, 0.6), 28);
      } else {
        for (const [x, r, hh, c] of [[-hw * 0.55, 40, h, 0xefe6d6], [hw * 0.2, 34, h * 0.68, 0xd8c3a5], [hw * 0.8, 28, h * 0.42, 0xb9a58c]]) {
          cyl(x, 0, r, hh * 0.9, M(c, 0.75));
          cyl(x, hh * 0.9, 1.6, 12, darkMat);
        }
      }
      break;
    }
    case 'deco_serviettes':
    case 'deco_panier':
    case 'deco_panier_linge':
    case 'deco_linge': {
      const tones = [0xf3efe8, 0xcdbfae, 0x9fb3a6, 0xd9a58a, 0x8fa4b5, 0xe6dccb];
      const cloth = (i) => new THREE.MeshStandardMaterial({ color: tones[((i % 6) + 6) % 6], roughness: 0.95 });
      const wicker = new THREE.MeshStandardMaterial({ color: 0xb08a5b, roughness: 0.9, side: THREE.DoubleSide });
      // pile de linge plié : plis arrondis à l'avant
      const pile = (x, y0, bw, bd, count, th, seed, z = d / 2) => {
        for (let i = 0; i < count; i++) {
          const b = Math.min(8, th * 0.3);
          const q = mesh(extrudeUp(roundRectPath(new THREE.Shape(), -bw / 2 + b, -bd / 2 + b, bw / 2 - b, bd / 2 - b, Math.min(18, bw * 0.12)), 0, th - 3, b), cloth(seed + i));
          q.position.set(x + ((i * 37 + seed * 11) % 9) - 4, y0 + i * th, z);
          m.add(q);
        }
      };
      const basket = (x, bw, bh, bd, z = d / 2) => {
        m.add(mesh(extrudeUp(roundRectPath(new THREE.Shape(), x - bw / 2, z - bd / 2, x + bw / 2, z + bd / 2, 30), 0, bh, 4), wicker));
        for (let i = 1; i < 6; i++) m.add(mesh(extrudeUp(roundRectPath(new THREE.Shape(), x - bw / 2 - 7, z - bd / 2 - 7, x + bw / 2 + 7, z + bd / 2 + 7, 32), bh * i / 6, 6, 0), wicker));
      };
      if (o.type === 'deco_serviettes') pile(0, 0, w * 0.92, d * 0.92, 4, h / 4, 0);
      else if (o.type === 'deco_panier') {
        basket(0, w * 0.94, h * 0.62, d * 0.94);
        pile(-w * 0.2, h * 0.62, w * 0.4, d * 0.7, 3, h * 0.12, 1);
        pile(w * 0.22, h * 0.62, w * 0.38, d * 0.7, 2, h * 0.13, 3);
      } else if (o.type === 'deco_panier_linge') {
        const z = d / 2;
        for (const [r0, r1, y0, hh, mat] of [[hw * 0.8, hw * 0.94, 0, h * 0.86, wicker], [hw * 0.9, hw * 0.78, h * 0.84, h * 0.1, cloth(0)]]) {
          const q = mesh(new THREE.CylinderGeometry(r1, r0, hh, 36), mat);
          q.position.set(0, y0 + hh / 2, z);
          m.add(q);
        }
        for (let i = 1; i < 8; i++) {
          const r = mesh(new THREE.TorusGeometry(hw * (0.8 + 0.14 * i / 8) + 3, 5, 8, 40), wicker);
          r.rotation.x = Math.PI / 2;
          r.position.set(0, h * 0.86 * i / 8, z);
          m.add(r);
        }
      } else {
        // niche : piles, boîtes selon le niveau
        const kind = Math.round(h) % 3, bw = Math.min(300, w * 0.46), bd = d * 0.86;
        const boxAt = (x, c) => {
          const bh = Math.min(200, h * 0.7);
          const q = mesh(new THREE.BoxGeometry(bw * 0.9, bh, bd), new THREE.MeshStandardMaterial({ color: c, roughness: 0.85 }));
          q.position.set(x, bh / 2, d / 2);
          m.add(q);
          const lid = mesh(new THREE.BoxGeometry(bw * 0.94, 26, bd + 8), new THREE.MeshStandardMaterial({ color: c, roughness: 0.8 }));
          lid.position.set(x, bh, d / 2);
          m.add(lid);
        };
        const n = Math.max(1, Math.floor(w / (bw + 20)));
        for (let i = 0; i < n; i++) {
          const x = -hw + (w * (i + 0.5)) / n;
          if ((i + kind) % 3 === 2) boxAt(x, kind === 1 ? 0xc9b79c : 0x8d8a83);
          else pile(x, 0, bw * 0.92, bd, Math.max(2, Math.min(5, Math.floor(h * 0.75 / 42))), 42, i * 2 + kind);
        }
      }
      break;
    }
    case 'deco_vetements': {
      // vêtements sur cintres, de longueurs et de couleurs variées
      const tones = [0x2f3a4a, 0xe9e4da, 0x8c6f5a, 0x6f8577, 0xb55d4c, 0x3b3b3d, 0xc9b59a, 0x7f93ab, 0xf4f2ee, 0x55463f];
      const step = 62, count = Math.max(3, Math.floor((w * 0.86) / step));
      for (let i = 0; i < count; i++) {
        const x = -((count - 1) * step) / 2 + i * step;
        const len = (h - 70) * [0.95, 0.72, 0.8, 0.66, 0.9][(i * 7 + Math.round(h)) % 5], sh = d * 0.46;
        const s2 = new THREE.Shape();
        s2.moveTo(-28, 0);
        s2.lineTo(28, 0);
        s2.lineTo(sh, -70);
        s2.lineTo(sh * 0.86, -len);
        s2.lineTo(-sh * 0.86, -len);
        s2.lineTo(-sh, -70);
        s2.closePath();
        const q = mesh(new THREE.ExtrudeGeometry(s2, { depth: 24, bevelEnabled: true, bevelSize: 6, bevelThickness: 8, bevelSegments: 2 }), new THREE.MeshStandardMaterial({ color: tones[(i * 3 + Math.round(w)) % 10], roughness: 0.95 }));
        q.rotation.y = Math.PI / 2;
        q.position.set(x - 12, h - 50, d / 2);
        m.add(q);
        const hook = mesh(new THREE.TorusGeometry(16, 2.4, 8, 18, Math.PI * 1.4), chrome);
        hook.rotation.y = Math.PI / 2;
        hook.position.set(x, h - 8, d / 2);
        m.add(hook);
      }
      break;
    }
    case 'deco_livres_niche': {
      const tones = [0x8c4a3c, 0x2f4858, 0xd8c7a6, 0x5b6f5a, 0x3a3a3c, 0xb98a55, 0xe8e2d6, 0x7c5c74];
      const kind = Math.round(h) % 3, M = (c, r = 0.7) => new THREE.MeshStandardMaterial({ color: c, roughness: r });
      const span = kind === 2 ? w * 0.4 : w * 0.58;
      let x = kind === 1 ? hw - span : -hw;
      for (let i = 0; x < (kind === 1 ? hw : -hw + span) - 20; i++) {
        const bt = 20 + ((i * 13 + kind * 7) % 22), bh = Math.min(h * 0.92, 190 + ((i * 29) % 70)), bd = Math.min(d * 0.8, 170);
        const q = mesh(new THREE.BoxGeometry(bt, bh, bd), M(tones[(i * 5 + kind) % 8]));
        q.position.set(x + bt / 2, bh / 2, d / 2);
        m.add(q);
        x += bt + 1.5;
      }
      const ox = kind === 1 ? -hw * 0.55 : hw * 0.6, ph = Math.min(190, h * 0.8);
      if (w > 420) {
        if (kind === 0) {
          const v = mesh(new THREE.LatheGeometry([[0.5, 0], [0.9, 0.2], [1, 0.45], [0.5, 0.75], [0.36, 0.9], [0.5, 1]].map(([r, y]) => new THREE.Vector2(r * 52, y * Math.min(210, h * 0.85))), 32), new THREE.MeshStandardMaterial({ color: 0xc8beb0, roughness: 0.6, side: THREE.DoubleSide }));
          v.position.set(ox, 0, d / 2);
          m.add(v);
        } else if (kind === 1) {
          for (const [pw, hh, c, z] of [[150, ph, 0x3a2d24, 0], [120, ph - 32, 0xd9d2c4, 10]]) {
            const fr = mesh(new THREE.BoxGeometry(pw, hh, z ? 4 : 16), M(c));
            fr.position.set(ox, ph / 2, d / 2 - 20 + z);
            fr.rotation.x = -0.12;
            m.add(fr);
          }
        } else {
          for (const [k, r] of [[0, 46], [1, 32]]) {
            const b = mesh(new THREE.SphereGeometry(r, 24, 18), M(k ? 0xb98a55 : 0x4c5a55, 0.5));
            b.position.set(ox - 40 + k * 86, r, d / 2);
            m.add(b);
          }
        }
      }
      break;
    }
    case 'deco_bouteilles': {
      const items = [[-hw * 0.62, 26, h, 0x5f6d2e, 0.25], [-hw * 0.05, 24, h * 0.82, 0x7a4a1e, 0.3], [hw * 0.45, 22, h * 0.36, 0xd8cdbd, 0.6], [hw * 0.82, 22, h * 0.36, 0x3a3a3c, 0.6]];
      for (const [x, r, hh, c, rough] of items) {
        const mat = new THREE.MeshStandardMaterial({ color: c, roughness: rough });
        const b = mesh(new THREE.CylinderGeometry(r, r, hh * 0.7, 22), mat);
        b.position.set(x, hh * 0.35, d / 2);
        m.add(b);
        const neck = mesh(new THREE.CylinderGeometry(hh > h * 0.5 ? r * 0.4 : r * 0.9, hh > h * 0.5 ? r * 0.9 : r, hh * 0.3, 18), hh > h * 0.5 ? mat : darkMat);
        neck.position.set(x, hh * 0.85, d / 2);
        m.add(neck);
      }
      break;
    }
    case 'deco_planches': {
      // deux planches appuyées au mur
      const board = (bw, bh, c, x, z, tilt) => {
        const sh = new THREE.Shape();
        const r = 26;
        sh.moveTo(-bw / 2 + r, 0);
        sh.lineTo(bw / 2 - r, 0);
        sh.quadraticCurveTo(bw / 2, 0, bw / 2, r);
        sh.lineTo(bw / 2, bh - r);
        sh.quadraticCurveTo(bw / 2, bh, bw / 2 - r, bh);
        sh.lineTo(-bw / 2 + r, bh);
        sh.quadraticCurveTo(-bw / 2, bh, -bw / 2, bh - r);
        sh.lineTo(-bw / 2, r);
        sh.quadraticCurveTo(-bw / 2, 0, -bw / 2 + r, 0);
        const hole = new THREE.Path();
        hole.absarc(0, bh - 34, 13, 0, Math.PI * 2);
        sh.holes.push(hole);
        const b = mesh(new THREE.ExtrudeGeometry(sh, { depth: 16, bevelEnabled: false }), new THREE.MeshStandardMaterial({ color: c, roughness: 0.6 }));
        b.position.set(x, 2, z);
        b.rotation.x = -tilt;
        m.add(b);
      };
      board(w * 0.82, h * 0.96, 0xb98a55, -w * 0.06, 46, 0.1);
      board(w * 0.56, h * 0.72, 0x7d5331, w * 0.14, 66, 0.11);
      break;
    }
    case 'deco_bouilloire': {
      const steelM = new THREE.MeshStandardMaterial({ color: 0xc9ccd0, metalness: 0.85, roughness: 0.25 });
      const body = mesh(new THREE.CylinderGeometry(w * 0.36, w * 0.46, h * 0.78, 32), steelM);
      body.position.set(0, h * 0.45, d / 2);
      m.add(body);
      const base = mesh(new THREE.CylinderGeometry(w * 0.48, w * 0.5, h * 0.07, 32), darkMat);
      base.position.set(0, h * 0.035, d / 2);
      m.add(base);
      const lid = mesh(new THREE.SphereGeometry(w * 0.34, 24, 10, 0, Math.PI * 2, 0, Math.PI / 2), steelM);
      lid.scale.y = 0.35;
      lid.position.set(0, h * 0.84, d / 2);
      m.add(lid);
      const grip = mesh(new THREE.TorusGeometry(h * 0.27, 9, 12, 24, Math.PI), darkMat);
      grip.rotation.z = -Math.PI / 2;
      grip.position.set(w * 0.38, h * 0.5, d / 2);
      m.add(grip);
      break;
    }
    case 'deco_casserole': {
      const pot = new THREE.MeshStandardMaterial({ color: 0x34373b, metalness: 0.5, roughness: 0.4, side: THREE.DoubleSide });
      const body = mesh(new THREE.CylinderGeometry(hw * 0.78, hw * 0.74, h * 0.62, 36), pot);
      body.position.set(0, h * 0.31, d / 2);
      m.add(body);
      const lid = mesh(new THREE.SphereGeometry(hw * 0.8, 32, 10, 0, Math.PI * 2, 0, Math.PI / 2), new THREE.MeshStandardMaterial({ color: 0xc9ccd0, metalness: 0.8, roughness: 0.25 }));
      lid.scale.y = 0.22;
      lid.position.set(0, h * 0.62, d / 2);
      m.add(lid);
      const knobM = mesh(new THREE.SphereGeometry(13, 16, 12), darkMat);
      knobM.position.set(0, h * 0.62 + hw * 0.19, d / 2);
      m.add(knobM);
      for (const sx of [-1, 1]) {
        const ear = mesh(new THREE.BoxGeometry(hw * 0.24, 9, 60), darkMat);
        ear.position.set(sx * hw * 0.88, h * 0.5, d / 2);
        m.add(ear);
      }
      break;
    }
    case 'deco_rideau': {
      // tringle et deux pans de tissu ondulés, ouverts de chaque côté
      const cloth = new THREE.MeshStandardMaterial({ color: 0xeee6da, roughness: 0.95, side: THREE.DoubleSide });
      const pan = (x0, x1) => {
        const n = 48, geo = new THREE.PlaneGeometry(x1 - x0, h - 30, n, 1), pos = geo.attributes.position;
        for (let i = 0; i < pos.count; i++) pos.setZ(i, Math.sin((pos.getX(i) / (x1 - x0)) * Math.PI * 2 * 5) * 26);
        geo.computeVertexNormals();
        const p = mesh(geo, cloth);
        p.position.set((x0 + x1) / 2, (h - 30) / 2, d / 2);
        m.add(p);
      };
      const pw = Math.min(w * 0.27, 480);
      pan(-hw, -hw + pw);
      pan(hw - pw, hw);
      const rod = mesh(new THREE.CylinderGeometry(11, 11, w + 60, 16), new THREE.MeshStandardMaterial({ color: 0x3a3a3c, metalness: 0.6, roughness: 0.4 }));
      rod.rotation.z = Math.PI / 2;
      rod.position.set(0, h - 16, d / 2);
      m.add(rod);
      for (const sx of [-1, 1]) {
        const end = mesh(new THREE.SphereGeometry(20, 16, 12), rod.material);
        end.position.set(sx * (hw + 34), h - 16, d / 2);
        m.add(end);
      }
      break;
    }
    case 'deco_store': {
      // store vénitien à demi baissé
      const slat = new THREE.MeshStandardMaterial({ color: 0xf1ece3, roughness: 0.7 });
      const head = mesh(new THREE.BoxGeometry(w, 45, 45), slat);
      head.position.set(0, h - 22, d / 2);
      m.add(head);
      const step = 42, count = Math.floor((h * 0.5) / step);
      for (let i = 1; i <= count; i++) {
        const s0 = mesh(new THREE.BoxGeometry(w - 10, 3, 44), slat);
        s0.rotation.x = 0.5;
        s0.position.set(0, h - 45 - i * step, d / 2);
        m.add(s0);
      }
      for (const sx of [-0.32, 0.32]) {
        const cord = mesh(new THREE.BoxGeometry(4, count * step, 2), slat);
        cord.position.set(sx * w, h - 45 - (count * step) / 2, d / 2);
        m.add(cord);
      }
      break;
    }
    case 'miroir': {
      // miroir rétroéclairé : glace, cadre alu fin, LED tout autour
      const frame = mesh(new THREE.BoxGeometry(w, h, 25), new THREE.MeshStandardMaterial({ color: 0xc9ccce, metalness: 0.8, roughness: 0.3 }));
      frame.position.set(0, h / 2, 12.5);
      m.add(frame);
      const glassM = mesh(new THREE.BoxGeometry(w - 16, h - 16, 4), mirrorMat);
      glassM.position.set(0, h / 2, 27);
      m.add(glassM);
      const led = new THREE.Mesh(new THREE.BoxGeometry(w + 6, h + 6, 6), new THREE.MeshStandardMaterial({ color: 0xfff3dc, emissive: 0xffe8c0, emissiveIntensity: 1.2 }));
      led.position.set(0, h / 2, 6);
      m.add(led);
      break;
    }
    case 'chauffe_eau':
    case 'chauffe_eau_h': {
      const flat = o.type === 'chauffe_eau_h';
      const len = flat ? w : h, r = Math.min(flat ? h : w, d) / 2;
      const body = mesh(new THREE.CapsuleGeometry(r, Math.max(10, len - 2 * r), 16, 48), enamel());
      body.position.set(0, h / 2, d - r);
      if (flat) body.rotation.z = Math.PI / 2;
      m.add(body);
      // pattes murales
      for (const k of [-0.28, 0.28]) m.add(at(mesh(new THREE.BoxGeometry(flat ? 40 : w * 0.5, flat ? h * 0.5 : 40, Math.max(6, d - r)), greyMat), flat ? w * k : 0, flat ? h / 2 : h / 2 + h * k, (d - r) / 2));
      if (flat) {
        const cap = mesh(new THREE.CylinderGeometry(70, 70, 14, 40), darkMat);
        cap.rotation.z = Math.PI / 2;
        cap.position.set(w / 2 - 6, h / 2, d - r);
        m.add(cap);
        pipes(-hw + 160, 70, d - r);
      } else {
        m.add(at(mesh(new THREE.CylinderGeometry(Math.min(70, r * 0.35), Math.min(70, r * 0.35), 12, 40), darkMat), 0, h * 0.3, d - 4).rotateX(Math.PI / 2));
        pipes(0, Math.min(70, hw * 0.45), d - r);
      }
      break;
    }
    case 'chauffe_eau_plat':
    case 'chauffe_eau_plat_h':
    case 'chauffe_eau_carre':
    case 'chauffe_eau_inst':
    case 'chauffe_eau_gaz': {
      const flat = o.type.startsWith('chauffe_eau_plat'), lying = o.type.endsWith('_h');
      const rad = flat ? Math.min(d * 0.45, Math.min(w, h) * 0.24) : Math.min(w, h) * 0.09;
      // coque : contour arrondi de face, extrudé vers l'avant avec un arrondi
      const bev = flat ? Math.min(45, d * 0.16) : Math.min(16, d * 0.12);
      const sh = new THREE.Shape();
      const X = hw - bev, Y = h - bev, R = Math.max(4, rad - bev);
      sh.moveTo(-X + R, bev);
      sh.lineTo(X - R, bev);
      sh.quadraticCurveTo(X, bev, X, bev + R);
      sh.lineTo(X, Y - R);
      sh.quadraticCurveTo(X, Y, X - R, Y);
      sh.lineTo(-X + R, Y);
      sh.quadraticCurveTo(-X, Y, -X, Y - R);
      sh.lineTo(-X, bev + R);
      sh.quadraticCurveTo(-X, bev, -X + R, bev);
      const shell = mesh(new THREE.ExtrudeGeometry(sh, { depth: Math.max(10, d - 2 * bev), bevelEnabled: true, bevelThickness: bev, bevelSize: bev, bevelSegments: 6, curveSegments: 20 }), enamel());
      shell.position.z = bev;
      m.add(shell);
      const face = (bw, bh, x, y, mat, out = 2) => m.add(at(mesh(new THREE.BoxGeometry(bw, bh, 4), mat), x, y, d + out - 2));
      const knob = (x, y, r) => m.add(at(mesh(new THREE.CylinderGeometry(r, r * 1.08, 18, 36), greyMat), x, y, d + 7).rotateX(Math.PI / 2));
      if (flat) {
        face(lying ? 60 : w * 0.42, lying ? h * 0.36 : 60, lying ? w * 0.36 : 0, lying ? h / 2 : h * 0.16, darkMat);
        pipes(lying ? -hw + 160 : 0, Math.min(70, hw * 0.45), d / 2);
      } else if (o.type === 'chauffe_eau_carre') {
        knob(0, h * 0.24, 24);
        face(w * 0.2, 8, 0, h * 0.42, new THREE.MeshStandardMaterial({ color: 0xd9803a, roughness: 0.5 }));
        pipes(0, Math.min(70, hw * 0.45), d / 2);
      } else if (o.type === 'chauffe_eau_inst') {
        face(w * 0.62, h * 0.2, 0, h * 0.34, darkMat);
        pipes(0, Math.min(45, hw * 0.4), d / 2);
      } else {
        // gaz : hublot de flamme, deux boutons, buse de fumée jusqu'au plafond
        face(w * 0.2, h * 0.09, 0, h * 0.42, darkMat);
        face(w * 0.1, h * 0.035, 0, h * 0.405, new THREE.MeshStandardMaterial({ color: 0x4aa3ff, emissive: 0x2a6cff, emissiveIntensity: 0.6 }), 3);
        knob(-w * 0.2, h * 0.16, 22);
        knob(w * 0.2, h * 0.16, 22);
        const top = Math.max(180, Math.min(600, ((sceneData?.room?.h ?? 2600) - (o.z || 0) - h)));
        m.add(at(mesh(new THREE.CylinderGeometry(58, 58, top, 32), chromeSoft()), 0, h + top / 2 - 4, d * 0.5));
        pipes(0, Math.min(85, hw * 0.5), d / 2);
        m.add(at(mesh(new THREE.CylinderGeometry(9, 9, 120, 16), new THREE.MeshStandardMaterial({ color: 0xd9b13a, metalness: 0.6, roughness: 0.35 })), 0, -58, d / 2));
      }
      break;
    }
    case 'chauffe_eau_sol':
    case 'chauffe_eau_thermo': {
      const thermo = o.type === 'chauffe_eau_thermo', wall = (o.z || 0) > 300;
      const r = hw, foot = wall ? 0 : 70, head = thermo ? Math.min(460, h * 0.26) : 0;
      const pts = [[0, foot], [r * 0.82, foot], [r, foot + 40], [r, h - head - 60], [r * 0.9, h - head - 14], [0, h - head]].map(([x, y]) => new THREE.Vector2(x, y));
      m.add(at(mesh(new THREE.LatheGeometry(pts, 56), enamel()), 0, 0, d - r));
      if (!wall) for (const a of [0.5, 2.6, 4.7]) m.add(at(mesh(new THREE.CylinderGeometry(18, 18, foot + 8, 18), darkMat), Math.cos(a) * r * 0.72, foot / 2, d - r + Math.sin(a) * r * 0.72));
      if (thermo) {
        // pompe à chaleur : tête grise, grille et deux manchettes d'air
        const grey = new THREE.MeshStandardMaterial({ color: 0x7d858b, roughness: 0.55 });
        m.add(at(mesh(new THREE.CylinderGeometry(r * 0.98, r, head - 10, 56), grey), 0, h - head / 2, d - r));
        m.add(at(mesh(new THREE.CylinderGeometry(r * 0.9, r * 0.98, 12, 56), darkMat), 0, h - 5, d - r));
        for (const k of [-1, 1]) m.add(at(mesh(new THREE.CylinderGeometry(80, 80, 120, 32), chromeSoft()), k * r * 0.45, h + 55, d - r));
        m.add(at(mesh(new THREE.BoxGeometry(w * 0.32, head * 0.3, 8), darkMat), 0, h - head * 0.5, d - 2));
      } else {
        m.add(at(mesh(new THREE.CylinderGeometry(95, 95, 16, 40), darkMat), 0, h * 0.32, d - 4).rotateX(Math.PI / 2));
      }
      for (const [x, c] of [[-70, 0x3f7fc4], [70, 0xc94f3f]]) {
        const q = mesh(new THREE.CylinderGeometry(11, 11, 90, 16), chrome);
        q.rotation.x = Math.PI / 2;
        q.position.set(x, wall ? 60 : foot + 130, 30);
        m.add(q);
        m.add(at(mesh(new THREE.CylinderGeometry(15, 15, 10, 16), new THREE.MeshStandardMaterial({ color: c, roughness: 0.5 })), x, wall ? 60 : foot + 130, 8).rotateX(Math.PI / 2));
      }
      break;
    }
    case 'll_hublot':
    case 'll_mini':
    case 'll_encastrable':
    case 'll_sechant':
    case 'sl_evac':
    case 'sl_cond':
    case 'sl_pac':
    case 'sl_mural':
      frontLoader(m, o.type, 0, w, h, d);
      break;
    case 'tour_lavage': {
      const gap = 18, hh = (h - gap) / 2;
      frontLoader(m, 'll_hublot', 0, w, hh, d);
      m.add(at(mesh(new THREE.BoxGeometry(w - 6, gap, d - 10), darkMat), 0, hh + gap / 2, d / 2));
      frontLoader(m, 'sl_pac', hh + gap, w, hh, d);
      break;
    }
    case 'll_top':
    case 'll_cuve':
    case 'll_semi': {
      const body = enamel(), bar = Math.min(150, h * 0.15), top = o.type === 'll_top' ? h - 60 : h - bar;
      m.add(mesh(extrudeUp(roundRectPath(new THREE.Shape(), -hw + 4, 4, hw - 4, d - 4, 26), 20, top - 20, 4), body));
      m.add(at(mesh(new THREE.BoxGeometry(w - 30, 20, d - 30), darkMat), 0, 10, d / 2));
      // bandeau de commande au dos
      m.add(at(mesh(new THREE.BoxGeometry(w - 10, h - top, d * 0.22), o.type === 'll_semi' ? new THREE.MeshStandardMaterial({ color: 0x7f9db5, roughness: 0.5 }) : body), 0, top + (h - top) / 2, d * 0.12));
      m.add(at(mesh(new THREE.BoxGeometry(w * 0.3, Math.min(60, (h - top) * 0.5), 4), darkMat), w * 0.18, top + (h - top) / 2, d * 0.23 + 2));
      const lid = (x, lw, mat) => m.add(at(mesh(extrudeUp(roundRectPath(new THREE.Shape(), -lw / 2, 0, lw / 2, d * 0.66, 22), 0, 16, 4), mat), x, top, d * 0.27));
      if (o.type === 'll_semi') {
        lid(-w * 0.17, w * 0.54, new THREE.MeshStandardMaterial({ color: 0x9fb8cc, roughness: 0.3 }));
        lid(w * 0.29, w * 0.3, new THREE.MeshStandardMaterial({ color: 0x9fb8cc, roughness: 0.3 }));
        for (const k of [-0.3, 0, 0.3]) m.add(at(mesh(new THREE.CylinderGeometry(22, 24, 24, 28), greyMat), w * k, top + (h - top) / 2, d * 0.23 + 12).rotateX(Math.PI / 2));
      } else if (o.type === 'll_cuve') {
        lid(0, w * 0.86, darkMat);
        m.add(at(mesh(new THREE.BoxGeometry(w * 0.3, 8, 24), chromeSoft()), 0, top + 20, d * 0.9));
      } else {
        lid(0, w * 0.88, body);
        m.add(at(mesh(new THREE.BoxGeometry(w * 0.4, 14, 14), greyMat), 0, top + 12, d * 0.93));
      }
      break;
    }
    case 'kitchen_sink': {
      const mount = o.mount || 'inset';
      const layout = o.layout || 'drainer';
      const sinkMat = o.sinkFinish === 'noir_quartz' ? tapBlack
                    : o.sinkFinish === 'blanc_ceramique' ? ceramic
                    : new THREE.MeshStandardMaterial({ color: 0xc8cdd2, roughness: 0.22, metalness: 0.88 });
      const sinkMatBowl = o.sinkFinish === 'noir_quartz'
                    ? new THREE.MeshStandardMaterial({ color: 0x1f2124, roughness: 0.45, side: THREE.DoubleSide })
                    : o.sinkFinish === 'blanc_ceramique'
                    ? ceramicIn
                    : new THREE.MeshStandardMaterial({ color: 0xc8cdd2, roughness: 0.22, metalness: 0.88, side: THREE.DoubleSide });
      const isUndermount = mount === 'undermount';
      // Sous-plan : lèvre fine biseautée au ras du plan ; Encastré : cadre avec lèvre 5mm au-dessus du plan
      const topY = isUndermount ? 1.5 : 5.0;
      const rimH = isUndermount ? 3.0 : 6.0;
      const rimThick = 26; // largeur des bords du cadre extérieur

      const hasDrainer = layout === 'drainer' || layout === '2_drainer';
      const isDouble = layout === '2' || layout === '2_drainer';
      // cuve entre la plage de robinetterie et le bord avant
      const deckDepth = Math.max(70, d * 0.26);
      const halfD = (d - 36 - deckDepth - 6) / 2;
      const cz = deckDepth + 6 + halfD;
      const bowlD = halfD * 2 + 30;
      const BN = 3.8; // arrondi de la cuve, le même pour le trou de la plage
      const bowls = []; // [centre x, demi-largeur]

      const addBowl = (x, a) => {
        bowls.push([x, a]);
        m.add(mesh(bowl(x, cz, a, halfD, 190, topY - 1, BN, 0.6), sinkMatBowl));
      };

      if (hasDrainer && !isDouble) {
        // 1 bac à gauche + égouttoir design à droite
        const bowlW = Math.min(w * 0.52, 480);
        const bowlX = -hw + bowlW / 2 + 35;
        // Tablier plein sous l'égouttoir
        const drX0 = bowlX + bowlW / 2 + 10;
        const drX1 = hw - rimThick;
        const drW = drX1 - drX0;

        // Égouttoir avec rainures d'écoulement biseautées
        if (!isUndermount) {
          const nGrooves = 8;
          for (let i = 0; i < nGrooves; i++) {
            const gz = cz - bowlD * 0.38 + (bowlD * 0.76) * i / (nGrooves - 1);
            const groove = mesh(new THREE.BoxGeometry(drW - 20, 2.5, 6), sinkMat);
            groove.position.set((drX0 + drX1) / 2, topY + 0.5, gz);
            m.add(groove);
          }
        }
        // Cuve profonde
        addBowl(bowlX, bowlW / 2 - 15);
        // Bonde panier inox 90 mm + bouchon filtre
        m.add(at(mesh(new THREE.CylinderGeometry(45, 42, 5, 32), chrome), bowlX, topY - 188, cz));
        m.add(at(mesh(new THREE.CylinderGeometry(18, 18, 8, 24), darkMat), bowlX, topY - 185, cz));
        // Trop-plein
        const overFlow = mesh(new THREE.BoxGeometry(32, 12, 4), chrome);
        overFlow.position.set(bowlX, topY - 35, cz - (bowlD / 2 - 16));
        m.add(overFlow);
      } else if (isDouble) {
        // Double cuve profonde avec séparation centrale
        const singleW = (w - 90) / 2;
        const b1X = -hw + 35 + singleW / 2;
        const b2X = hw - 35 - singleW / 2;
        addBowl(b1X, singleW / 2 - 10);
        m.add(at(mesh(new THREE.CylinderGeometry(45, 42, 5, 32), chrome), b1X, topY - 188, cz));
        m.add(at(mesh(new THREE.CylinderGeometry(18, 18, 8, 24), darkMat), b1X, topY - 185, cz));

        addBowl(b2X, singleW / 2 - 10);
        m.add(at(mesh(new THREE.CylinderGeometry(45, 42, 5, 32), chrome), b2X, topY - 188, cz));
        m.add(at(mesh(new THREE.CylinderGeometry(18, 18, 8, 24), darkMat), b2X, topY - 185, cz));
      } else {
        // 1 bac simple / compact
        const bowlW = w - 60;
        const bowlX = 0;
        addBowl(bowlX, bowlW / 2 - 10);
        m.add(at(mesh(new THREE.CylinderGeometry(45, 42, 5, 32), chrome), bowlX, topY - 188, cz));
        m.add(at(mesh(new THREE.CylinderGeometry(18, 18, 8, 24), darkMat), bowlX, topY - 185, cz));
        const overFlow = mesh(new THREE.BoxGeometry(32, 12, 4), chrome);
        overFlow.position.set(bowlX, topY - 35, cz - (bowlD / 2 - 16));
        m.add(overFlow);
      }

      // Plage d'une pièce, percée à la forme exacte de chaque cuve : pas de jour dans les coins
      const deck = roundRectPath(new THREE.Shape(), -hw, 0, hw, d, 12);
      for (const [x, a] of bowls) deck.holes.push(sePath(new THREE.Path(), x, cz, a, halfD, BN, 64, true));
      m.add(mesh(extrudeUp(deck, topY - rimH, rimH, 0), sinkMat));

      // Mitigeur réaliste placé sur la gorge arrière
      const fMat = o.faucetFinish === 'noir_mat' ? tapBlack
                 : o.faucetFinish === 'or_brosse' ? tapGold
                 : o.faucetFinish === 'inox_brosse' ? tapSteel : chrome;
      const fX = hasDrainer && !isDouble ? (-hw + Math.min(w * 0.52, 480) / 2 + 35) : 0;
      const faucetY = topY;
      mixerRealistic(m, fX, faucetY, deckDepth * 0.55, {
        mat: fMat,
        height: o.faucetHeight || 360,
        spring: o.spring === true,
        pullout: o.pullout === true,
        swan: o.swan === true || (!o.spring && !o.square),
        square: o.square === true,
        faucetLever: o.faucetLever,
        toward: 1,
      });
      break;
    }
    case 'kitchen_hob': {
      const hobType = o.hobType || 'induction';
      const glassMat = new THREE.MeshPhysicalMaterial({ color: 0x111316, roughness: 0.08, metalness: 0.12, clearcoat: 1.0 });
      const plate = mesh(new THREE.BoxGeometry(w, 8, d), glassMat);
      plate.position.set(0, 4.0, d / 2);
      m.add(plate);

      if (hobType === 'gaz') {
        const castMat = new THREE.MeshStandardMaterial({ color: 0x222426, roughness: 0.85, metalness: 0.2 });
        const brassMat = new THREE.MeshStandardMaterial({ color: 0xd4af37, roughness: 0.35, metalness: 0.8 });
        const nBurners = w >= 800 ? 5 : 4;
        const positions = nBurners === 5 ? [
          [-w * 0.3, d * 0.3], [w * 0.3, d * 0.3],
          [0, d * 0.5],
          [-w * 0.3, d * 0.7], [w * 0.3, d * 0.7],
        ] : [
          [-w * 0.25, d * 0.32], [w * 0.25, d * 0.32],
          [-w * 0.25, d * 0.68], [w * 0.25, d * 0.68],
        ];
        for (const [bx, bz] of positions) {
          m.add(at(mesh(new THREE.CylinderGeometry(28, 32, 8, 32), darkMat), bx, 6, bz));
          m.add(at(mesh(new THREE.CylinderGeometry(18, 18, 4, 24), brassMat), bx, 10, bz));
          const g1 = mesh(new THREE.BoxGeometry(75, 12, 10), castMat);
          g1.position.set(bx, 13, bz);
          const g2 = mesh(new THREE.BoxGeometry(10, 12, 75), castMat);
          g2.position.set(bx, 13, bz);
          m.add(g1, g2);
        }
        for (let i = 0; i < nBurners; i++) {
          const kx = -w * 0.3 + (w * 0.6) * i / (nBurners - 1);
          const knob = mesh(new THREE.CylinderGeometry(14, 14, 10, 24), tapSteel);
          knob.position.set(kx, 8, d * 0.88);
          m.add(knob);
        }
      } else {
        const ringMat = new THREE.MeshStandardMaterial({ color: 0x828890, roughness: 0.4 });
        const ledRed = new THREE.MeshBasicMaterial({ color: 0xff3b30 });
        const nZones = w >= 800 ? 5 : 4;
        const zones = nZones === 5 ? [
          [-w * 0.3, d * 0.32, 75], [w * 0.3, d * 0.32, 65],
          [0, d * 0.5, 95],
          [-w * 0.3, d * 0.68, 65], [w * 0.3, d * 0.68, 85],
        ] : [
          [-w * 0.25, d * 0.32, 75], [w * 0.25, d * 0.32, 65],
          [-w * 0.25, d * 0.68, 65], [w * 0.25, d * 0.68, 85],
        ];
        for (const [zx, zz, r] of zones) {
          const ring = mesh(new THREE.RingGeometry(r - 3, r, 48), ringMat);
          ring.rotation.x = -Math.PI / 2;
          ring.position.set(zx, 5.2, zz);
          m.add(ring);
          const c1 = mesh(new THREE.BoxGeometry(20, 0.5, 2), ringMat);
          c1.position.set(zx, 5.2, zz);
          const c2 = mesh(new THREE.BoxGeometry(2, 0.5, 20), ringMat);
          c2.position.set(zx, 5.2, zz);
          m.add(c1, c2);
        }
        const ctrl = mesh(new THREE.BoxGeometry(w * 0.45, 0.5, 28), new THREE.MeshBasicMaterial({ color: 0x22262a }));
        ctrl.position.set(0, 5.2, d * 0.88);
        m.add(ctrl);
        for (let i = -2; i <= 2; i++) {
          const dot = mesh(new THREE.BoxGeometry(6, 0.8, 3), ledRed);
          dot.position.set(i * 22, 5.4, d * 0.88);
          m.add(dot);
        }
      }
      break;
    }
    case 'kitchen_oven': {
      const isBlack = o.finish === 'full_black';
      const isWhite = o.finish === 'blanc';
      const isBlackGold = o.finish === 'black_gold';
      const handleStyle = o.handle || 'bar';
      const bodyMat = new THREE.MeshStandardMaterial({ color: 0x1f2124, roughness: 0.5 });
      const fasciaMat = isWhite ? new THREE.MeshStandardMaterial({ color: 0xf5f5f5, roughness: 0.25 })
                      : (isBlack || isBlackGold) ? new THREE.MeshStandardMaterial({ color: 0x181a1c, roughness: 0.35 })
                      : new THREE.MeshStandardMaterial({ color: 0xb5bcc4, roughness: 0.3, metalness: 0.85 });
      const glassDoorMat = isWhite
          ? new THREE.MeshPhysicalMaterial({ color: 0xf0f2f5, roughness: 0.1, clearcoat: 0.9 })
          : new THREE.MeshPhysicalMaterial({ color: 0x121417, roughness: 0.08, clearcoat: 1.0, transmission: 0.2, thickness: 12 });

      const body = mesh(new THREE.BoxGeometry(w - 20, h - 20, d), bodyMat);
      body.position.set(0, h / 2, d / 2 - 10);
      m.add(body);

      const doorH = h * 0.78;
      const door = mesh(new THREE.BoxGeometry(w, doorH, 18), glassDoorMat);
      door.position.set(0, doorH / 2, d + 9);
      m.add(door);

      const barMat = isBlackGold ? tapGold : (isBlack ? tapBlack : (isWhite ? tapSteel : chrome));
      const barLen = w * 0.76;

      if (handleStyle === 'square') {
        // Profilé carré contemporain
        const barSq = mesh(new THREE.BoxGeometry(barLen, 16, 16), barMat);
        barSq.position.set(0, doorH - 35, d + 38);
        m.add(barSq);
        for (const sx of [-barLen * 0.44, barLen * 0.44]) {
          const standoff = mesh(new THREE.BoxGeometry(16, 16, 26), barMat);
          standoff.position.set(sx, doorH - 35, d + 22);
          m.add(standoff);
        }
      } else if (handleStyle === 'retro') {
        // Poignée cintrée classique aux extrémités avec sphères décoratives
        const barR = mesh(new THREE.CylinderGeometry(9, 9, barLen * 0.9, 24), barMat);
        barR.rotation.z = Math.PI / 2;
        barR.position.set(0, doorH - 35, d + 38);
        m.add(barR);
        for (const sx of [-barLen * 0.45, barLen * 0.45]) {
          const ball = mesh(new THREE.SphereGeometry(13, 20, 20), barMat);
          ball.position.set(sx, doorH - 35, d + 38);
          const standoff = mesh(new THREE.CylinderGeometry(8, 11, 24, 16), barMat);
          standoff.rotation.x = Math.PI / 2;
          standoff.position.set(sx, doorH - 35, d + 22);
          m.add(ball, standoff);
        }
      } else if (handleStyle === 'integrated') {
        // Poignée affleurante intégrée / profil minimaliste
        const profile = mesh(new THREE.BoxGeometry(w - 24, 12, 22), barMat);
        profile.position.set(0, doorH - 12, d + 12);
        m.add(profile);
      } else {
        // Barre ronde tubulaire moderne par défaut
        const bar = mesh(new THREE.CylinderGeometry(9, 9, barLen, 24), barMat);
        bar.rotation.z = Math.PI / 2;
        bar.position.set(0, doorH - 35, d + 38);
        m.add(bar);
        for (const sx of [-barLen * 0.44, barLen * 0.44]) {
          const standoff = mesh(new THREE.CylinderGeometry(7, 7, 26, 16), barMat);
          standoff.rotation.x = Math.PI / 2;
          standoff.position.set(sx, doorH - 35, d + 22);
          m.add(standoff);
        }
      }

      const bandH = h - doorH;
      const band = mesh(new THREE.BoxGeometry(w, bandH, 18), fasciaMat);
      band.position.set(0, doorH + bandH / 2, d + 9);
      m.add(band);

      const ledDisplay = mesh(new THREE.BoxGeometry(75, 26, 2), new THREE.MeshBasicMaterial({ color: 0x050608 }));
      ledDisplay.position.set(0, doorH + bandH / 2, d + 19);
      m.add(ledDisplay);
      const ledText = mesh(new THREE.BoxGeometry(45, 12, 1), new THREE.MeshBasicMaterial({ color: 0xffa500 }));
      ledText.position.set(0, doorH + bandH / 2, d + 20.5);
      m.add(ledText);

      if (!isBlack) {
        for (const kx of [-w * 0.32, w * 0.32]) {
          const knob = mesh(new THREE.CylinderGeometry(18, 18, 14, 28), barMat);
          knob.rotation.x = Math.PI / 2;
          knob.position.set(kx, doorH + bandH / 2, d + 22);
          m.add(knob);
        }
      }
      break;
    }
    case 'kitchen_hood': {
      // Hotte aspirante intégrée ou télescopique sous caisson
      const steelMat = new THREE.MeshStandardMaterial({ color: 0xc4c9ce, metalness: 0.88, roughness: 0.28 });
      const darkSteel = new THREE.MeshStandardMaterial({ color: 0x22252a, metalness: 0.6, roughness: 0.4 });
      const filterMat = new THREE.MeshStandardMaterial({ color: 0x9ca3af, metalness: 0.92, roughness: 0.45 });
      const ledMat = new THREE.MeshStandardMaterial({ color: 0xfff6e0, emissive: 0xffe8b4, emissiveIntensity: 2.2 });

      // Corps métallique inférieur de la hotte
      const hoodH = Math.min(120, h * 0.25);
      const body = mesh(new THREE.BoxGeometry(w - 4, hoodH, d - 10), steelMat);
      body.position.set(0, hoodH / 2, d / 2);
      m.add(body);

      // Bandeau frontal / visière télescopique
      const visorH = Math.min(45, hoodH * 0.7);
      const visor = mesh(new THREE.BoxGeometry(w, visorH, 22), darkSteel);
      visor.position.set(0, visorH / 2 + 6, d + 8);
      m.add(visor);

      // Grilles filtres à graisse sous la hotte (inox perforé)
      const fw = (w - 40) / 2;
      const fd = d - 70;
      for (const fx of [-w * 0.24, w * 0.24]) {
        const flt = mesh(new THREE.BoxGeometry(fw, 5, fd), filterMat);
        flt.position.set(fx, 2, d / 2);
        m.add(flt);
        // Poignée / clip de filtre
        const clip = mesh(new THREE.BoxGeometry(28, 4, 14), darkSteel);
        clip.position.set(fx, -1, d / 2);
        m.add(clip);
      }

      // Spots LED d'éclairage intégrés sous la hotte
      for (const lx of [-w * 0.35, w * 0.35]) {
        const spotRing = mesh(new THREE.CylinderGeometry(20, 20, 4, 24), steelMat);
        spotRing.position.set(lx, 2, 45);
        const spotGlass = mesh(new THREE.CylinderGeometry(15, 15, 5, 24), ledMat);
        spotGlass.position.set(lx, 1.5, 45);
        m.add(spotRing, spotGlass);
      }
      break;
    }
    case 'kitchen_hood_free': {
      // Hotte murale posée librement : hotte (pyramide, inclinée verre noir ou box) + cheminée jusqu'au plafond.
      // Repère : x centré sur la largeur, y = 0 au bas de la hotte, z = 0 contre le mur, z = d devant.
      const steel = new THREE.MeshStandardMaterial({ color: 0xc8ccd0, metalness: 0.88, roughness: 0.26 });
      const glass = new THREE.MeshStandardMaterial({ color: 0x0d0f12, metalness: 0.35, roughness: 0.08 });
      const dark = new THREE.MeshStandardMaterial({ color: 0x24272c, metalness: 0.6, roughness: 0.4 });
      const led = new THREE.MeshStandardMaterial({ color: 0xfff6e0, emissive: 0xffe8b4, emissiveIntensity: 2.2 });
      const style = o.hoodStyle || 'pyramid';
      const chimW = Math.min(300, w * 0.45), chimD = Math.min(260, d * 0.6);
      let canopyTop = 0;
      if (style === 'inclined') {
        // caisson contre le mur + vitre noire inclinée vers l'avant
        const bodyH = 420, bodyD = Math.min(220, d * 0.55);
        const body = mesh(new THREE.BoxGeometry(w, bodyH, bodyD), dark);
        body.position.set(0, bodyH / 2, bodyD / 2);
        m.add(body);
        const len = Math.hypot(bodyH, d - bodyD);
        const panel = mesh(new THREE.BoxGeometry(w, len, 14), glass);
        const ang = Math.atan2(d - bodyD, bodyH);
        panel.position.set(0, bodyH / 2, bodyD + (d - bodyD) / 2);
        panel.rotation.x = ang;
        m.add(panel);
        const strip = mesh(new THREE.BoxGeometry(w * 0.6, 6, 6), led);
        strip.position.set(0, 4, d - 20);
        m.add(strip);
        canopyTop = bodyH;
      } else if (style === 'box') {
        // box rectangulaire en inox
        const boxH = 90;
        const box = mesh(new THREE.BoxGeometry(w, boxH, d), steel);
        box.position.set(0, boxH / 2, d / 2);
        m.add(box);
        const bar = mesh(new THREE.BoxGeometry(w * 0.4, 8, 6), dark);
        bar.position.set(0, boxH / 2, d + 3);
        m.add(bar);
        canopyTop = boxH;
      } else {
        // pyramide : bandeau bas + tronc de pyramide jusqu'à la cheminée
        const bandH = 60;
        const band = mesh(new THREE.BoxGeometry(w, bandH, d), steel);
        band.position.set(0, bandH / 2, d / 2);
        m.add(band);
        const pyrH = Math.min(320, h * 0.35);
        // tronc de pyramide : bas w × d, haut chimW × chimD (contre le mur)
        const frustum = new THREE.BufferGeometry();
        const b0 = [-w / 2, 0, 0], b1 = [w / 2, 0, 0], b2 = [w / 2, 0, d], b3 = [-w / 2, 0, d];
        const t0 = [-chimW / 2, pyrH, 0], t1 = [chimW / 2, pyrH, 0], t2 = [chimW / 2, pyrH, chimD], t3 = [-chimW / 2, pyrH, chimD];
        const quads = [[b3, b2, t2, t3], [b2, b1, t1, t2], [b0, b3, t3, t0], [t3, t2, t1, t0]];
        const pos = [];
        for (const [a, b, c, e] of quads) pos.push(...a, ...b, ...c, ...a, ...c, ...e);
        frustum.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
        frustum.computeVertexNormals();
        const pyrMat = steel.clone();
        pyrMat.side = THREE.DoubleSide;
        const pyr = new THREE.Mesh(frustum, pyrMat);
        pyr.position.set(0, bandH, 0);
        m.add(pyr);
        canopyTop = bandH + pyrH;
      }
      // cheminée jusqu'au plafond, contre le mur
      const chimH = Math.max(0, h - canopyTop);
      if (chimH > 1) {
        const chim = mesh(new THREE.BoxGeometry(chimW, chimH, chimD), style === 'inclined' ? dark : steel);
        chim.position.set(0, canopyTop + chimH / 2, chimD / 2);
        m.add(chim);
      }
      // filtres sous la hotte
      const flt = mesh(new THREE.BoxGeometry(w * 0.8, 4, d * 0.6), dark);
      flt.position.set(0, 1, d / 2);
      m.add(flt);
      break;
    }
      default:
        lbox(g, ceramic, -hw, hw, 0, h, 0, d);
    }
  } catch (err) {
    console.error('buildFixture error for', o, err);
    lbox(g, ceramic, -hw, hw, 0, h, 0, d);
  }
  return g;
}

/** Cylindre vertical chromé en mm (centre y). */
function lcylMM(m, x, y, z, r, len) {
  const c = mesh(new THREE.CylinderGeometry(r, r, len, 24), chrome);
  c.position.set(x, y, z);
  m.add(c);
  return c;
}

/** Place un objet (mm) et le renvoie. */
function at(o, x, y, z) {
  o.position.set(x, y, z);
  return o;
}

/** Objet posé : groupe au centre de son emprise, tourné dos au mur. Le modèle glTF arrive plus tard. */
function buildObject(o, d) {
  const root = new THREE.Group();
  root.position.copy(P(o.x, o.y, o.z));
  root.rotation.y = -o.rot * Math.PI / 180;
  if (!o.decor) root.userData.uid = o.pick || 'obj:' + o.uid; // toucher l'objet le sélectionne (la vasque : son meuble)
  const inner = new THREE.Group();
  inner.position.z = -o.d / 2 * S; // dos en z = 0 → recentré
  root.add(inner);
  if (o.kind === 'fixture') {
    inner.add(buildFixture(o, d));
  } else if (o.panels && o.panels.length) {
    // meuble de la bibliothèque de l'atelier : un pavé par panneau, à sa couleur
    const mats = new Map();
    for (const q of o.panels) {
      let m = mats.get(q.color);
      if (!m) {
        m = new THREE.MeshStandardMaterial({ color: q.color, roughness: 0.62 });
        mats.set(q.color, m);
      }
      const mesh = lbox(inner, m, q.x0, q.x1, q.y0, q.y1, q.z0, q.z1);
      mesh.castShadow = mesh.receiveShadow = true;
    }
  } else if (o.file) {
    // en attendant le modèle : un volume discret aux cotes
    const ph = lbox(inner, new THREE.MeshStandardMaterial({ color: 0xe8e2da, transparent: true, opacity: 0.35 }), -o.w / 2, o.w / 2, 0, o.h, 0, o.d);
    loadModel(o.file).then((src) => {
      invalidate(true);
      // modèle tourné (largeur le long de x), puis mis aux cotes de l'objet
      const inner2 = src.clone(true);
      // géométries et matériaux partagés avec le modèle en cache : à ne pas libérer
      inner2.traverse((x) => {
        x.userData.cached = true;
        const ms = Array.isArray(x.material) ? x.material : x.material ? [x.material] : [];
        for (const m of ms) m.userData.cached = true;
      });
      inner2.rotation.y = (o.yaw || 0) * Math.PI / 180;
      const m = new THREE.Group();
      m.add(inner2);
      const box = new THREE.Box3().setFromObject(m);
      const size = box.getSize(new THREE.Vector3());
      m.scale.set(o.w * S / (size.x || 1), Math.max(o.h, 1) * S / (size.y || 1), o.d * S / (size.z || 1));
      const b2 = new THREE.Box3().setFromObject(m);
      const c = b2.getCenter(new THREE.Vector3());
      m.position.set(-c.x, -b2.min.y, o.d / 2 * S - c.z);
      m.traverse((x) => {
        if (x.isMesh) x.castShadow = x.receiveShadow = true;
      });
      inner.remove(ph);
      ph.geometry.dispose();
      inner.add(m);
    }).catch(() => {
      ph.material.opacity = 0.8; // modèle introuvable : on garde le volume
    });
  }
  return root;
}

// ------------------------------------------------------------------ points de réseau (appareillage)

const plateMat = new THREE.MeshStandardMaterial({ color: 0xf6f6f3, roughness: 0.35 });
const plateDark = new THREE.MeshStandardMaterial({ color: 0x2b2d31, roughness: 0.5 });
const plateGrey = new THREE.MeshStandardMaterial({ color: 0xc9ccd0, roughness: 0.45 });
const pvc = new THREE.MeshStandardMaterial({ color: 0x9ea3a8, roughness: 0.6 });
const brass = new THREE.MeshStandardMaterial({ color: 0xd4a017, roughness: 0.3, metalness: 0.7 });

/** Appareillage en mm dans un repère local : x le long du mur, y vers le haut, z vers la pièce (0 = mur). */
function buildNetPoint(p, d) {
  const g = new THREE.Group();
  const m = new THREE.Group();
  m.scale.set(S, S, S);
  g.add(m);

  const sf = p.finish || d?.socketFinish || 'blanc';
  const customPlate = sf === 'noir_mat' ? new THREE.MeshStandardMaterial({ color: 0x1e2022, roughness: 0.5 })
                    : sf === 'anthracite' ? new THREE.MeshStandardMaterial({ color: 0x3a3d42, roughness: 0.45 })
                    : sf === 'alu_brosse' ? new THREE.MeshStandardMaterial({ color: 0xc0c3c7, roughness: 0.25, metalness: 0.85 })
                    : sf === 'or_brosse' ? new THREE.MeshStandardMaterial({ color: 0xd4a017, roughness: 0.3, metalness: 0.75 })
                    : plateMat;

  const box = (w, h, d, mat, x = 0, y = 0, z = 0) => {
    const b = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
    b.position.set(x, y, z + d / 2);
    b.castShadow = false;
    m.add(b);
    return b;
  };
  const cyl = (r, len, mat, x = 0, y = 0, z = 0, alongZ = true) => {
    const c = new THREE.Mesh(new THREE.CylinderGeometry(r, r, len, 24), mat);
    if (alongZ) c.rotation.x = Math.PI / 2;
    c.position.set(x, y, z + (alongZ ? len / 2 : 0));
    m.add(c);
    return c;
  };
  // plaque de 86 x 86 (prise, interrupteur) : socle, enjoliveur
  const plate = (x = 0) => {
    box(86, 86, 9, customPlate, x, 0, 0);
    box(70, 70, 2, customPlate, x, 0, 9);
  };
  const socket = (x = 0) => {
    plate(x);
    cyl(24, 3, plateGrey, x, 0, 10);
    cyl(2.6, 2, plateDark, x - 9.5, 0, 12.5);
    cyl(2.6, 2, plateDark, x + 9.5, 0, 12.5);
  };
  switch (p.kind) {
    case 'socket':
    case 'socket20':
      socket();
      if (p.kind === 'socket20') box(14, 6, 1, new THREE.MeshStandardMaterial({ color: 0xe8590c }), 0, -33, 11);
      break;
    case 'socketDouble':
      box(157, 86, 9, customPlate, 0, 0, 0);
      for (const x of [-36, 36]) {
        box(64, 64, 2, customPlate, x, 0, 9);
        cyl(22, 3, plateGrey, x, 0, 10);
        cyl(2.6, 2, plateDark, x - 9, 0, 12.5);
        cyl(2.6, 2, plateDark, x + 9, 0, 12.5);
      }
      break;
    case 'socketTriple':
      box(228, 86, 9, customPlate, 0, 0, 0);
      for (const x of [-71, 0, 71]) {
        box(64, 64, 2, customPlate, x, 0, 9);
        cyl(22, 3, plateGrey, x, 0, 10);
        cyl(2.6, 2, plateDark, x - 9, 0, 12.5);
        cyl(2.6, 2, plateDark, x + 9, 0, 12.5);
      }
      break;
    case 'socketQuad':
      box(299, 86, 9, customPlate, 0, 0, 0);
      for (const x of [-106.5, -35.5, 35.5, 106.5]) {
        box(64, 64, 2, customPlate, x, 0, 9);
        cyl(22, 3, plateGrey, x, 0, 10);
        cyl(2.6, 2, plateDark, x - 9, 0, 12.5);
        cyl(2.6, 2, plateDark, x + 9, 0, 12.5);
      }
      break;
    case 'switch_':
      plate();
      box(44, 56, 4, customPlate, 0, 0, 11);
      box(30, 2, 1, plateGrey, 0, -20, 15);
      break;
    case 'switchDouble':
      plate();
      box(26, 56, 4, customPlate, -15, 0, 11);
      box(26, 56, 4, customPlate, 15, 0, 11);
      break;
    case 'switchTriple':
      plate();
      box(18, 56, 4, customPlate, -22, 0, 11);
      box(18, 56, 4, customPlate, 0, 0, 11);
      box(18, 56, 4, customPlate, 22, 0, 11);
      break;
    case 'usb':
      plate();
      box(14, 6, 2, plateDark, 0, 10, 11);
      box(9, 4, 2, plateDark, 0, -10, 11);
      break;
    case 'rj45':
      plate();
      box(16, 14, 3, plateDark, 0, 0, 11);
      break;
    case 'tvSat':
      plate();
      cyl(8, 6, plateGrey, -16, 0, 11);
      cyl(8, 6, plateGrey, 16, 0, 11);
      break;
    case 'out32':
      plate();
      cyl(9, 18, plateGrey, 0, -20, 10);
      break;
    case 'light':
      if (p.ceiling) {
        // point lumineux au plafond : douille et ampoule allumée
        const rose = new THREE.Mesh(new THREE.CylinderGeometry(50, 50, 12, 32), plateMat);
        rose.position.set(0, -6, 0);
        m.add(rose);
        const wire = new THREE.Mesh(new THREE.CylinderGeometry(2, 2, 300, 8), plateDark);
        wire.position.set(0, -160, 0);
        m.add(wire);
        const bulb = new THREE.Mesh(new THREE.SphereGeometry(45, 24, 16), new THREE.MeshStandardMaterial({ color: 0xfff6e0, emissive: 0xffe2b0, emissiveIntensity: 1.6 }));
        bulb.position.set(0, -340, 0);
        m.add(bulb);
      } else {
        plate();
      }
      break;
    case 'led':
      box(60, 30, 20, plateGrey);
      break;
    case 'waterCold':
    case 'waterHot':
    case 'valveMachine': {
      // robinet d'arrêt chromé, poignée bleue (froid) ou rouge (chaud)
      cyl(10, 50, chrome, 0, 0, 0);
      cyl(14, 22, chrome, 0, 0, 50);
      const col = p.kind === 'waterHot' ? 0xd62f2f : (p.kind === 'valveMachine' ? 0x7a7f86 : 0x1c7ed6);
      box(46, 10, 8, new THREE.MeshStandardMaterial({ color: col, roughness: 0.4 }), 0, 18, 58);
      break;
    }
    case 'drain':
      cyl(22, 60, pvc, 0, 0, 0);
      cyl(25, 10, pvc, 0, 0, 55);
      break;
    case 'drainWc':
      cyl(55, 80, pvc, 0, 0, 0);
      cyl(58, 12, pvc, 0, 0, 72);
      break;
    case 'cable':
      plate();
      cyl(9, 22, plateGrey, 0, 0, 10);
      break;
    case 'gas':
      cyl(10, 50, brass, 0, 0, 0);
      box(50, 12, 10, new THREE.MeshStandardMaterial({ color: 0xd9a400, roughness: 0.4 }), 0, 0, 52);
      break;
    case 'duct':
      cyl(66, 40, pvc, 0, 0, 0);
      cyl(60, 42, plateDark, 0, 0, 0.5);
      break;
    default:
      plate();
  }
  if (p.ceiling) {
    g.position.copy(P(p.x, p.y, p.z));
  } else {
    // repère du mur : x le long du mur, z vers la pièce ; posé 1 mm devant la surface du mur
    g.applyMatrix4(wallBasis({ dx: p.dx, dy: p.dy, nx: p.nx, ny: p.ny }));
    g.position.copy(P(p.x + p.nx, p.y + p.ny, p.z));
  }
  g.userData.wallOf = p.wall || null;
  return g;
}

function buildNetPoints(d) {
  const g = new THREE.Group();
  for (const p of d.netPoints || []) g.add(buildNetPoint(p, d));
  return g;
}

// un groupe par objet : déplacer un objet ne reconstruit pas les autres
const objectGroups = new Map(); // uid → { sig, obj, o }
function syncObjects(d) {
  const list = [...(d.objects || []), ...(d.basins || []), ...(d.kitchenFixtures || [])];
  const keep = new Set(list.map((o) => o.uid));
  for (const [uid, cur] of [...objectGroups]) {
    if (!keep.has(uid)) {
      scene.remove(cur.obj);
      disposeTree(cur.obj);
      objectGroups.delete(uid);
    }
  }
  for (const o of list) {
    try {
      const sig = JSON.stringify([o, d.style?.faucet_finish]);
      const cur = objectGroups.get(o.uid);
      if (cur && cur.sig === sig) continue;
      if (cur) {
        // simple déplacement ou rotation d'un modèle 3D du catalogue libre dont la géométrie ne change pas
        const same = cur.o.kind === 'model' && cur.o.type === o.type && cur.o.file === o.file && cur.o.w === o.w && cur.o.h === o.h && cur.o.d === o.d;
        if (same) {
          cur.obj.position.copy(P(o.x, o.y, o.z));
          cur.obj.rotation.y = -o.rot * Math.PI / 180;
          cur.sig = sig;
          cur.o = o;
          continue;
        }
        scene.remove(cur.obj);
        disposeTree(cur.obj);
      }
      const obj = buildObject(o, d);
      scene.add(obj);
      objectGroups.set(o.uid, { sig, obj, o });
    } catch (err) {
      console.error('syncObjects error for object:', o, err);
    }
  }
}

/** Matériaux communs à toute la scène : jamais libérés (sinon recompilés à chaque mise à jour). */
let sharedMats = null;
function isShared(m) {
  if (!sharedMats) sharedMats = new Set([mirrorMat, ceramic, ceramicIn, chrome, glass, greyMat, darkMat, plateMat, plateDark, plateGrey, pvc, brass]);
  return sharedMats.has(m) || m.userData.cached;
}

/** Libère la mémoire graphique d'un ensemble retiré de la scène (géométries, matériaux propres).
 * Les textures (en cache, partagées) et les modèles glTF (en cache) sont gardés. */
function disposeTree(root) {
  root.traverse((o) => {
    if (o.userData.cached) return;
    if (o.geometry) o.geometry.dispose();
    const own = o.userData.sketchOrig ?? o.material;
    const ms = Array.isArray(own) ? own : own ? [own] : [];
    for (const m of ms) {
      if (isShared(m)) continue;
      if (m.userData.ownMap && m.map) m.map.dispose();
      m.dispose();
    }
  });
}

function sync(key, sig, build) {
  const cur = groups.get(key);
  if (cur && cur.sig === sig) return;
  if (cur) {
    scene.remove(cur.obj);
    disposeTree(cur.obj);
  }
  const obj = build();
  scene.add(obj);
  groups.set(key, { sig, obj });
}

// ------------------------------------------------------------------ occlusion ambiante précalculée

/** Empreintes au sol (mm) : plinthes, panneaux et objets touchant réellement le sol. */
function groundFootprints(d) {
  const out = [];
  for (const b of d.solids || []) {
    // Ne retenir que les éléments reposant réellement au sol (z0 < 30) comme les plinthes et panneaux
    if (b.top || b.z0 > 30 || (b.z1 - b.z0) < 30) continue;
    out.push([Math.min(b.x0, b.x1), Math.min(b.y0, b.y1), Math.max(b.x0, b.x1), Math.max(b.y0, b.y1)]);
  }
  for (const o of [...(d.objects || [])]) {
    if (o.z > 30 || o.h <= 20) continue;
    const turned = (o.rot % 180) !== 0;
    const fw = turned ? o.d : o.w, fd = turned ? o.w : o.d;
    out.push([o.x - fw / 2, o.y - fd / 2, o.x + fw / 2, o.y + fd / 2]);
  }
  return out;
}

/** Ombre de contact douce sous les meubles et le long des murs, dessinée une fois dans une texture
 * (au lieu d'un calcul d'occlusion à chaque image) : les meubles « touchent » le sol de façon naturelle. */
function buildAO(d) {
  const g = new THREE.Group();
  const r = d.room;
  const pp = Math.min(0.14, 1024 / Math.max(r.w, r.d)); // pixels par mm
  const cw = Math.max(2, Math.ceil(r.w * pp)), ch = Math.max(2, Math.ceil(r.d * pp));
  const cv = document.createElement('canvas');
  cv.width = cw;
  cv.height = ch;
  const ctx = cv.getContext('2d');
  // le sol réel (pièce à contour libre) : rien en dehors
  const outline = new Path2D();
  const poly = d.floorPoly || [[0, 0], [r.w, 0], [r.w, r.d], [0, r.d]];
  poly.forEach(([x, y], i) => (i ? outline.lineTo(x * pp, y * pp) : outline.moveTo(x * pp, y * pp)));
  outline.closePath();
  ctx.save();
  ctx.clip(outline);
  // pied de mur : dégradé doux et régulier
  for (let i = 1; i <= 4; i++) {
    ctx.lineWidth = i * 16 * pp;
    ctx.strokeStyle = 'rgba(0,0,0,0.035)';
    ctx.stroke(outline);
  }
  // sous et autour des meubles : ombre de contact douce et floutée (sans dents de scie ni triangles)
  const fp = groundFootprints(d);
  if (fp.length > 0) {
    if (ctx.filter !== undefined) {
      ctx.filter = `blur(${Math.max(2, Math.round(18 * pp))}px)`;
      ctx.fillStyle = 'rgba(0,0,0,0.18)';
      for (const [x0, y0, x1, y1] of fp) {
        ctx.fillRect(x0 * pp, y0 * pp, (x1 - x0) * pp, (y1 - y0) * pp);
      }
      ctx.filter = 'none';
    } else {
      // Fallback si filter non supporté
      for (let i = 0; i < 3; i++) {
        const grow = i * 6;
        ctx.fillStyle = 'rgba(0,0,0,0.06)';
        for (const [x0, y0, x1, y1] of fp) {
          ctx.fillRect((x0 - grow) * pp, (y0 - grow) * pp, (x1 - x0 + 2 * grow) * pp, (y1 - y0 + 2 * grow) * pp);
        }
      }
    }
  }
  ctx.restore();
  const tex = new THREE.CanvasTexture(cv);
  tex.colorSpace = THREE.NoColorSpace;
  // texture noire, transparente là où il n'y a pas d'ombre (libérée avec le matériau)
  const mat = new THREE.MeshBasicMaterial({ map: tex, transparent: true, depthWrite: false, toneMapped: false, polygonOffset: true, polygonOffsetFactor: -2 });
  mat.userData.ownMap = true;
  const plane = new THREE.Mesh(new THREE.PlaneGeometry(r.w * S, r.d * S), mat);
  plane.rotation.x = -Math.PI / 2;
  plane.position.set(r.w * S / 2, 0.0015, r.d * S / 2);
  plane.renderOrder = 1;
  plane.raycast = () => {}; // ne gêne pas le toucher
  g.add(plane);
  return g;
}

let lastFit = null;

/** « Tout afficher » : même direction de regard, toute la pièce (ou les meubles en présentation) centrée dans le cadre. */
function fitCamera(d) {
  const bb = new THREE.Box3();
  if (d.studio) for (const [key, v] of groups) if (key.startsWith('item:')) bb.expandByObject(v.obj);
  if (bb.isEmpty()) bb.set(new THREE.Vector3(0, 0, 0), new THREE.Vector3(d.room.w * S, Math.min(2.4, (d.room.h || 2400) * S), d.room.d * S));
  const c = bb.getCenter(new THREE.Vector3());
  const dir = camera.position.clone().sub(controls.target);
  if (dir.lengthSq() < 1e-6) dir.set(0, 0.7, 1);
  const probe = camera.clone();
  probe.position.copy(c).add(dir.normalize().multiplyScalar(bb.getSize(new THREE.Vector3()).length() * 1.4));
  for (let pass = 0; pass < 5; pass++) {
    probe.lookAt(c);
    probe.updateMatrixWorld();
    probe.matrixWorldInverse.copy(probe.matrixWorld).invert();
    let most = 0.01;
    for (let k = 0; k < 8; k++) {
      const v = new THREE.Vector3(k & 1 ? bb.max.x : bb.min.x, k & 2 ? bb.max.y : bb.min.y, k & 4 ? bb.max.z : bb.min.z);
      const p = v.clone().applyMatrix4(probe.matrixWorldInverse);
      const q = v.project(probe);
      most = Math.max(most, p.z < -0.01 ? Math.max(Math.abs(q.x), Math.abs(q.y)) : 2);
    }
    probe.position.sub(c).multiplyScalar(most / 0.9).add(c);
  }
  camAnim = { p0: camera.position.clone(), t0: controls.target.clone(), p1: probe.position.clone(), t1: c, k: 0 };
}

// ------------------------------------------------------------------ fond, mode croquis, réseaux tracés

let bgKey = null;
/** Fond de la scène : couleur unie, ou dégradé vertical (ciel) ; blanc en présentation. */
function applyBackground(d) {
  const bg = d.studio ? [0xffffff] : d.bg || [0xeef1f3];
  const key = bg.join();
  if (key === bgKey) return;
  bgKey = key;
  if (scene.background && scene.background.isTexture) scene.background.dispose();
  if (bg.length < 2) {
    scene.background = new THREE.Color(bg[0]);
    return;
  }
  const cv = document.createElement('canvas');
  cv.width = 4;
  cv.height = 256;
  const ctx = cv.getContext('2d');
  const grad = ctx.createLinearGradient(0, 0, 0, 256);
  const hex = (c) => '#' + c.toString(16).padStart(6, '0');
  grad.addColorStop(0, hex(bg[0]));
  grad.addColorStop(1, hex(bg[1]));
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, 4, 256);
  const tex = new THREE.CanvasTexture(cv);
  tex.colorSpace = THREE.SRGBColorSpace;
  scene.background = tex;
}

const sketchMat = new THREE.MeshLambertMaterial({ color: 0xffffff, polygonOffset: true, polygonOffsetFactor: 1, polygonOffsetUnits: 1 });
const sketchGlass = new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.15, depthWrite: false });
const sketchLine = new THREE.LineBasicMaterial({ color: 0x2b2f33 });
sketchMat.userData.cached = sketchGlass.userData.cached = sketchLine.userData.cached = true;
const edgeCache = new Map(); // géométrie → arêtes
let lookNow = 'real';

/** Mode croquis : surfaces blanches et arêtes tracées au trait ; réaliste : les matériaux reviennent. */
function applyLook(look) {
  const sketch = look === 'sketch';
  if (!sketch && lookNow !== 'sketch') return;
  lookNow = look;
  const nodes = [];
  scene.traverse((o) => nodes.push(o));
  for (const o of nodes) {
    if (!o.isMesh || o.userData.sketchEdge || o.userData.netRun) continue;
    if (sketch) {
      if (o.userData.sketchOrig) continue;
      const m0 = Array.isArray(o.material) ? o.material[0] : o.material;
      if (!m0 || m0.visible === false) continue;
      // ombres au sol, reflets : sans objet dans un croquis
      if (m0.isMeshBasicMaterial && m0.transparent && m0.map) {
        o.userData.sketchOrig = o.material;
        o.userData.sketchHidden = o.visible;
        o.visible = false;
        continue;
      }
      o.userData.sketchOrig = o.material;
      o.material = m0.transparent && m0.opacity < 0.6 ? sketchGlass : sketchMat;
      const geo = o.geometry;
      if (!geo || !geo.attributes.position) continue;
      let eg = edgeCache.get(geo.uuid);
      if (!eg) {
        if (geo.attributes.position.count > 120000) continue; // modèle très détaillé : surfaces seules
        eg = new THREE.EdgesGeometry(geo, 28);
        eg.userData.cached = true;
        edgeCache.set(geo.uuid, eg);
      }
      const ln = new THREE.LineSegments(eg, sketchLine);
      ln.userData.sketchEdge = true;
      ln.userData.cached = true;
      ln.raycast = () => {};
      o.add(ln);
    } else if (o.userData.sketchOrig) {
      o.material = o.userData.sketchOrig;
      delete o.userData.sketchOrig;
      if ('sketchHidden' in o.userData) {
        o.visible = o.userData.sketchHidden;
        delete o.userData.sketchHidden;
      }
      for (const c of [...o.children]) if (c.userData.sketchEdge) o.remove(c);
    }
  }
  if (!sketch) {
    for (const eg of edgeCache.values()) eg.dispose();
    edgeCache.clear();
  }
  invalidate(true);
}

const wireMats = new Map();
function wireMat(w, color) {
  let m = wireMats.get(w);
  if (m) return m;
  if (w === 'PE') {
    // terre : rayures vert / jaune
    const cv = document.createElement('canvas');
    cv.width = 4;
    cv.height = 32;
    const ctx = cv.getContext('2d');
    ctx.fillStyle = '#3fa142';
    ctx.fillRect(0, 0, 4, 32);
    ctx.fillStyle = '#f2d21b';
    ctx.fillRect(0, 0, 4, 12);
    const tex = new THREE.CanvasTexture(cv);
    tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
    tex.colorSpace = THREE.SRGBColorSpace;
    m = new THREE.MeshStandardMaterial({ map: tex, roughness: 0.55 });
  } else {
    m = new THREE.MeshStandardMaterial({ color, roughness: w === 'gas' || w === 'drain' ? 0.35 : 0.55, metalness: w === 'gas' ? 0.35 : 0 });
  }
  m.userData.cached = true;
  wireMats.set(w, m);
  return m;
}

/** Réseaux tracés : conducteurs depuis le tableau, tuyaux d'eau, évacuations et gaz le long des murs. */
function buildNets(n) {
  const g = new THREE.Group();
  if (!n) return g;
  // murs de la pièce : chaque tronçon suit la visibilité du mur qui le porte
  const walls = [];
  groups.get('room')?.obj.traverse((o) => {
    if (o.userData.wall) walls.push(o.userData.wall);
  });
  const wallOf = (a, b) => {
    const mx = (a.x + b.x) / 2, mz = (a.z + b.z) / 2;
    let best = null, bd = 0.12;
    for (const w of walls) {
      const dd = Math.abs((mx - w.ox * S) * w.nx + (mz - w.oy * S) * w.ny);
      if (dd < bd) {
        bd = dd;
        best = w.id;
      }
    }
    return best;
  };
  const up = new THREE.Vector3(0, 1, 0);
  for (const run of n.runs || []) {
    const mat = wireMat(run.w, n.colors?.[run.w] ?? 0x888888);
    const r = Math.max(4, run.r) * S;
    const pts = run.p.map(([x, y, z]) => P(x, y, z));
    for (let i = 1; i < pts.length; i++) {
      const a = pts[i - 1], b = pts[i];
      const len = a.distanceTo(b);
      if (len < 1e-4) continue;
      const geo = new THREE.CylinderGeometry(r, r, len, 10, 1, true);
      if (run.w === 'PE') {
        const uv = geo.attributes.uv;
        for (let k = 0; k < uv.count; k++) uv.setY(k, uv.getY(k) * len / 0.03);
      }
      const c = new THREE.Mesh(geo, mat);
      c.position.copy(a).add(b).multiplyScalar(0.5);
      c.quaternion.setFromUnitVectors(up, b.clone().sub(a).normalize());
      c.userData.netRun = true;
      c.castShadow = false;
      c.raycast = () => {};
      const w = wallOf(a, b);
      if (w) c.userData.wallOf = w;
      g.add(c);
      if (i < pts.length - 1) {
        const j = new THREE.Mesh(new THREE.SphereGeometry(r, 10, 8), mat);
        j.position.copy(b);
        j.userData.netRun = true;
        j.raycast = () => {};
        if (w) j.userData.wallOf = w;
        g.add(j);
      }
    }
  }
  // tableau électrique : coffret blanc à porte fumée, rangées de disjoncteurs
  if (n.board) {
    const [x, y, z, nx, ny, dx, dy] = n.board;
    const box = new THREE.Group();
    const body = new THREE.Mesh(new THREE.BoxGeometry(0.32, 0.46, 0.1), new THREE.MeshStandardMaterial({ color: 0xf4f5f6, roughness: 0.5 }));
    box.add(body);
    const face = new THREE.Mesh(new THREE.PlaneGeometry(0.27, 0.38), new THREE.MeshStandardMaterial({ color: 0x5c6670, roughness: 0.2, transparent: true, opacity: 0.55 }));
    face.position.z = 0.0505;
    box.add(face);
    const brk = new THREE.MeshStandardMaterial({ color: 0x23272b, roughness: 0.5 });
    for (let row = 0; row < 3; row++) {
      for (let k = 0; k < 8; k++) {
        const b = new THREE.Mesh(new THREE.BoxGeometry(0.026, 0.07, 0.02), k === 0 ? new THREE.MeshStandardMaterial({ color: 0x1e63c8 }) : brk);
        b.position.set(-0.105 + k * 0.03, 0.12 - row * 0.12, 0.04);
        box.add(b);
      }
    }
    box.position.copy(P(x, y, z));
    box.position.x += nx * 0.05;
    box.position.z += ny * 0.05;
    box.lookAt(box.position.clone().add(new THREE.Vector3(nx, 0, ny)));
    const wb = wallOf(box.position, box.position);
    box.traverse((o) => {
      o.raycast = () => {};
      o.userData.netRun = true;
      if (wb) o.userData.wallOf = wb;
    });
    void dx;
    void dy;
    g.add(box);
  }
  return g;
}

function applyScene(d) {
  data = d;
  doors.length = 0;
  applyBackground(d);
  sync('room', JSON.stringify([d.studio || '', d.room, d.walls, d.floor, d.wall, d.splashMat, d.splash]), () => buildRoom(d));
  sync('lights', JSON.stringify(d.lights || []), () => buildLights(d));
  const uids = [...new Set(d.items.map((i) => i.uid))];
  // les portes sont reconstruites avec leur groupe : on vide la liste et on la remplit pour tous
  for (const key of [...groups.keys()]) {
    if (key.startsWith('item:') && !uids.includes(key.slice(5))) {
      scene.remove(groups.get(key).obj);
      disposeTree(groups.get(key).obj);
      groups.delete(key);
    }
  }
  for (const uid of uids) {
    const sig = JSON.stringify([d.solids.filter((x) => x.uid === uid), d.fronts.filter((x) => x.uid === uid)]);
    const cur = groups.get('item:' + uid);
    if (cur && cur.sig === sig) {
      cur.obj.traverse((o) => {
        if (o.userData.door) doors.push(o.userData.door);
      });
      continue;
    }
    const start = doors.length;
    sync('item:' + uid, sig, () => {
      const g = buildItem(d, uid);
      return bakeStatic(g, new Set(doors.slice(start).map((x) => x.pivot)));
    });
    for (let i = start; i < doors.length; i++) doors[i].pivot.userData.door = doors[i];
  }
  sync('others', JSON.stringify([d.solids.filter((x) => !x.uid), d.tops]), () => bakeStatic(buildOthers(d)));
  syncObjects(d);
  sync('netPoints', JSON.stringify([d.netPoints || [], d.socketFinish]), () => buildNetPoints(d));
  sync('ao', JSON.stringify([d.studio || '', d.room, d.floorPoly || null, groundFootprints(d)]), () => (d.studio ? new THREE.Group() : buildAO(d)));
  sync('nets3d', JSON.stringify([d.nets3d || null, d.room, d.walls]), () => buildNets(d.nets3d));
  applyLook(d.look || 'real');
  // sélection : boîte orange
  if (selBox) {
    scene.remove(selBox);
    selBox = null;
  }
  let g = d.selected && groups.get('item:' + d.selected);
  if (!g && d.selectedObject) g = objectGroups.get(d.selectedObject);
  if (g) {
    selBox = new THREE.BoxHelper(g.obj, 0xff7a1a);
    scene.add(selBox);
  }
  // caméra : rotation / zoom demandés par les boutons de l'application
  const r = d.room;
  const target = new THREE.Vector3(r.w * S / 2, 0.9, r.d * S / 2);
  baseDist = Math.max(r.w, r.d) * S * 1.55 + 1;
  const view = d.cam || 0;
  if (lastFit !== null && (d.fit || 0) !== lastFit && view !== 2) {
    fitCamera(d);
    lastYaw = d.yaw;
    lastZoom = d.zoom;
    lastView = view;
  } else if (lastYaw !== null && view === lastView && (d.fit || 0) === lastFit && (Math.abs(d.yaw - lastYaw) > 1e-6 || Math.abs(d.zoom - lastZoom) > 1e-6)) {
    // boutons zoom et rotation : à partir du point de vue actuel, sans revenir à l'angle de départ
    const p0 = camAnim ? camAnim.p1 : camera.position, t0 = camAnim ? camAnim.t1 : controls.target;
    const v = p0.clone().sub(t0).applyAxisAngle(new THREE.Vector3(0, 1, 0), lastYaw - d.yaw).multiplyScalar((lastZoom || 1) / (d.zoom || 1));
    camAnim = { p0: camera.position.clone(), t0: controls.target.clone(), p1: v.add(t0), t1: t0.clone(), k: 0 };
    lastYaw = d.yaw;
    lastZoom = d.zoom;
  } else if (lastYaw === null || (lastFit !== null && (d.fit || 0) !== lastFit) || Math.abs(d.yaw - lastYaw) > 1e-6 || Math.abs(d.zoom - lastZoom) > 1e-6 || view !== lastView) {
    // fenêtre étroite : on recule pour garder toute la pièce dans le cadre
    const dist = (baseDist / (d.zoom || 1)) * Math.max(1, 1.4 / (camera.aspect || 1));
    const az = -d.yaw;
    const pos = new THREE.Vector3();
    const look = target.clone();
    if (view === 1) {
      // vue de dessus : à la verticale, le lacet garde l'orientation du plan
      pos.set(target.x + Math.sin(az) * 0.02, target.y + dist * 1.15, target.z + Math.cos(az) * 0.02);
    } else if (view === 2) {
      // à hauteur d'œil (1,60 m), dans la pièce : ce que voit quelqu'un debout
      const back = Math.min(Math.max(r.w, r.d) * S * 0.48, dist) / (d.zoom || 1);
      look.y = 1.15;
      pos.set(target.x + Math.sin(az) * back, 1.6, target.z + Math.cos(az) * back);
    } else {
      pos.set(target.x + Math.sin(az) * dist, target.y + dist * 0.72, target.z + Math.cos(az) * dist);
    }
    if (lastYaw === null) {
      camera.position.copy(pos);
      controls.target.copy(look);
      controls.update();
    } else {
      // déplacement fluide vers la nouvelle vue (0,45 s)
      camAnim = { p0: camera.position.clone(), t0: controls.target.clone(), p1: pos, t1: look, k: 0 };
    }
    lastYaw = d.yaw;
    lastZoom = d.zoom;
    lastView = view;
  }
  lastFit = d.fit || 0;
  // présentation : cadrage serré sur les meubles, de trois quarts ; retour à la vue de la pièce en sortant
  if ((d.studio || '') !== lastStudio && (!!d.studio !== !!lastStudio || lastStudio === null)) {
    if (d.studio) {
      const bb = new THREE.Box3();
      for (const [key, v] of groups) if (key.startsWith('item:')) bb.expandByObject(v.obj);
      if (!bb.isEmpty()) {
        const c = bb.getCenter(new THREE.Vector3()), size = bb.getSize(new THREE.Vector3());
        // téléobjectif, à hauteur d'œil, de trois quarts : les verticales restent droites ;
        // on se place du côté ouvert (l'autre mur meublé reste visible)
        camera.fov = 30;
        camera.updateProjectionMatrix();
        const half = Math.tan((camera.fov * Math.PI) / 360), asp = camera.aspect || 1.6;
        const dist2 = Math.max(size.y / (2 * half), (size.x + size.z * 0.45) / (2 * half * asp)) * 1.16 + size.z * 0.5;
        // devant les façades : la moyenne des murs meublés donne la direction (de trois quarts sur un seul mur)
        const [vx, vy] = d.studioDir || [0, 1];
        const el = ((d.studioHigh ? 34 : 11) * Math.PI) / 180;
        camera.position.set(c.x + vx * Math.cos(el) * dist2, c.y + Math.sin(el) * dist2, c.z + vy * Math.cos(el) * dist2);
        // tout le meuble dans le cadre, au plus près
        for (let pass = 0; pass < 4; pass++) {
          camera.lookAt(c);
          camera.updateMatrixWorld();
          let most = 0;
          for (let k = 0; k < 8; k++) {
            const v = new THREE.Vector3(k & 1 ? bb.max.x : bb.min.x, k & 2 ? bb.max.y : bb.min.y, k & 4 ? bb.max.z : bb.min.z).project(camera);
            most = Math.max(most, Math.abs(v.x), Math.abs(v.y));
          }
          camera.position.sub(c).multiplyScalar(most / 0.9).add(c);
        }
        controls.target.copy(c);
        controls.update();
        camAnim = null;
      }
    } else lastYaw = null; // recadre la pièce au prochain passage
  }
  const leaving = lastStudio && !d.studio;
  lastStudio = d.studio || '';
  // éclairage : trois sources en présentation, la pièce sinon
  hemiLight.intensity = d.studio ? 0.85 : 1.15;
  ambLight.intensity = d.studio ? 0.35 : 0.45;
  fillLight.intensity = d.studio ? 0 : 0.75;
  sideLight.intensity = d.studio ? 0.55 : 0;
  rimLight.intensity = d.studio ? 0.4 : 0;
  sideLight.position.set(target.x + 4, 2.6, target.z + 4);
  sideLight.target.position.copy(target);
  rimLight.position.set(target.x, 4, target.z - 5);
  rimLight.target.position.copy(target);
  if (leaving) {
    camera.fov = 38;
    camera.updateProjectionMatrix();
    const dist = baseDist * Math.max(1, 1.4 / (camera.aspect || 1));
    camera.position.set(target.x - Math.sin(d.yaw) * dist, target.y + dist * 0.72, target.z + Math.cos(d.yaw) * dist);
    controls.target.copy(target);
    controls.update();
    lastYaw = d.yaw;
    lastZoom = d.zoom;
    lastView = d.cam || 0;
  }
  // lumière principale cadrée sur la pièce (positionnée en hauteur et orientée pour des ombres douces et réalistes)
  // elle vient de devant les façades : on voit leur matière, les ombres partent vers les murs
  {
    const [lx, ly] = d.studioDir || [0.12, 1];
    const c = Math.cos(-0.45), q = Math.sin(-0.45);
    sun.position.set(target.x + (lx * c - ly * q) * 4.3, 6.0, target.z + (lx * q + ly * c) * 4.3);
  }
  sun.target.position.copy(target);
  const half = Math.max(r.w, r.d) * S;
  Object.assign(sun.shadow.camera, { left: -half, right: half, top: half, bottom: -half, near: 0.5, far: 20 });
  sun.shadow.camera.updateProjectionMatrix();
  invalidate(true);
}

// ------------------------------------------------------------------ animation et murs masqués

function animate() {
  raf = requestAnimationFrame(animate);
  if (hdRunning()) return; // le rendu HD a la main
  try {
    const now = performance.now();
    const dt = Math.min(0.1, (now - lastT) / 1000);
    lastT = now;
    if (camAnim) {
      camAnim.k = Math.min(1, camAnim.k + dt / 0.45);
      const e = camAnim.k * camAnim.k * (3 - 2 * camAnim.k);
      camera.position.lerpVectors(camAnim.p0, camAnim.p1, e);
      controls.target.lerpVectors(camAnim.t0, camAnim.t1, e);
      if (camAnim.k >= 1) camAnim = null;
      invalidate();
    }
    // caméra : inertie du geste (amortissement) ; vrai si elle a bougé
    if (controls && controls.update()) invalidate();
    // fin de geste et caméra arrêtée : pleine résolution
    if (lowRes && !interacting && needsRender <= 0) {
      lowRes = false;
      setDpr(fullDpr());
      invalidate();
    }
    let moving = false;
    if (data) {
      // ouverture : vers la cible (limitée par les obstacles), 0,6 s
      const open = data.open || {};
      const seen = new Set();
      for (const dr of doors) {
        const key = dr.uid + '#' + dr.k;
        if (seen.has(key)) continue;
        seen.add(key);
        const target = open[key] ?? open[dr.uid] ?? 0;
        const p0 = progress.get(key) ?? 0;
        const p = p0 + Math.sign(target - p0) * Math.min(Math.abs(target - p0), dt / 0.6);
        if (p !== p0) moving = true;
        if (p <= 0 && target === 0) progress.delete(key);
        else progress.set(key, p);
      }
    }
    if (moving) invalidate(true); // portes et tiroirs en mouvement : leurs ombres aussi
    if (needsRender <= 0) {
      stats.idleSkips++;
      return;
    }
    needsRender--;
    if (data) {
      for (const dr of doors) {
        const p = progress.get(dr.uid + '#' + dr.k) ?? 0;
        const e = p * p * (3 - 2 * p);
        dr.pivot.rotation.set(0, 0, 0);
        dr.pivot.position.set(0, 0, 0);
        if (dr.kind === 'door') dr.pivot.rotateY((dr.hinge === 'left' ? -1 : 1) * e * Math.PI / 2);
        else if (dr.kind === 'flapUp') dr.pivot.rotateX(-e * Math.PI * 100 / 180);
        else if (dr.kind === 'flapDown') dr.pivot.rotateX(e * Math.PI * 85 / 180);
        else if (dr.kind === 'rack') dr.pivot.position.z = Math.max(0, p - 0.55) / 0.45 * dr.travel; // une fois la porte basse
        else if (dr.kind === 'drawer') dr.pivot.translateZ(e * Math.min(450, dr.depth - 120) * S);
      }
      // murs entre la caméra et la cuisine : masqués
      const cam = camera.position;
      for (const { obj } of groups.values()) {
        obj.traverse((o) => {
          const w = o.userData.wall;
          if (w) o.visible = (cam.x - w.ox * S) * w.nx + (cam.z - w.oy * S) * w.ny > 0;
        });
      }
      const walls = new Map();
      groups.get('room')?.obj.traverse((o) => {
        if (o.userData.wall) walls.set(o.userData.wall.id, o.visible);
      });
      // un mur qui apparaît ou disparaît change les ombres
      const sigWalls = [...walls.values()].join();
      if (sigWalls !== lastWalls) {
        lastWalls = sigWalls;
        shadowsDirty = true;
      }
      for (const key of ['room', 'netPoints', 'nets3d']) {
        groups.get(key)?.obj.traverse((o) => {
          if (o.userData.wallOf) o.visible = walls.get(o.userData.wallOf) ?? true;
        });
      }
    }
    if (lookNow === 'sketch' && (stats.frames % 40) === 0) applyLook('sketch');
    if (selBox) selBox.update();
    reportSelection();
    if (shadowsDirty) {
      renderer.shadowMap.needsUpdate = true;
      shadowsDirty = false;
      stats.shadowUpdates++;
    }
    stats.frames++;
    renderer.render(scene, camera);
  } catch (err) {
    console.error('animate loop error:', err);
  }
}
let lastWalls = '';

// ------------------------------------------------------------------ souris : choisir, glisser, double clic

const ray = new THREE.Raycaster();
const ndc = new THREE.Vector2();
let press = null; // { x, y, uid, item, plane, start, moved }

/** Point touché dans le repère de la vue, même quand l'app est affichée tournée d'un quart de tour
 * (tablette tenue droite) : le rectangle à l'écran est alors « couché ». */
function localXY(ev) {
  const el = renderer.domElement;
  const r = el.getBoundingClientRect();
  const w = el.clientWidth || r.width, h = el.clientHeight || r.height;
  const dx = ev.clientX - r.left, dy = ev.clientY - r.top;
  if (Math.abs(r.width - w) < 2 || Math.abs(r.width - h) >= 2) return [dx, dy, w, h];
  // tourné de 90° dans le sens horaire : x de la vue vers le bas de l'écran, y vers la gauche
  return [dy, r.width - dx, w, h];
}

function pick(ev) {
  const [lx, ly, w, h] = localXY(ev);
  ndc.set((lx / w) * 2 - 1, -(ly / h) * 2 + 1);
  ray.setFromCamera(ndc, camera);
  const hits = ray.intersectObjects(scene.children, true).filter((h) => h.object.visible && !(h.object instanceof THREE.LineSegments));
  for (const h of hits) {
    let o = h.object;
    while (o && !o.userData.uid) o = o.parent;
    if (o) return { uid: o.userData.uid, point: h.point, object: h.object };
    if (h.object.userData.wall || h.object.userData.wallOf) continue;
    return null;
  }
  return null;
}

function planeHit(ev, plane) {
  const [lx, ly, w, h] = localXY(ev);
  ndc.set((lx / w) * 2 - 1, -(ly / h) * 2 + 1);
  ray.setFromCamera(ndc, camera);
  const p = new THREE.Vector3();
  return ray.ray.intersectPlane(plane, p) ? p : null;
}

let blockedInput = false; // un panneau de l'application est sous le pointeur

function onDown(ev) {
  if (ev.button !== 0 || blockedInput) return;
  const h = pick(ev);
  press = { x: ev.clientX, y: ev.clientY, uid: h?.uid ?? null, moved: false };
  if (h && data?.editable) {
    const item = data.items.find((i) => i.uid === h.uid);
    if (item) {
      // plan vertical parallèle au mur de l'élément, passant par le point saisi
      const n = new THREE.Vector3(item.nx, 0, item.ny);
      press.item = item;
      press.plane = new THREE.Plane().setFromNormalAndCoplanarPoint(n, h.point);
      press.start = h.point.clone();
      controls.enabled = false;
    }
  }
}

function onMove(ev) {
  if (!press || !press.item) return;
  if (!press.moved && Math.hypot(ev.clientX - press.x, ev.clientY - press.y) < 5) return;
  if (!press.moved) {
    press.moved = true;
    gestureStart();
    handler('dragStart', press.uid);
  }
  const p = planeHit(ev, press.plane);
  if (!p) return;
  const it = press.item;
  const ds = ((p.x - press.start.x) * it.dx + (p.z - press.start.z) * it.dy) / S;
  const dz = (p.y - press.start.y) / S;
  handler('drag', press.uid, it.s + ds, it.canZ ? it.z + dz : it.z);
}

function onUp(ev) {
  if (!press) return;
  const moved = press.moved || Math.hypot(ev.clientX - press.x, ev.clientY - press.y) >= 5;
  if (press.item && press.moved) {
    gestureEnd();
    handler('dragEnd', press.uid);
  }
  else if (!moved) handler('pick', press.uid);
  controls.enabled = !blockedInput;
  press = null;
}

function onDouble(ev) {
  if (blockedInput) return;
  const h = pick(ev);
  if (!h) return;
  const mine = doors.filter((x) => x.uid === h.uid);
  const count = mine.filter((x) => !x.follows).length;
  let part = -1;
  // la porte ou le tiroir touché…
  for (let o = h.object; o && part < 0; o = o.parent) if (o.userData.door) part = o.userData.door.k;
  // … ou celui devant l'endroit touché (intérieur, chant, gorge)
  if (part < 0) {
    let best = 0.4;
    for (const dr of mine) {
      if (!dr.f || !dr.part) continue;
      const x = h.point.x / S - dr.f.ox, y = h.point.z / S - dr.f.oy, z = h.point.y / S;
      const s = x * dr.f.dx + y * dr.f.dy;
      const off = Math.max(dr.part.s0 - s, s - dr.part.s1, dr.part.z0 - z, z - dr.part.z1, 0) / 1000;
      if (off < best) {
        best = off;
        part = dr.k;
      }
    }
  }
  handler('dbl', h.uid, part, count);
}

// ------------------------------------------------------------------ montage

let sun;
function init(el) {
  host = el;
  renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: !!window.kitchen3dPreserve });
  {
    const gl = renderer.getContext();
    const log = window.__kxlog || (() => {});
    log('3d', `WebGL ${renderer.capabilities.isWebGL2 ? 2 : 1}, textures max ${renderer.capabilities.maxTextureSize}, hôte ${el?.clientWidth}x${el?.clientHeight}`);
    renderer.domElement.addEventListener('webglcontextlost', () => log('3d', 'contexte WebGL perdu (mémoire ?)'));
    if (gl.isContextLost && gl.isContextLost()) log('3d', 'contexte WebGL perdu dès le départ');
  }
  // Qualité d'affichage optimisée : Retina / iPad (plafonné à 2.5 pour netteté cristalline)
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2.5));
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.shadowMap.autoUpdate = false; // recalculées seulement quand la cuisine change
  // rendu des couleurs fidèle et contrasté
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.05;
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.domElement.style.width = '100%';
  renderer.domElement.style.height = '100%';
  renderer.domElement.style.display = 'block';
  renderer.domElement.style.touchAction = 'none';
  host.appendChild(renderer.domElement);

  scene = new THREE.Scene();
  scene.background = new THREE.Color(0xeef1f3);
  // reflets doux d'une pièce claire : le chrome et l'émail ont enfin quelque chose à refléter
  const pmrem = new THREE.PMREMGenerator(renderer);
  scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
  scene.environmentIntensity = 0.45;
  pmrem.dispose();
  camera = new THREE.PerspectiveCamera(38, 1, 0.05, 100);
  controls = new OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true;
  controls.dampingFactor = 0.12;
  controls.maxPolarAngle = Math.PI * 0.49;
  controls.minDistance = 0.8;
  controls.maxDistance = 25;
  // app affichée tournée d'un quart de tour (tablette tenue droite) : les gestes suivent l'image, pas l'écran
  const rotated = () => {
    const el = renderer.domElement, r = el.getBoundingClientRect();
    const w = el.clientWidth || r.width, h = el.clientHeight || r.height;
    return Math.abs(r.width - w) >= 2 && Math.abs(r.width - h) < 2;
  };
  const rl = controls._rotateLeft.bind(controls), ru = controls._rotateUp.bind(controls), pan = controls._pan.bind(controls);
  controls._rotateLeft = (a) => (rotated() ? ru(-a) : rl(a));
  controls._rotateUp = (a) => (rotated() ? rl(a) : ru(a));
  controls._pan = (x, y) => (rotated() ? pan(y, -x) : pan(x, y));
  controls.addEventListener('start', () => (camAnim = null));
  controls.addEventListener('start', gestureStart);
  controls.addEventListener('end', gestureEnd);
  controls.addEventListener('change', () => invalidate());

  hemiLight = new THREE.HemisphereLight(0xffffff, 0xd0c4b4, 1.15);
  ambLight = new THREE.AmbientLight(0xffffff, 0.45);
  scene.add(hemiLight, ambLight);
  sun = new THREE.DirectionalLight(0xfff6ea, 2.2);
  sun.castShadow = true;
  sun.shadow.mapSize.set(4096, 4096);
  sun.shadow.bias = -0.0002;
  sun.shadow.normalBias = 0.02;
  sun.shadow.radius = 3.5;
  scene.add(sun, sun.target);
  // lumière d'appoint sous les meubles hauts
  const fill = new THREE.PointLight(0xfff2dd, 0.75, 9);
  fill.position.set(1.5, 2.2, 1.2);
  scene.add(fill);
  fillLight = fill;
  // présentation : une lumière d'appoint froide de côté et un liseré par l'arrière (éteints dans la pièce)
  sideLight = new THREE.DirectionalLight(0xf2f6ff, 0);
  rimLight = new THREE.DirectionalLight(0xffffff, 0);
  scene.add(sideLight, sideLight.target, rimLight, rimLight.target);

  const el2 = renderer.domElement;
  el2.addEventListener('pointerdown', onDown);
  window.addEventListener('pointermove', onMove);
  window.addEventListener('pointerup', onUp);
  el2.addEventListener('dblclick', onDouble);
  new ResizeObserver(resize).observe(host);
  resize();
  animate();
}

function resize() {
  if (!host || !renderer) return;
  const w = Math.max(1, host.clientWidth), h = Math.max(1, host.clientHeight);
  renderer.setSize(w, h, false);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
  invalidate();
}

// ------------------------------------------------------------------ réalité augmentée (AR Quick Look)

let arPrepared = null; // { bytes, stats }

/** Repère du coin de la pièce (origine du plan) : un L rouge au sol, à poser sur le vrai coin. */
function cornerMarker() {
  const g = new THREE.Group();
  const m = new THREE.MeshStandardMaterial({ color: 0xe03131, roughness: 0.5 });
  const a = new THREE.Mesh(new THREE.BoxGeometry(0.6, 0.004, 0.03), m);
  a.position.set(0.3, 0.002, 0.015);
  const b = new THREE.Mesh(new THREE.BoxGeometry(0.03, 0.004, 0.6), m);
  b.position.set(0.015, 0.002, 0.3);
  const c = new THREE.Mesh(new THREE.CylinderGeometry(0.035, 0.035, 0.006, 20), m);
  c.position.set(0.015, 0.003, 0.015);
  g.add(a, b, c);
  return g;
}

/**
 * Prépare le paquet USDZ de la scène affichée.
 * opts : { kitchen: bool (meubles, plans, crédence, objets), walls: bool (murs fantômes),
 *          nets: objet réseaux (comme scene.nets3d) ou null, marker: bool, maxTexture, maxVertices }
 * Renvoie les statistiques (JSON) ; le paquet est gardé pour arOpen().
 */
async function arPrepare(opts) {
  if (!scene) throw new Error('vue 3D fermée');
  const roots = [];
  const temp = [];
  const ghosts = new Set();
  const room = groups.get('room')?.obj;
  if (opts.kitchen !== false) {
    for (const [k, v] of groups) if (k.startsWith('item:') || k === 'others') roots.push(v.obj);
    for (const v of objectGroups.values()) roots.push(v.obj);
    room?.children.forEach((o) => o.userData.splash && roots.push(o));
  }
  if (opts.walls) {
    room?.children.forEach((o) => {
      if ((o.userData.wall || o.userData.wallOf) && !o.userData.splash) {
        roots.push(o);
        ghosts.add(o);
      }
    });
  }
  if (opts.nets) {
    const n = buildNets(opts.nets);
    temp.push(n);
    roots.push(n);
    const pts = groups.get('netPoints')?.obj;
    if (pts) roots.push(pts);
  }
  if (opts.marker !== false) {
    const mk = cornerMarker();
    temp.push(mk);
    roots.push(mk);
  }
  const ghost = (o) => {
    for (let x = o; x; x = x.parent) if (ghosts.has(x)) return true;
    return false;
  };
  try {
    arPrepared = await buildUsdz(roots, { ghost, maxTexture: opts.maxTexture, maxVertices: opts.maxVertices });
  } finally {
    for (const t of temp) disposeTree(t);
  }
  return { ...arPrepared.stats, quickLook: arQuickLookSupported() };
}

window.kitchen3d = {
  ready: true,
  /** Réalité augmentée : l'appareil ouvre-t-il les USDZ (iPad / iPhone) ? */
  arSupported() {
    return arQuickLookSupported();
  },
  /** Prépare le paquet AR (opts en JSON) ; promesse des statistiques en JSON. */
  arPrepare(json) {
    return arPrepare(JSON.parse(json || '{}')).then((st) => JSON.stringify(st));
  },
  /** Ouvre le paquet préparé (pendant un toucher) : AR Quick Look, sinon téléchargement. */
  arOpen() {
    if (!arPrepared) return false;
    openUsdz(arPrepared.bytes);
    return true;
  },
  /**
   * Envoie le paquet préparé à l'app native Kitchinox AR (scan RoomPlan) : dépôt sur le serveur local,
   * puis ouverture de kitchinoxar://open?src=… avec les cotes de la pièce (calage automatique). Promesse : true si envoyé.
   */
  async arSendToApp(name) {
    if (!arPrepared) return false;
    const r = await fetch('__ar/scene.usdz', { method: 'POST', body: arPrepared.bytes });
    if (!r.ok) return false;
    const src = new URL('__ar/scene.usdz?t=' + Date.now(), location.href).href;
    const q = new URLSearchParams({ src, name: name || 'Cuisine' });
    if (data?.room) {
      q.set('w', String(Math.round(data.room.w)));
      q.set('d', String(Math.round(data.room.d)));
    }
    location.href = 'kitchinoxar://open?' + q.toString();
    return true;
  },
  /** App native : dépose le paquet préparé sur le serveur interne de l'app (Flutter le partage ensuite). */
  async arUpload() {
    if (!arPrepared) return false;
    const r = await fetch('__ar/scene.usdz', { method: 'POST', body: arPrepared.bytes });
    return r.ok;
  },
  /** Cotes de la pièce affichée, « 3600x3000 » (mm), vide sans scène. */
  arRoomSize() {
    return data?.room ? `${Math.round(data.room.w)}x${Math.round(data.room.d)}` : '';
  },
  /** Taille du paquet préparé (octets), 0 sans paquet. */
  arSize() {
    return arPrepared ? arPrepared.bytes.length : 0;
  },
  arClear() {
    arPrepared = null;
  },
  /** Capture un instantané PNG haute résolution de la vue 3D perspective réelle. */
  capturePng() {
    if (!renderer || !scene || !camera || !host || !host.isConnected) return null; // vue fermée : pas d'image périmée
    renderer.render(scene, camera);
    return renderer.domElement.toDataURL('image/png');
  },
  /** Rendu HD : démarre (w × h pixels, n passes), avancement et image (JSON), arrêt. */
  hdStart(w, h, n) {
    if (!renderer || !scene || !host || !host.isConnected) return false;
    const box = selBox;
    if (box) box.visible = false;
    hdStart({ renderer, scene, camera, sun, hemi: hemiLight, ambient: ambLight, fill: fillLight, done: () => {
      if (box) box.visible = true;
      resize();
      invalidate(true);
    } }, w, h, n);
    return true;
  },
  hdState() {
    return hdState();
  },
  hdStop() {
    hdStop();
  },
  /** Gestes acceptés (false : un panneau de l'application est sous le pointeur, la 3D ne bouge pas). */
  /** Diagnostic : la 3D accepte-t-elle les gestes ? */
  inputOn() {
    return !blockedInput && !!controls?.enabled;
  },
  input(on) {
    blockedInput = !on;
    if (!controls) return;
    if (!on) press = null;
    controls.enabled = on;
  },
  /** Monte la vue dans [el] (élément HTML fourni par Flutter). */
  mount(el) {
    if (host === el) return;
    if (renderer && renderer.domElement.parentElement) renderer.domElement.parentElement.removeChild(renderer.domElement);
    if (!renderer) init(el);
    else {
      host = el;
      el.appendChild(renderer.domElement);
      new ResizeObserver(resize).observe(el);
      resize();
    }
  },
  /** Ajoute une image (pixels RGBA, ligne du haut en premier). */
  addImage(key, w, h, rgba) {
    if (images.has(key)) return;
    const t = new THREE.DataTexture(new Uint8Array(rgba), w, h, THREE.RGBAFormat);
    t.flipY = true;
    t.colorSpace = THREE.SRGBColorSpace;
    t.generateMipmaps = true;
    t.minFilter = THREE.LinearMipmapLinearFilter;
    t.magFilter = THREE.LinearFilter;
    t.anisotropy = 8;
    t.needsUpdate = true;
    images.set(key, t);
    invalidate();
  },
  /** Compteurs du rendu (diagnostic) : images dessinées, ombres recalculées, images évitées au repos. */
  renderStats() {
    return { ...stats, dpr: renderer ? renderer.getPixelRatio() : null, calls: renderer ? renderer.info.render.calls : null, triangles: renderer ? renderer.info.render.triangles : null, geometries: renderer ? renderer.info.memory.geometries : null, textures: renderer ? renderer.info.memory.textures : null };
  },
  /** Scène complète (JSON). */
  setScene(json) {
    if (!renderer) return;
    try {
      applyScene(JSON.parse(json));
    } catch (e) {
      console.error('kitchinox 3D :', e);
    }
  },
  supported() {
    try {
      const c = document.createElement('canvas');
      return !!(c.getContext('webgl2') || c.getContext('webgl'));
    } catch (_) {
      return false;
    }
  },
};

(window.__kxlog || (() => {}))('3d', 'module three_view chargé');
