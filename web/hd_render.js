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
 * Démarre un rendu de w × h pixels en n passes. ctx : { renderer, scene, camera, sun, hemi, ambient, fill, studio, done }.
 * L'avancement et l'image (PNG) se lisent avec hdState().
 */
export function hdStart(ctx, w, h, n) {
  if (state.running) return;
  Object.assign(state, { k: 0, n, url: null, error: null, running: true, engine: 'path' });
  stopAsked = false;
  const log = window.__kxlog || (() => {});
  pathStart(ctx, w, h, n).catch((e) => {
    // lancer de rayons impossible ici : l'accumulation de lumière prend le relais
    log('rendu', 'lancer de rayons indisponible, accumulation : ' + (e?.message || e));
    if (stopAsked) {
      Object.assign(state, { url: null, error: 'stop', running: false });
      ctx.done();
      return;
    }
    Object.assign(state, { k: 0, engine: 'raster' });
    rasterStart(ctx, w, h, n);
  });
}

/**
 * Lancer de rayons : n échantillons par pixel, quelques-uns par image affichée (la page reste vivante).
 * Rejette la promesse (sans rien laisser modifié) si la bibliothèque ou l'appareil ne suit pas.
 */
async function pathStart(ctx, w, h, n) {
  const { renderer, scene, camera } = ctx;
  if (!renderer.capabilities.isWebGL2) throw new Error('WebGL 2 requis');
  const { WebGLPathTracer, GradientEquirectTexture } = await import('three-gpu-pathtracer');
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
  // ciel doux tout autour (le RoomEnvironment pré-filtré ne se lit pas en lancer de rayons)
  const sky = new GradientEquirectTexture();
  sky.topColor.set(0xffffff);
  sky.bottomColor.set(0x9a9a9a);
  sky.update();
  scene.environment = sky;
  scene.environmentIntensity = 0.9;
  renderer.toneMappingExposure = 1.05;
  renderer.setPixelRatio(1);
  renderer.setSize(w, h, false);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();

  let pt = null;
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
    try {
      pt?.dispose();
    } catch (_) {}
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
    pt.bounces = 6;
    pt.filteredGlossyFactor = 0.5; // pas d'étincelles blanches sur le chrome
    pt.tiles.set(2, 2);
    pt.setScene(scene, camera);
  } catch (e) {
    restore();
    throw e;
  }
  const log = window.__kxlog || (() => {});
  log('rendu', `lancer de rayons ${w}x${h}, ${n} échantillons`);
  const t0all = performance.now();
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
        if (performance.now() - t0all > 15 * 60 * 1000) throw new Error('lancer de rayons trop long');
        state.k = Math.min(n, Math.floor(pt.samples));
        if (pt.samples < n) return requestAnimationFrame(step);
        const url = renderer.domElement.toDataURL('image/png');
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
