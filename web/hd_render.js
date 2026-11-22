// Rendu HD de kitchinox : accumulation de lumière, sans bibliothèque supplémentaire.
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

const state = { k: 0, n: 0, url: null, error: null, running: false };
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
  Object.assign(state, { k: 0, n, url: null, error: null, running: true });
  stopAsked = false;
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
