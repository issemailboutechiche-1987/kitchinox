// Vue 3D temps réel (WebGL, three.js) de kitchinox.
// La scène arrive de Flutter en JSON (mm, repère du plan : x, y vers l'avant, z vers le haut) ;
// les images (façades, intérieurs, textures) arrivent en pixels RGBA et sont mises en cache.
// Repère three.js : X = x, Y = z (haut), Z = y — le plan est « main gauche », ce choix le respecte.

import * as THREE from 'three';
import { OrbitControls } from './vendor/OrbitControls.js';
import { RoomEnvironment } from './vendor/environments/RoomEnvironment.js';
import { mergeGeometries } from './vendor/utils/BufferGeometryUtils.js';

const S = 0.001; // mm → m
const P = (x, y, z) => new THREE.Vector3(x * S, z * S, y * S);

const images = new Map(); // clé → THREE.DataTexture (source)
let renderer, scene, camera, controls, host, raf = 0;
let data = null;
const groups = new Map(); // clé de groupe → { sig, obj }
const doors = []; // { uid, pivot, kind, max }
const progress = new Map(); // uid → ouverture animée 0..1
let selBox = null;
let lastYaw = null, lastZoom = null, lastView = 0, baseDist = 6;
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
  const m = new THREE.MeshStandardMaterial({ roughness: opts.rough ?? 0.5, metalness: 0 });
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
      g.add(mesh);
    }
  }
  return g;
}

/** Une case de façade : volume de 18 mm, image sur la face avant, intérieur derrière. */
// miroir : métal poli qui reflète l'environnement de la pièce
const mirrorMat = new THREE.MeshStandardMaterial({ color: 0xf4f7f8, metalness: 1, roughness: 0.02 });

function buildPart(f, uid, part, depth, carcassColor) {
  const out = new THREE.Group();
  const w = part.s1 - part.s0, h = part.z1 - part.z0;
  const front = f.mirror ? mirrorMat : imageMat(part.img, { rough: 0.45 });
  const edge = new THREE.MeshStandardMaterial({ color: 0xdedbd4, roughness: 0.6 });
  const back = new THREE.MeshStandardMaterial({ color: carcassColor, roughness: 0.7 });
  const geo = new THREE.BoxGeometry(w * S, h * S, 0.018);
  const panel = new THREE.Mesh(geo, [edge, edge, edge, edge, front, back]);
  panel.castShadow = panel.receiveShadow = true;
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
  if (part.kind !== 'static') doors.push({ uid, pivot, kind: part.kind, hinge: part.hinge, depth });
  return out;
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
    case 'chauffe_eau': {
      const r = Math.min(w, d) / 2;
      const body = mesh(new THREE.CapsuleGeometry(r, Math.max(10, h - 2 * r), 16, 48), new THREE.MeshPhysicalMaterial({ color: 0xfafafa, roughness: 0.35, clearcoat: 0.6 }));
      body.position.set(0, h / 2, r);
      m.add(body);
      m.add(at(mesh(new THREE.CylinderGeometry(70, 70, 12, 40), darkMat), 0, h * 0.3, 2 * r - 4).rotateX(Math.PI / 2));
      lcylMM(m, -70, -60, r, 11, 120);
      lcylMM(m, 70, -60, r, 11, 120);
      break;
    }
    case 'kitchen_sink': {
      const mount = o.mount || 'inset';
      const layout = o.layout || 'drainer';
      const sinkMat = o.sinkFinish === 'noir_quartz' ? tapBlack
                    : o.sinkFinish === 'blanc_ceramique' ? ceramic
                    : new THREE.MeshStandardMaterial({ color: 0xc8cdd2, roughness: 0.22, metalness: 0.88 });
      const isUndermount = mount === 'undermount';
      // Sous-plan : lèvre fine biseautée au ras du plan ; Encastré : cadre avec lèvre 5mm au-dessus du plan
      const topY = isUndermount ? 1.5 : 5.0;
      const rimH = isUndermount ? 3.0 : 6.0;
      const rimThick = 26; // largeur des bords du cadre extérieur

      const hasDrainer = layout === 'drainer' || layout === '2_drainer';
      const isDouble = layout === '2' || layout === '2_drainer';
      const bowlD = d * 0.74;
      const cz = d * 0.54;

      // Cadre extérieur ouvert (la cuve reste creuse et visible de haut)
      // Bord gauche et bord droit
      const rimL = mesh(new THREE.BoxGeometry(rimThick, rimH, d), sinkMat);
      rimL.position.set(-hw + rimThick / 2, topY - rimH / 2, d / 2);
      const rimR = mesh(new THREE.BoxGeometry(rimThick, rimH, d), sinkMat);
      rimR.position.set(hw - rimThick / 2, topY - rimH / 2, d / 2);
      // Bord avant
      const rimFront = mesh(new THREE.BoxGeometry(w, rimH, 30), sinkMat);
      rimFront.position.set(0, topY - rimH / 2, d - 15);
      // Gorge arrière (plage de robinetterie)
      const deckDepth = Math.max(70, d * 0.26);
      const rimBack = mesh(new THREE.BoxGeometry(w, rimH, deckDepth), sinkMat);
      rimBack.position.set(0, topY - rimH / 2, deckDepth / 2);
      m.add(rimL, rimR, rimFront, rimBack);

      if (hasDrainer && !isDouble) {
        // 1 bac à gauche + égouttoir design à droite
        const bowlW = Math.min(w * 0.52, 480);
        const bowlX = -hw + bowlW / 2 + 35;
        // Tablier plein sous l'égouttoir
        const drX0 = bowlX + bowlW / 2 + 10;
        const drX1 = hw - rimThick;
        const drW = drX1 - drX0;
        const drainDeck = mesh(new THREE.BoxGeometry(drW, rimH, d - deckDepth - 30), sinkMat);
        drainDeck.position.set((drX0 + drX1) / 2, topY - rimH / 2, deckDepth + (d - deckDepth - 30) / 2);
        m.add(drainDeck);

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
        m.add(mesh(bowl(bowlX, cz, bowlW / 2 - 15, bowlD / 2 - 15, 190, topY - 2, 3.8, 0.6), sinkMat));
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
        const divider = mesh(new THREE.BoxGeometry(20, rimH, d - deckDepth - 30), sinkMat);
        divider.position.set(0, topY - rimH / 2, deckDepth + (d - deckDepth - 30) / 2);
        m.add(divider);

        m.add(mesh(bowl(b1X, cz, singleW / 2 - 10, bowlD / 2 - 15, 190, topY - 2, 3.8, 0.6), sinkMat));
        m.add(at(mesh(new THREE.CylinderGeometry(45, 42, 5, 32), chrome), b1X, topY - 188, cz));
        m.add(at(mesh(new THREE.CylinderGeometry(18, 18, 8, 24), darkMat), b1X, topY - 185, cz));

        m.add(mesh(bowl(b2X, cz, singleW / 2 - 10, bowlD / 2 - 15, 190, topY - 2, 3.8, 0.6), sinkMat));
        m.add(at(mesh(new THREE.CylinderGeometry(45, 42, 5, 32), chrome), b2X, topY - 188, cz));
        m.add(at(mesh(new THREE.CylinderGeometry(18, 18, 8, 24), darkMat), b2X, topY - 185, cz));
      } else {
        // 1 bac simple / compact
        const bowlW = w - 60;
        const bowlX = 0;
        m.add(mesh(bowl(bowlX, cz, bowlW / 2 - 10, bowlD / 2 - 15, 190, topY - 2, 3.8, 0.6), sinkMat));
        m.add(at(mesh(new THREE.CylinderGeometry(45, 42, 5, 32), chrome), bowlX, topY - 188, cz));
        m.add(at(mesh(new THREE.CylinderGeometry(18, 18, 8, 24), darkMat), bowlX, topY - 185, cz));
        const overFlow = mesh(new THREE.BoxGeometry(32, 12, 4), chrome);
        overFlow.position.set(bowlX, topY - 35, cz - (bowlD / 2 - 16));
        m.add(overFlow);
      }

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
  root.userData.uid = o.pick || 'obj:' + o.uid; // toucher l'objet le sélectionne (la vasque : son meuble)
  const inner = new THREE.Group();
  inner.position.z = -o.d / 2 * S; // dos en z = 0 → recentré
  root.add(inner);
  if (o.kind === 'fixture') {
    inner.add(buildFixture(o, d));
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
function buildNetPoint(p) {
  const g = new THREE.Group();
  const m = new THREE.Group();
  m.scale.set(S, S, S);
  g.add(m);
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
    box(86, 86, 9, plateMat, x, 0, 0);
    box(70, 70, 2, plateMat, x, 0, 9);
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
      box(157, 86, 9, plateMat, 0, 0, 0);
      for (const x of [-36, 36]) {
        box(64, 64, 2, plateMat, x, 0, 9);
        cyl(22, 3, plateGrey, x, 0, 10);
        cyl(2.6, 2, plateDark, x - 9, 0, 12.5);
        cyl(2.6, 2, plateDark, x + 9, 0, 12.5);
      }
      break;
    case 'switch_':
      plate();
      box(44, 56, 4, plateMat, 0, 0, 11);
      box(30, 2, 1, plateGrey, 0, -20, 15);
      break;
    case 'switchDouble':
      plate();
      box(26, 56, 4, plateMat, -15, 0, 11);
      box(26, 56, 4, plateMat, 15, 0, 11);
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
  for (const p of d.netPoints || []) g.add(buildNetPoint(p));
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
    const ms = Array.isArray(o.material) ? o.material : o.material ? [o.material] : [];
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

function applyScene(d) {
  data = d;
  doors.length = 0;
  sync('room', JSON.stringify([d.room, d.walls, d.floor, d.wall, d.splashMat, d.splash]), () => buildRoom(d));
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
  sync('netPoints', JSON.stringify(d.netPoints || []), () => buildNetPoints(d));
  sync('ao', JSON.stringify([d.room, d.floorPoly || null, groundFootprints(d)]), () => buildAO(d));
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
  if (lastYaw === null || Math.abs(d.yaw - lastYaw) > 1e-6 || Math.abs(d.zoom - lastZoom) > 1e-6 || view !== lastView) {
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
  // lumière principale cadrée sur la pièce (positionnée en hauteur et orientée pour des ombres douces et réalistes)
  sun.position.set(target.x + 0.5, 6.0, target.z + 4.2);
  sun.target.position.copy(target);
  const half = Math.max(r.w, r.d) * S;
  Object.assign(sun.shadow.camera, { left: -half, right: half, top: half, bottom: -half, near: 0.5, far: 20 });
  sun.shadow.camera.updateProjectionMatrix();
  invalidate(true);
}

// ------------------------------------------------------------------ animation et murs masqués

function animate() {
  raf = requestAnimationFrame(animate);
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
      const uids = new Set([...progress.keys(), ...Object.keys(open)]);
      for (const uid of uids) {
        const target = uid in open ? open[uid] : 0;
        const p0 = progress.get(uid) ?? 0;
        let p = p0;
        p += Math.sign(target - p) * Math.min(Math.abs(target - p), dt / 0.6);
        if (p !== p0) moving = true;
        if (p <= 0 && target === 0) progress.delete(uid);
        else progress.set(uid, p);
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
        const p = progress.get(dr.uid) ?? 0;
        const e = p * p * (3 - 2 * p);
        dr.pivot.rotation.set(0, 0, 0);
        dr.pivot.position.set(0, 0, 0);
        if (dr.kind === 'door') dr.pivot.rotateY((dr.hinge === 'left' ? -1 : 1) * e * Math.PI / 2);
        else if (dr.kind === 'flapUp') dr.pivot.rotateX(-e * Math.PI * 100 / 180);
        else if (dr.kind === 'flapDown') dr.pivot.rotateX(e * Math.PI * 85 / 180);
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
      for (const key of ['room', 'netPoints']) {
        groups.get(key)?.obj.traverse((o) => {
          if (o.userData.wallOf) o.visible = walls.get(o.userData.wallOf) ?? true;
        });
      }
    }
    if (selBox) selBox.update();
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
    if (o) return { uid: o.userData.uid, point: h.point };
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

function onDown(ev) {
  if (ev.button !== 0) return;
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
  controls.enabled = true;
  press = null;
}

function onDouble(ev) {
  const h = pick(ev);
  if (h) handler('dbl', h.uid);
}

// ------------------------------------------------------------------ montage

let sun;
function init(el) {
  host = el;
  renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: !!window.kitchen3dPreserve });
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

  scene.add(new THREE.HemisphereLight(0xffffff, 0xd0c4b4, 1.15));
  scene.add(new THREE.AmbientLight(0xffffff, 0.45));
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

window.kitchen3d = {
  ready: true,
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
