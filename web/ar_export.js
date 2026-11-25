// Export AR : la scène three.js en paquet USDZ (AR Quick Look de l'iPad / iPhone), sans dépendance.
// Le paquet contient un calque USDA (maillages en mètres, Y vers le haut, transformations appliquées)
// et ses textures en PNG, rangés dans une archive zip non compressée alignée sur 64 octets.
//
// Contrat : buildUsdz(roots, opts) → Promise<{ bytes: Uint8Array, stats }>
//   roots : objets three.js à exporter (matrices du monde à jour)
//   opts.ghost : Set d'objets (ou prédicat) rendus en « fantôme » translucide (murs)
//   opts.maxTexture : côté maximal des textures (1024 par défaut)
//   opts.maxVertices : budget de sommets ; au-delà, les maillages les plus lourds sont omis

import * as THREE from 'three';

const fmt = (v) => {
  const s = v.toFixed(4);
  return s === '-0.0000' ? '0' : s.replace(/\.?0+$/, '') || '0';
};

// ------------------------------------------------------------------ zip « stocké », aligné 64 octets

const CRC = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(b) {
  let c = 0xffffffff;
  for (let i = 0; i < b.length; i++) c = CRC[(c ^ b[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

/** Archive zip sans compression ; les données de chaque fichier commencent sur un multiple de 64. */
export function zipStore(files) {
  const enc = new TextEncoder();
  const parts = [];
  const central = [];
  let offset = 0;
  for (const f of files) {
    const name = enc.encode(f.name);
    const data = f.data;
    const crc = crc32(data);
    const base = offset + 30 + name.length + 4;
    const pad = (64 - (base % 64)) % 64;
    const extra = 4 + pad;
    const h = new DataView(new ArrayBuffer(30 + name.length + extra));
    h.setUint32(0, 0x04034b50, true);
    h.setUint16(4, 20, true); // version
    h.setUint16(6, 0, true); // drapeaux
    h.setUint16(8, 0, true); // stocké
    h.setUint16(10, 0, true);
    h.setUint16(12, 0x21, true);
    h.setUint32(14, crc, true);
    h.setUint32(18, data.length, true);
    h.setUint32(22, data.length, true);
    h.setUint16(26, name.length, true);
    h.setUint16(28, extra, true);
    new Uint8Array(h.buffer).set(name, 30);
    h.setUint16(30 + name.length, 0x1986, true); // champ de remplissage
    h.setUint16(32 + name.length, pad, true);
    parts.push(new Uint8Array(h.buffer), data);
    central.push({ name, crc, size: data.length, offset });
    offset += h.byteLength + data.length;
  }
  const cdStart = offset;
  for (const c of central) {
    const h = new DataView(new ArrayBuffer(46 + c.name.length));
    h.setUint32(0, 0x02014b50, true);
    h.setUint16(4, 20, true);
    h.setUint16(6, 20, true);
    h.setUint16(8, 0, true);
    h.setUint16(10, 0, true);
    h.setUint16(12, 0, true);
    h.setUint16(14, 0x21, true);
    h.setUint32(16, c.crc, true);
    h.setUint32(20, c.size, true);
    h.setUint32(24, c.size, true);
    h.setUint16(28, c.name.length, true);
    h.setUint32(42, c.offset, true);
    new Uint8Array(h.buffer).set(c.name, 46);
    parts.push(new Uint8Array(h.buffer));
    offset += h.byteLength;
  }
  const end = new DataView(new ArrayBuffer(22));
  end.setUint32(0, 0x06054b50, true);
  end.setUint16(8, central.length, true);
  end.setUint16(10, central.length, true);
  end.setUint32(12, offset - cdStart, true);
  end.setUint32(16, cdStart, true);
  parts.push(new Uint8Array(end.buffer));
  const out = new Uint8Array(offset + 22);
  let p = 0;
  for (const x of parts) {
    out.set(x, p);
    p += x.length;
  }
  return out;
}

// ------------------------------------------------------------------ textures

async function texturePng(tex, max) {
  const img = tex.image;
  if (!img) return null;
  const w0 = img.width || img.videoWidth, h0 = img.height || img.videoHeight;
  if (!w0 || !h0) return null;
  const k = Math.min(1, max / Math.max(w0, h0));
  const w = Math.max(1, Math.round(w0 * k)), h = Math.max(1, Math.round(h0 * k));
  const cv = document.createElement('canvas');
  cv.width = w;
  cv.height = h;
  const ctx = cv.getContext('2d');
  let flipRows = false;
  if (img.data) {
    // texture de données (rangée 0 = bas de l'image en GL) : retournée pour le PNG
    const src = document.createElement('canvas');
    src.width = w0;
    src.height = h0;
    const id = new ImageData(w0, h0);
    const d = img.data;
    if (d.length === w0 * h0 * 4) id.data.set(d);
    else if (d.length === w0 * h0 * 3) for (let i = 0, j = 0; i < d.length; i += 3, j += 4) id.data.set([d[i], d[i + 1], d[i + 2], 255], j);
    else return null;
    src.getContext('2d').putImageData(id, 0, 0);
    ctx.translate(0, h);
    ctx.scale(1, -1);
    ctx.drawImage(src, 0, 0, w, h);
    flipRows = true;
  } else {
    try {
      ctx.drawImage(img, 0, 0, w, h);
    } catch (_) {
      return null;
    }
  }
  const blob = await new Promise((r) => cv.toBlob(r, 'image/png'));
  if (!blob) return null;
  return { bytes: new Uint8Array(await blob.arrayBuffer()), flipRows };
}

// ------------------------------------------------------------------ matériaux

function surfaceOf(m) {
  const c = m.color ? m.color : new THREE.Color(1, 1, 1); // couleurs linéaires, comme UsdPreviewSurface
  const glass = (m.transmission ?? 0) > 0.3;
  const opacity = glass ? 0.3 : m.transparent ? m.opacity ?? 1 : 1;
  return {
    color: [c.r, c.g, c.b],
    roughness: m.roughness ?? (m.isMeshBasicMaterial ? 1 : 0.6),
    metallic: m.metalness ?? 0,
    opacity: Math.max(0.05, Math.min(1, opacity)),
    map: m.map && m.map.image ? m.map : null,
    doubleSided: m.side === THREE.DoubleSide,
  };
}

// ------------------------------------------------------------------ export

/** Maillages à exporter : visibles (sauf murs masqués par la caméra), sans traits ni ombres peintes. */
function collect(roots) {
  const out = [];
  const walk = (o, force) => {
    const wallish = !!(o.userData.wall || o.userData.wallOf);
    if (!o.visible && !wallish && !force && !('sketchHidden' in o.userData)) return;
    if ('sketchHidden' in o.userData && !o.userData.sketchHidden) return;
    if (o.userData.sketchEdge || o.isLine || o.isPoints || o.isSprite) return;
    if (o.isMesh) {
      const mat = o.userData.sketchOrig ?? o.material;
      const mats = Array.isArray(mat) ? mat : [mat];
      const first = mats[0];
      const paintedShadow = first && first.isMeshBasicMaterial && first.transparent && first.map && !first.depthWrite;
      if (!paintedShadow) out.push({ mesh: o, mats });
    }
    for (const c of o.children) walk(c, force || wallish);
  };
  for (const r of roots) walk(r, false);
  return out;
}

export async function buildUsdz(roots, opts = {}) {
  const maxTex = opts.maxTexture ?? 1024;
  const maxVerts = opts.maxVertices ?? 1500000;
  const ghost = opts.ghost ?? (() => false);
  for (const r of roots) r.updateMatrixWorld(true);
  let items = collect(roots);

  // budget : les maillages les plus lourds sautent d'abord
  const count = (x) => (x.mesh.geometry?.attributes?.position?.count ?? 0) * (x.mesh.isInstancedMesh ? x.mesh.count : 1);
  let total = items.reduce((a, x) => a + count(x), 0);
  let dropped = 0;
  if (total > maxVerts) {
    const sorted = [...items].sort((a, b) => count(b) - count(a));
    const skip = new Set();
    for (const x of sorted) {
      if (total <= maxVerts) break;
      skip.add(x);
      total -= count(x);
      dropped++;
    }
    items = items.filter((x) => !skip.has(x));
  }

  const files = [];
  const matKeys = new Map(); // clé → matériau écrit
  const matDefs = [];
  const texNames = new Map(); // texture → { file, flipRows }
  const meshDefs = [];
  let vertices = 0;

  async function materialName(m, isGhost) {
    const key = m.uuid + (isGhost ? ':g' : '');
    if (matKeys.has(key)) return matKeys.get(key);
    const name = 'M' + matKeys.size;
    const entry = { name, tex: null, map: null, doubleSided: false };
    matKeys.set(key, entry);
    const s = surfaceOf(m);
    if (isGhost) {
      s.color = [0.86, 0.88, 0.9];
      s.opacity = 0.28;
      s.map = null;
    }
    let tex = null;
    if (s.map) {
      if (!texNames.has(s.map)) {
        const png = await texturePng(s.map, maxTex);
        if (png) {
          const file = 'textures/T' + texNames.size + '.png';
          files.push({ name: file, data: png.bytes });
          texNames.set(s.map, { file, flipRows: png.flipRows });
        } else texNames.set(s.map, null);
      }
      tex = texNames.get(s.map);
    }
    const p = `/Root/Materials/${name}`;
    const c = s.color.map(fmt).join(', ');
    let body = `    def Material "${name}"\n    {\n        token outputs:surface.connect = <${p}/Surface.outputs:surface>\n`;
    body += `        def Shader "Surface"\n        {\n            uniform token info:id = "UsdPreviewSurface"\n`;
    if (tex) body += `            color3f inputs:diffuseColor.connect = <${p}/Tex.outputs:rgb>\n`;
    else body += `            color3f inputs:diffuseColor = (${c})\n`;
    body += `            float inputs:roughness = ${fmt(s.roughness)}\n            float inputs:metallic = ${fmt(s.metallic)}\n`;
    body += `            float inputs:opacity = ${fmt(s.opacity)}\n            int inputs:useSpecularWorkflow = 0\n            token outputs:surface\n        }\n`;
    if (tex) {
      body += `        def Shader "St"\n        {\n            uniform token info:id = "UsdPrimvarReader_float2"\n            token inputs:varname = "st"\n            float2 outputs:result\n        }\n`;
      body += `        def Shader "Tex"\n        {\n            uniform token info:id = "UsdUVTexture"\n            asset inputs:file = @${tex.file}@\n`;
      body += `            float2 inputs:st.connect = <${p}/St.outputs:result>\n            token inputs:wrapS = "repeat"\n            token inputs:wrapT = "repeat"\n`;
      body += `            float4 inputs:scale = (${c}, 1)\n            token inputs:sourceColorSpace = "sRGB"\n            float3 outputs:rgb\n        }\n`;
    }
    body += '    }\n';
    matDefs.push(body);
    Object.assign(entry, { tex, map: tex ? s.map : null, doubleSided: s.doubleSided });
    return entry;
  }

  const v = new THREE.Vector3();
  const nm = new THREE.Matrix3();
  const world = new THREE.Matrix4();
  const inst = new THREE.Matrix4();
  for (const { mesh, mats } of items) {
    const g = mesh.geometry;
    const pos = g?.attributes?.position;
    if (!pos) continue;
    const nor = g.attributes.normal;
    const uv = g.attributes.uv;
    const index = g.index;
    const groups = g.groups.length ? g.groups : [{ start: 0, count: index ? index.count : pos.count, materialIndex: 0 }];
    const copies = mesh.isInstancedMesh ? mesh.count : 1;
    const isGhost = ghost(mesh);
    for (let ci = 0; ci < copies; ci++) {
      world.copy(mesh.matrixWorld);
      if (mesh.isInstancedMesh) {
        mesh.getMatrixAt(ci, inst);
        world.multiply(inst);
      }
      nm.getNormalMatrix(world);
      for (const gr of groups) {
        const m = mats[gr.materialIndex ?? 0] ?? mats[0];
        if (!m || m.visible === false) continue;
        const mat = await materialName(m, isGhost);
        // sommets utilisés par ce groupe, réindexés
        const remap = new Map();
        const ids = [];
        const end = Math.min(gr.start + gr.count, index ? index.count : pos.count);
        for (let i = gr.start; i < end; i++) {
          const src = index ? index.getX(i) : i;
          let d = remap.get(src);
          if (d === undefined) {
            d = remap.size;
            remap.set(src, d);
          }
          ids.push(d);
        }
        if (ids.length < 3) continue;
        const P = [], N = [], T = [];
        const texM = mat.tex && mat.map ? (mat.map.updateMatrix(), mat.map.matrix) : null;
        const invertV = mat.tex ? !mat.tex.flipRows && mat.map.flipY === false : false;
        const t2 = new THREE.Vector2();
        for (const src of remap.keys()) {
          v.fromBufferAttribute(pos, src).applyMatrix4(world);
          P.push(`(${fmt(v.x)}, ${fmt(v.y)}, ${fmt(v.z)})`);
          if (nor) {
            v.fromBufferAttribute(nor, src).applyMatrix3(nm).normalize();
            N.push(`(${fmt(v.x)}, ${fmt(v.y)}, ${fmt(v.z)})`);
          }
          if (texM && uv) {
            t2.fromBufferAttribute(uv, src).applyMatrix3(texM);
            T.push(`(${fmt(t2.x)}, ${fmt(invertV ? 1 - t2.y : t2.y)})`);
          }
        }
        vertices += remap.size;
        const tris = Math.floor(ids.length / 3);
        const name = 'G' + meshDefs.length;
        let s = `    def Mesh "${name}" (\n        prepend apiSchemas = ["MaterialBindingAPI"]\n    )\n    {\n`;
        s += `        int[] faceVertexCounts = [${new Array(tris).fill(3).join(', ')}]\n`;
        s += `        int[] faceVertexIndices = [${ids.slice(0, tris * 3).join(', ')}]\n`;
        s += `        rel material:binding = </Root/Materials/${mat.name}>\n`;
        if (N.length) s += `        normal3f[] normals = [${N.join(', ')}] (\n            interpolation = "vertex"\n        )\n`;
        s += `        point3f[] points = [${P.join(', ')}]\n`;
        if (T.length) s += `        texCoord2f[] primvars:st = [${T.join(', ')}] (\n            interpolation = "vertex"\n        )\n`;
        if (mat.doubleSided || isGhost) s += '        uniform bool doubleSided = 1\n';
        s += '        uniform token subdivisionScheme = "none"\n    }\n';
        meshDefs.push(s);
      }
    }
  }

  const usda =
    '#usda 1.0\n(\n    customLayerData = {\n        string creator = "kitchinox"\n    }\n    defaultPrim = "Root"\n    metersPerUnit = 1\n    upAxis = "Y"\n)\n\n' +
    'def Xform "Root"\n{\n' +
    '    def Scope "Materials"\n    {\n' + matDefs.join('') + '    }\n\n' +
    meshDefs.join('\n') +
    '}\n';
  const bytes = zipStore([{ name: 'model.usda', data: new TextEncoder().encode(usda) }, ...files]);
  return { bytes, stats: { meshes: meshDefs.length, vertices, materials: matDefs.length, textures: files.length, dropped, size: bytes.length } };
}

/** L'appareil sait-il ouvrir un USDZ en réalité augmentée (AR Quick Look) ? */
export function arQuickLookSupported() {
  try {
    return document.createElement('a').relList.supports('ar');
  } catch (_) {
    return false;
  }
}

/**
 * Ouvre le paquet dans AR Quick Look (iPad / iPhone), sinon le télécharge.
 * À appeler pendant un geste de l'utilisateur (toucher), sinon Safari refuse.
 * [fixedScale] : l'échelle 1:1 ne peut pas être modifiée au pincement.
 */
export function openUsdz(bytes, fileName = 'kitchinox.usdz', fixedScale = true) {
  const url = URL.createObjectURL(new Blob([bytes], { type: 'model/vnd.usdz+zip' }));
  const a = document.createElement('a');
  const ar = arQuickLookSupported();
  if (ar) {
    a.rel = 'ar';
    a.appendChild(document.createElement('img')); // exigé par Quick Look
    a.href = url + (fixedScale ? '#allowsContentScaling=0' : '');
  } else {
    a.href = url;
    a.download = fileName;
  }
  document.body.appendChild(a);
  a.click();
  setTimeout(() => {
    a.remove();
    URL.revokeObjectURL(url);
  }, 60000);
  return ar;
}
