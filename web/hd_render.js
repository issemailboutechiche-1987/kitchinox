// Rendu HD de kitchinox : de préférence un vrai lancer de rayons (three-gpu-pathtracer, web/vendor/pathtracer) :
// reflets, lumière qui rebondit sur les murs, ombres physiques. Si l'appareil ne le permet pas
// (WebGL 1, mémoire, erreur), on revient à l'accumulation de lumière ci-dessous, sans bibliothèque.
//
// Accumulation de lumière :
// L'image est la moyenne de nombreux rendus : le soleil est une grande source douce, le ciel éclaire de partout
// (chaque rendu a sa propre direction et ses propres ombres), la caméra est décalée d'une fraction de pixel.
// Résultat : ombres douces, coins naturellement sombres (occlusion réelle) et contours sans escaliers.
import * as THREE from 'three';

/** Suite de Halton : des tirages bien répartis, toujours les mêmes (image identique d'une fois à l'autre). */
function halton(i, b) {
  let f = 1, r = 0;
  while (i > 0) {
    f /= b;
    r += f * (i % b);
    i = Math.floor(i / b);
  }
  return r;
}

const state = { k: 0, n: 0, url: null, error: null, running: false, engine: '' }; // engine : 'path' ou 'raster'
let stopAsked = false;

export function hdState() {
  return JSON.stringify(state);
}
export function hdRunning() {
  return state.running;
}
export function hdStop() {
  stopAsked = true;
}

/**
 * Libère vraiment un traceur : sa propre fonction dispose() plante dès sa première ligne dans cette version
 * (objet « _renderQuad » absent) et ne libérait rien. Cibles de rendu, textures de la scène (BVH, matériaux,
 * tableau de textures, environnement) : tout est rendu à la carte graphique. Sans cela, chaque image tracée
 * laissait des centaines de Mo pris, et l'iPad finissait par retirer la 3D à l'application (écran vide).
 */
export function disposePathTracer(pt) {
  if (!pt) return;
  const safe = (f) => {
    try {
      f();
    } catch (_) {}
  };
  for (const r of [pt._pathTracer, pt._lowResPathTracer]) {
    if (!r) continue;
    const mat = r.material;
    if (mat?.uniforms) {
      for (const u of Object.values(mat.uniforms)) {
        const v = u?.value;
        if (!v) continue;
        // tableau de textures du traceur : la texture appartient à une cible de rendu, qu'il faut libérer aussi
        const rt = v.kxTarget; // ajouté dans la bibliothèque (vendor/pathtracer)
        if (rt && typeof rt.dispose === 'function') {
          safe(() => rt.fsQuad?.dispose?.());
          safe(() => rt.dispose());
        }
        if (typeof v.dispose === 'function') safe(() => v.dispose());
        if (v.tex?.isTexture) safe(() => v.tex.dispose()); // lumières : la structure n'a pas de dispose()
      }
    }
    safe(() => r.dispose());
    safe(() => mat?.dispose());
  }
  for (const q of [pt._quad, pt._renderQuad]) {
    safe(() => q?.material?.dispose());
    safe(() => q?.dispose());
  }
  safe(() => pt._generator?.dispose?.());
  safe(() => pt._colorBackground?.dispose?.());
  safe(() => pt._internalBackground?.dispose?.());
}

/**
 * Démarre un rendu de w × h pixels en n passes. ctx : { renderer, scene, camera, sun, hemi, ambient, fill, studio, done }.
 * L'avancement et l'image (PNG) se lisent avec hdState().
 */
export function hdStart(ctx, w, h, n) {
  if (state.running) return;
  Object.assign(state, { k: 0, n, url: null, error: null, running: true, engine: 'path' });
  stopAsked = false;
  const log = window.__kxlog || (() => {});
  // lancer de rayons : chaque échantillon vaut bien plus qu'une passe d'accumulation
  const np = Math.max(12, Math.round(n / 3));
  state.n = np;
  pathStart(ctx, w, h, np).catch((e) => {
    // lancer de rayons impossible ici : l'accumulation de lumière prend le relais
    log('rendu', 'lancer de rayons indisponible, accumulation : ' + (e?.message || e));
    if (stopAsked) {
      Object.assign(state, { url: null, error: 'stop', running: false });
      ctx.done();
      return;
    }
    Object.assign(state, { k: 0, n, engine: 'raster' });
    rasterStart(ctx, w, h, n);
  });
}

/**
 * Copie propre de la scène pour le traceur : chaque face de chaque objet visible devient un objet simple, avec
 * un seul matériau, ses sommets déjà placés dans le monde et les mêmes attributs partout (position, normale, UV).
 * Le traceur décalait les matériaux sur les pièces fusionnées du moteur (meubles regroupés par matière, boîtes
 * à six faces) : un panneau blanc sortait rouge ou en bois, le sol en blanc. Avec cette copie, plus rien à deviner.
 */
function proxyScene(src) {
  const out = new THREE.Scene();
  out.environment = src.environment;
  out.environmentIntensity = src.environmentIntensity;
  out.background = null; // fond transparent : recomposé à sa vraie couleur, hors exposition (blitToCanvas)
  src.updateMatrixWorld(true);
  const geos = [];
  const m4 = new THREE.Matrix4();
  // faces à double côté : le traceur ignore une face vue de dos, et voyait à travers le dos et le dessus des
  // meubles (façades bleu nuit, couleur du fond). Copie du matériau, celui de la vue n'est pas touché.
  const twoSided = new Map();
  const sideOf = (m) => {
    if (m.side !== THREE.FrontSide) return m;
    let c = twoSided.get(m);
    if (!c) {
      c = m.clone();
      c.side = THREE.DoubleSide;
      twoSided.set(m, c);
    }
    return c;
  };
  const addMesh = (o, world) => {
    const g0 = o.geometry;
    if (!g0?.attributes?.position) return;
    const mats = Array.isArray(o.material) ? o.material : [o.material];
    const total = g0.index ? g0.index.count : g0.attributes.position.count;
    const groups = Array.isArray(o.material) && g0.groups.length ? g0.groups : [{ start: 0, count: total, materialIndex: 0 }];
    const flat = g0.index ? g0.toNonIndexed() : g0;
    const flip = world.determinant() < 0; // miroir : l'ordre des sommets s'inverse
    for (const gr of groups) {
      const m = mats[gr.materialIndex ?? 0];
      if (!m || m.visible === false) continue;
      const start = Math.max(0, gr.start), count = Math.min(gr.count, total - start);
      if (count < 3) continue;
      const g = new THREE.BufferGeometry();
      for (const name of ['position', 'normal', 'uv']) {
        const a = flat.attributes[name];
        const size = name === 'uv' ? 2 : 3;
        const arr = new Float32Array(count * size);
        if (a) for (let i = 0; i < count; i++) for (let c = 0; c < size; c++) arr[i * size + c] = a.getComponent(start + i, c);
        g.setAttribute(name, new THREE.BufferAttribute(arr, size));
      }
      if (!flat.attributes.normal) g.computeVertexNormals();
      g.applyMatrix4(world);
      if (flip) {
        for (const name of ['position', 'normal', 'uv']) {
          const a = g.attributes[name], sz = a.itemSize;
          for (let t = 0; t + 2 < count; t += 3) {
            for (let c = 0; c < sz; c++) {
              const v1 = a.array[(t + 1) * sz + c];
              a.array[(t + 1) * sz + c] = a.array[(t + 2) * sz + c];
              a.array[(t + 2) * sz + c] = v1;
            }
          }
        }
      }
      geos.push(g);
      out.add(new THREE.Mesh(g, sideOf(m)));
    }
    if (flat !== g0) flat.dispose();
  };
  src.traverseVisible((o) => {
    if (o.isLight) {
      if (!(o.isDirectionalLight || o.isPointLight || o.isSpotLight || o.isRectAreaLight)) return;
      const l = o.clone(false);
      o.getWorldPosition(l.position);
      o.getWorldQuaternion(l.quaternion);
      if (o.target) {
        l.target = new THREE.Object3D();
        o.target.getWorldPosition(l.target.position);
        out.add(l.target);
      }
      out.add(l);
      return;
    }
    if (!o.isMesh || o.isSkinnedMesh) return;
    if (o.isInstancedMesh) {
      for (let i = 0; i < o.count; i++) {
        o.getMatrixAt(i, m4);
        addMesh(o, o.matrixWorld.clone().multiply(m4));
      }
      return;
    }
    addMesh(o, o.matrixWorld);
  });
  out.updateMatrixWorld(true);
  out.userData.dispose = () => {
    geos.forEach((g) => g.dispose());
    twoSided.forEach((c) => c.dispose());
  };
  return out;
}

/**
 * Lancer de rayons : n échantillons par pixel, quelques-uns par image affichée (la page reste vivante).
 * Rejette la promesse (sans rien laisser modifié) si la bibliothèque ou l'appareil ne suit pas.
 */
async function pathStart(ctx, w, h, n) {
  const { renderer, scene, camera } = ctx;
  if (!renderer.capabilities.isWebGL2) throw new Error('WebGL 2 requis');
  const { WebGLPathTracer, GradientEquirectTexture, DenoiseMaterial } = await import('three-gpu-pathtracer');
  const max = renderer.capabilities.maxTextureSize;
  w = Math.min(w, max);
  h = Math.min(h, max);
  const keep = {
    size: renderer.getSize(new THREE.Vector2()),
    dpr: renderer.getPixelRatio(),
    aspect: camera.aspect,
    env: scene.environment,
    envI: scene.environmentIntensity,
    exposure: renderer.toneMappingExposure,
  };
  // ombres peintes au sol, ombre de présentation, traits du croquis : la vraie lumière les remplace
  const hidden = [];
  scene.traverse((o) => {
    const m = Array.isArray(o.material) ? o.material[0] : o.material;
    const painted = m && (m.isShadowMaterial || (m.isMeshBasicMaterial && m.transparent && m.map && !m.depthWrite));
    if ((o.isMesh && painted) || o.isLine) {
      hidden.push([o, o.visible]);
      o.visible = false;
    }
  });
  // environnement : la HDRI choisie (reflets réalistes) ; sinon un ciel doux tout autour
  // (le RoomEnvironment pré-filtré ne se lit pas en lancer de rayons)
  const env0 = scene.environment;
  const hdr = env0 && env0.isDataTexture && env0.mapping === THREE.EquirectangularReflectionMapping;
  const sky = new GradientEquirectTexture();
  sky.topColor.set(0xffffff);
  sky.bottomColor.set(0x9a9a9a);
  sky.update();
  scene.environment = hdr ? env0 : sky;
  scene.environmentIntensity = hdr ? env0.userData?.norm ?? 1.0 : 0.9;
  renderer.toneMappingExposure = 1.05;
  renderer.setPixelRatio(1);
  renderer.setSize(w, h, false);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();

  let pt = null;
  let proxy = null;
  const restore = () => {
    for (const [o, v] of hidden) o.visible = v;
    scene.environment = keep.env;
    scene.environmentIntensity = keep.envI;
    renderer.toneMappingExposure = keep.exposure;
    camera.aspect = keep.aspect;
    camera.updateProjectionMatrix();
    renderer.setRenderTarget(null);
    renderer.setPixelRatio(keep.dpr);
    renderer.setSize(keep.size.x, keep.size.y, false);
    disposePathTracer(pt);
    pt = null;
    proxy?.userData.dispose?.();
    sky.dispose();
  };
  try {
    pt = new WebGLPathTracer(renderer);
    pt.renderToCanvas = true;
    pt.rasterizeScene = false;
    pt.synchronizeRenderSize = true;
    pt.renderScale = 1;
    pt.minSamples = 0;
    pt.fadeDuration = 0;
    pt.renderDelay = 0;
    pt.dynamicLowRes = false;
    pt.bounces = 4;
    pt.filteredGlossyFactor = 1; // pas d'étincelles blanches sur le chrome
    // textures réduites : une image par façade, et la mémoire graphique de l'iPad déborde vite (façades d'une
    // mauvaise couleur, taches) ; les façades sont des aplats, 512 px suffisent largement
    pt.textureSize.set(512, 512);
    pt.tiles.set(2, 2);
    proxy = proxyScene(scene);
    pt.setScene(proxy, camera);
  } catch (e) {
    restore();
    throw e;
  }
  const log = window.__kxlog || (() => {});
  log('rendu', `lancer de rayons ${w}x${h}, ${n} échantillons`);
  const t0all = performance.now();
  let exposed = false;
  let tFirst = 0;
  await new Promise((resolve, reject) => {
    const step = () => {
      if (stopAsked) {
        restore();
        Object.assign(state, { url: null, error: 'stop', running: false });
        ctx.done();
        return resolve();
      }
      try {
        const t0 = performance.now();
        // tant que les shaders compilent, renderSample n'ajoute rien : la boucle attend sans bloquer
        while (pt.samples < n && performance.now() - t0 < 60) pt.renderSample();
        const spent = performance.now() - t0all;
        if (spent > 15 * 60 * 1000) throw new Error('lancer de rayons trop long');
        // l'image visible s'éclaircit au bon niveau dès les premiers échantillons (avant : blanc brûlé jusqu'à la fin)
        if (!exposed && pt.samples >= 3) {
          exposed = true;
          renderer.toneMappingExposure = autoExposure(renderer, pt.target);
        }
        // temps limité (image de la vue), compté depuis le premier échantillon : la préparation du traceur
        // (compilation, plusieurs secondes sur iPad) ne le mange plus. 64 échantillons au moins : en dessous,
        // l'image reste granuleuse (16 échantillons sur iPad avant cette correction).
        if (!tFirst && pt.samples > 0) tFirst = performance.now();
        const run = tFirst ? performance.now() - tFirst : 0;
        const timeUp = ctx.budget && run > ctx.budget && pt.samples >= Math.min(n, 64);
        state.k = ctx.budget && tFirst
          ? Math.min(n - 1, Math.max(Math.floor(pt.samples), Math.round((n * run) / ctx.budget)))
          : Math.min(n, Math.floor(pt.samples));
        if (pt.samples < n && !timeUp) return requestAnimationFrame(step);
        // l'image est lue dans la cible du traceur (et non sur le canevas, parfois déjà effacé : image noire)
        // exposition automatique (comme un appareil photo) : une pièce blanche fermée accumule beaucoup de lumière
        renderer.toneMappingExposure = autoExposure(renderer, pt.target);
        log('rendu', `exposition ${renderer.toneMappingExposure.toFixed(2)}, ${Math.floor(pt.samples)} échantillons`);
        // deux passes de débruitage (la seconde, plus fine, reprend le grain restant)
        const e = renderer.toneMappingExposure;
        const c1 = denoise(renderer, pt.target, DenoiseMaterial, e, 3, 0.15);
        const c2 = c1 && denoise(renderer, c1, DenoiseMaterial, e, 1.5, 0.08);
        const url = blitToCanvas(renderer, (c2 || c1 || pt.target).texture, true, ctx.bg);
        c1?.dispose();
        c2?.dispose();
        log('rendu', `lancer de rayons terminé en ${Math.round((performance.now() - t0all) / 1000)} s`);
        restore();
        Object.assign(state, { url, error: null, running: false });
        ctx.done();
        resolve();
      } catch (e) {
        // panne en cours de rendu : tout est remis en place, l'accumulation prend le relais
        restore();
        reject(e);
      }
    };
    requestAnimationFrame(step);
  });
}

/**
 * Débruitage final (filtre qui lisse le grain sans flouter les arêtes) : l'image du traceur est lissée
 * dans une cible de même taille. Le seuil suit l'exposition (le grain se juge sur l'image affichée).
 */
function denoise(renderer, target, DenoiseMaterial, exposure, sigma = 2.5, thr = 0.12) {
  if (!DenoiseMaterial) return null;
  try {
    const out = new THREE.WebGLRenderTarget(target.width, target.height, { type: THREE.HalfFloatType, depthBuffer: false });
    const mat = new DenoiseMaterial({ map: target.texture, sigma, kSigma: 1.5, threshold: thr / Math.max(0.05, exposure) });
    mat.toneMapped = false;
    const quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), mat);
    quad.frustumCulled = false;
    const flat = new THREE.Scene();
    flat.add(quad);
    renderer.setRenderTarget(out);
    renderer.render(flat, new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1));
    renderer.setRenderTarget(null);
    quad.geometry.dispose();
    mat.dispose();
    return out;
  } catch (_) {
    return null;
  }
}

/**
 * Retire le grain résiduel : un pixel nettement plus clair que tous ses voisins (étincelle isolée)
 * prend la moyenne de ses voisins. Les arêtes et les reflets étendus ne sont pas touchés.
 */
function despeckle(cv) {
  const ctx = cv.getContext('2d');
  const img = ctx.getImageData(0, 0, cv.width, cv.height);
  const d = img.data, w = cv.width, h = cv.height;
  const lum = new Float32Array(w * h);
  for (let i = 0; i < w * h; i++) lum[i] = 0.299 * d[i * 4] + 0.587 * d[i * 4 + 1] + 0.114 * d[i * 4 + 2];
  const out = new Uint8ClampedArray(d);
  let fixed = 0;
  for (let y = 1; y < h - 1; y++) {
    for (let x = 1; x < w - 1; x++) {
      const i = y * w + x;
      let mx = 0, r = 0, g = 0, b = 0;
      for (let dy = -1; dy <= 1; dy++) {
        for (let dx = -1; dx <= 1; dx++) {
          if (!dx && !dy) continue;
          const j = i + dy * w + dx;
          if (lum[j] > mx) mx = lum[j];
          r += d[j * 4];
          g += d[j * 4 + 1];
          b += d[j * 4 + 2];
        }
      }
      if (lum[i] > mx + 16) {
        out[i * 4] = r / 8;
        out[i * 4 + 1] = g / 8;
        out[i * 4 + 2] = b / 8;
        fixed++;
      }
    }
  }
  img.data.set(out);
  ctx.putImageData(img, 0, 0);
  return fixed;
}

/**
 * Exposition pour ramener la luminance moyenne (log) de l'image linéaire [target] à un gris moyen.
 * Les 2 % les plus clairs (fenêtres, reflets) ne comptent pas : ils ne doivent pas assombrir toute la cuisine.
 */
function autoExposure(renderer, target) {
  const w = target.width, h = target.height;
  let buf = new Float32Array(w * h * 4);
  try {
    if (target.texture.type === THREE.HalfFloatType) {
      // cible en demi-flottants (iPad) : lue telle quelle puis convertie
      const half = new Uint16Array(w * h * 4);
      renderer.readRenderTargetPixels(target, 0, 0, w, h, half);
      for (let i = 0; i < half.length; i++) buf[i] = THREE.DataUtils.fromHalfFloat(half[i]);
    } else {
      renderer.readRenderTargetPixels(target, 0, 0, w, h, buf);
    }
  } catch (_) {
    return 1;
  }
  const lums = [];
  for (let y = 0; y < h; y += 4) {
    for (let x = 0; x < w; x += 4) {
      const i = (y * w + x) * 4;
      const a = buf[i + 3];
      if (!(a > 0.5)) continue; // le fond ne compte pas
      const l = (0.2126 * buf[i] + 0.7152 * buf[i + 1] + 0.0722 * buf[i + 2]) / a;
      if (l > 1e-4 && Number.isFinite(l)) lums.push(l);
    }
  }
  if (lums.length < 50) return 1;
  lums.sort((a, b) => a - b);
  const keep = lums.slice(0, Math.floor(lums.length * 0.98));
  const logAvg = Math.exp(keep.reduce((a, l) => a + Math.log(l), 0) / keep.length);
  // 0,36 : une cuisine claire reste claire après la tonalité ACES, sans blancs brûlés
  return Math.max(0.02, Math.min(2.2, 0.36 / logAvg));
}

/** Dessine [texture] (linéaire, HDR) sur le canevas avec la tonalité de l'affichage, et renvoie le PNG. */
function blitToCanvas(renderer, texture, clean = false, bg = null) {
  // fond : couleur unie ou dégradé [haut, bas] en sRGB, posé tel quel (pas d'exposition) là où l'image est transparente
  const col = (hex) => new THREE.Color().setHex(hex).convertLinearToSRGB();
  const top = col(bg?.[0] ?? 0xeef1f3), bottom = col(bg?.[1] ?? bg?.[0] ?? 0xeef1f3);
  const mat = new THREE.ShaderMaterial({
    uniforms: { map: { value: texture }, bgTop: { value: top }, bgBottom: { value: bottom } },
    vertexShader: 'varying vec2 vUv; void main() { vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }',
    fragmentShader:
      'varying vec2 vUv; uniform sampler2D map; uniform vec3 bgTop, bgBottom; void main() {' +
      ' vec4 c = texture2D(map, vUv); float a = clamp(c.a, 0.0, 1.0); gl_FragColor = vec4(c.rgb / max(a, 0.001), 1.0);\n' +
      '#include <tonemapping_fragment>\n#include <colorspace_fragment>\n' +
      ' gl_FragColor.rgb = mix(mix(bgBottom, bgTop, vUv.y), gl_FragColor.rgb, a); }',
    depthTest: false,
    depthWrite: false,
  });
  const quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), mat);
  quad.frustumCulled = false;
  const flat = new THREE.Scene();
  flat.add(quad);
  renderer.setRenderTarget(null);
  renderer.render(flat, new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1));
  let url;
  if (clean) {
    // copie 2D (le canevas WebGL peut être effacé ensuite), grain retiré, puis PNG
    const cv = document.createElement('canvas');
    cv.width = renderer.domElement.width;
    cv.height = renderer.domElement.height;
    cv.getContext('2d').drawImage(renderer.domElement, 0, 0);
    const n = despeckle(cv);
    (window.__kxlog || (() => {}))('rendu', `grain retiré : ${n} pixels`);
    url = cv.toDataURL('image/png');
  } else {
    url = renderer.domElement.toDataURL('image/png');
  }
  quad.geometry.dispose();
  mat.dispose();
  return url;
}

/** Accumulation de lumière (sans bibliothèque) : le secours du lancer de rayons. */
function rasterStart(ctx, w, h, n) {
  const { renderer, scene, camera, sun, hemi, ambient, fill } = ctx;
  const keep = {
    size: renderer.getSize(new THREE.Vector2()),
    dpr: renderer.getPixelRatio(),
    aspect: camera.aspect,
    sunPos: sun.position.clone(),
    sunI: sun.intensity,
    hemiI: hemi.intensity,
    ambI: ambient.intensity,
    fillI: fill.intensity,
    env: scene.environmentIntensity,
    map: sun.shadow.mapSize.clone(),
    radius: sun.shadow.radius,
    exposure: renderer.toneMappingExposure,
    far: sun.shadow.camera.far,
  };
  const max = renderer.capabilities.maxTextureSize;
  w = Math.min(w, max);
  h = Math.min(h, max);
  const gl2 = renderer.getContext();
  const type = gl2.getExtension('EXT_color_buffer_float') ? THREE.FloatType : THREE.HalfFloatType;
  const opt = { type, format: THREE.RGBAFormat, minFilter: THREE.NearestFilter, magFilter: THREE.NearestFilter };
  const frame = new THREE.WebGLRenderTarget(w, h, { ...opt, type: THREE.HalfFloatType, depthBuffer: true });
  let a = new THREE.WebGLRenderTarget(w, h, { ...opt, depthBuffer: false });
  let b = new THREE.WebGLRenderTarget(w, h, { ...opt, depthBuffer: false });
  const quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2));
  quad.frustumCulled = false;
  const flat = new THREE.Scene();
  flat.add(quad);
  const ortho = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  const vs = 'varying vec2 vUv; void main() { vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }';
  const mix = new THREE.ShaderMaterial({
    uniforms: { prev: { value: null }, cur: { value: null }, t: { value: 1 } },
    vertexShader: vs,
    // une étincelle isolée (reflet) ne doit pas laisser de point blanc : on la plafonne
    fragmentShader: 'varying vec2 vUv; uniform sampler2D prev, cur; uniform float t; void main() { gl_FragColor = mix(texture2D(prev, vUv), min(texture2D(cur, vUv), vec4(6.0, 6.0, 6.0, 1.0)), t); }',
    depthTest: false, depthWrite: false, toneMapped: false,
  });
  const show = new THREE.ShaderMaterial({
    uniforms: { map: { value: null }, bg: { value: new THREE.Color() } },
    vertexShader: vs,
    // le fond garde sa couleur exacte (blanc pur en présentation) : il n'est pas touché par l'exposition
    fragmentShader: 'varying vec2 vUv; uniform sampler2D map; uniform vec3 bg; void main() { vec4 c = texture2D(map, vUv); float a = clamp(c.a, 0.0, 1.0); gl_FragColor = vec4(c.rgb / max(a, 0.001), 1.0);\n#include <tonemapping_fragment>\n#include <colorspace_fragment>\ngl_FragColor.rgb = mix(bg, gl_FragColor.rgb, a); }',
    depthTest: false, depthWrite: false,
  });

  const background = scene.background;
  if (background?.isColor) show.uniforms.bg.value.copy(background).convertLinearToSRGB();
  scene.background = null;
  const clearA = renderer.getClearAlpha();
  renderer.setClearAlpha(0);
  // ombre au sol de la présentation : plus dense, elle est étalée sur toutes les passes
  const shades = [];
  scene.traverse((o) => {
    if (o.material?.isShadowMaterial) {
      shades.push([o.material, o.material.opacity]);
      o.material.opacity = 0.55;
    }
  });
  renderer.setPixelRatio(1);
  renderer.setSize(w, h, false);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
  hemi.intensity = 0.55;
  ambient.intensity = 0.12;
  fill.intensity = keep.fillI * 0.35;
  scene.environmentIntensity = 0.4;
  renderer.toneMappingExposure = 1.12;
  sun.shadow.radius = 1.5;
  const res = Math.min(2048, renderer.capabilities.maxTextureSize);
  if (sun.shadow.mapSize.x !== res) {
    sun.shadow.mapSize.set(res, res);
    sun.shadow.map?.dispose();
    sun.shadow.map = null;
  }
  const target = sun.target.position.clone();
  const dist = keep.sunPos.distanceTo(target);
  const key = keep.sunPos.clone().sub(target).normalize();
  // repère autour de la direction du soleil
  const t1 = new THREE.Vector3(0, 1, 0).cross(key).normalize(), t2 = key.clone().cross(t1);
  const dir = new THREE.Vector3();

  const finish = (url, error) => {
    scene.background = background;
    renderer.setClearAlpha(clearA);
    for (const [m, o] of shades) m.opacity = o;
    sun.position.copy(keep.sunPos);
    sun.intensity = keep.sunI;
    hemi.intensity = keep.hemiI;
    ambient.intensity = keep.ambI;
    fill.intensity = keep.fillI;
    scene.environmentIntensity = keep.env;
    renderer.toneMappingExposure = keep.exposure;
    sun.shadow.radius = keep.radius;
    if (!sun.shadow.mapSize.equals(keep.map)) {
      sun.shadow.mapSize.copy(keep.map);
      sun.shadow.map?.dispose();
      sun.shadow.map = null;
    }
    camera.clearViewOffset();
    camera.aspect = keep.aspect;
    camera.updateProjectionMatrix();
    renderer.setRenderTarget(null);
    renderer.setPixelRatio(keep.dpr);
    renderer.setSize(keep.size.x, keep.size.y, false);
    for (const x of [frame, a, b, quad.geometry, mix, show]) x.dispose();
    Object.assign(state, { url, error, running: false });
    ctx.done();
  };

  const pass = (i) => {
    // une passe sur trois : le soleil (disque large) ; les autres : un point du ciel
    const u = halton(i + 1, 2), v = halton(i + 1, 3);
    if (i % 3 === 0) {
      const r = 0.16 * Math.sqrt(u), ph = 2 * Math.PI * v;
      dir.copy(key).addScaledVector(t1, r * Math.cos(ph)).addScaledVector(t2, r * Math.sin(ph)).normalize();
      sun.intensity = 2.9 * 1.5;
    } else {
      // répartition en cosinus autour de la verticale
      const r = Math.sqrt(u * 0.94), ph = 2 * Math.PI * v;
      dir.set(r * Math.cos(ph), Math.sqrt(Math.max(0.06, 1 - r * r)), r * Math.sin(ph)).normalize();
      sun.intensity = 1.35 * 1.5;
    }
    sun.position.copy(target).addScaledVector(dir, dist);
    sun.updateMatrixWorld();
    renderer.shadowMap.needsUpdate = true;
    camera.setViewOffset(w, h, halton(i + 1, 5) - 0.5, halton(i + 1, 7) - 0.5, w, h);
    renderer.setRenderTarget(frame);
    renderer.render(scene, camera);
    mix.uniforms.prev.value = a.texture;
    mix.uniforms.cur.value = frame.texture;
    mix.uniforms.t.value = 1 / (i + 1);
    quad.material = mix;
    renderer.setRenderTarget(b);
    renderer.render(flat, ortho);
    [a, b] = [b, a];
  };

  const step = () => {
    if (stopAsked) return finish(null, 'stop');
    try {
      const t0 = performance.now();
      // quelques passes par image affichée : la page reste vivante
      while (state.k < n && performance.now() - t0 < 60) {
        pass(state.k);
        state.k++;
      }
      if (state.k < n) return requestAnimationFrame(step);
      camera.clearViewOffset();
      quad.material = show;
      show.uniforms.map.value = a.texture;
      renderer.setRenderTarget(null);
      renderer.render(flat, ortho);
      finish(renderer.domElement.toDataURL('image/png'), null);
    } catch (e) {
      console.error('rendu HD :', e);
      finish(null, String(e));
    }
  };
  requestAnimationFrame(step);
}
