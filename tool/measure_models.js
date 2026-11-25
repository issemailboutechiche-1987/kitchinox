const fs = require('fs');
const path = require('path');

function findFiles(dir, exts) {
  let res = [];
  fs.readdirSync(dir, { withFileTypes: true }).forEach(e => {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) res = res.concat(findFiles(p, exts));
    else if (exts.some(x => e.name.endsWith(x))) res.push(p);
  });
  return res;
}

function parseModel(filePath) {
  const isGlb = filePath.endsWith('.glb');
  let json, totalBytes = 0, textures = [];
  
  if (isGlb) {
    const stat = fs.statSync(filePath);
    totalBytes = stat.size;
    const buf = fs.readFileSync(filePath);
    const magic = buf.readUInt32LE(0);
    if (magic !== 0x46546C67) return null;
    const chunk0Len = buf.readUInt32LE(12);
    const jsonStr = buf.toString('utf8', 20, 20 + chunk0Len);
    json = JSON.parse(jsonStr);
  } else {
    const dir = path.dirname(filePath);
    const stat = fs.statSync(filePath);
    totalBytes = stat.size;
    json = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    
    if (json.buffers) {
      json.buffers.forEach(b => {
        if (b.uri && !b.uri.startsWith('data:')) {
          const bp = path.join(dir, b.uri);
          if (fs.existsSync(bp)) totalBytes += fs.statSync(bp).size;
        }
      });
    }
    const texDir = path.join(dir, 'textures');
    if (fs.existsSync(texDir)) {
      fs.readdirSync(texDir).forEach(tf => {
        const tp = path.join(texDir, tf);
        const tstat = fs.statSync(tp);
        totalBytes += tstat.size;
        textures.push({ name: tf, size: tstat.size });
      });
    }
  }

  let vertices = 0, triangles = 0;
  if (json.meshes) {
    json.meshes.forEach(m => {
      (m.primitives || []).forEach(p => {
        if (p.attributes && p.attributes.POSITION !== undefined) {
          const posAcc = json.accessors[p.attributes.POSITION];
          if (posAcc) vertices += posAcc.count;
          if (p.indices !== undefined) {
            const indAcc = json.accessors[p.indices];
            if (indAcc) triangles += Math.floor(indAcc.count / 3);
          } else if (posAcc) {
            triangles += Math.floor(posAcc.count / 3);
          }
        }
      });
    });
  }

  const rel = filePath.replace(/\\/g, '/');
  const source = rel.includes('/polyhaven/') ? 'Poly Haven' : 'Kenney';
  const name = path.basename(filePath, path.extname(filePath)).replace(/_1k$/, '');

  const texSize = textures.reduce((s, t) => s + t.size, 0);

  return {
    file: rel,
    name,
    source,
    vertices,
    triangles,
    textureCount: textures.length,
    textures,
    texSize,
    totalBytes,
    sizeFormatted: totalBytes >= 1048576 
      ? (totalBytes / 1048576).toFixed(2) + ' Mo' 
      : (totalBytes / 1024).toFixed(0) + ' Ko'
  };
}

const allFiles = findFiles('web/objects', ['.gltf', '.glb']);
const models = allFiles.map(parseModel).filter(Boolean);

// Sort by totalBytes descending
models.sort((a, b) => b.totalBytes - a.totalBytes);

let md = '# Mesure du poids des modèles 3D pour l’AR Quick Look\n\n';
md += 'Inventaire complet des ' + models.length + ' modèles 3D du catalogue (`web/objects/`), mesurés et triés du plus lourd au plus léger sur disque.\n\n';
md += 'Budget de l’exporteur USDZ : **1 500 000 sommets** au total pour la scène AR.\n';
md += 'Objectif d’allègement (LODs AR) : **≤ 20 000 triangles** et textures **≤ 512 px** par modèle individuel.\n\n';

md += '| Modèle | Source | Poids total | Sommets | Triangles | Textures | Statut AR |\n';
md += '| :--- | :--- | :---: | :---: | :---: | :---: | :---: |\n';

for (const m of models) {
  const needsLod = m.triangles > 20000 || m.totalBytes > 1500000;
  const status = needsLod ? '⚠️ À alléger (LOD)' : '✅ Prêt';
  const texDesc = m.textureCount > 0 ? (m.textureCount + ' (' + (m.texSize / 1024).toFixed(0) + ' Ko)') : '0';
  md += '| `' + m.name + '` | ' + m.source + ' | ' + m.sizeFormatted + ' | ' + m.vertices.toLocaleString('fr-FR') + ' | ' + m.triangles.toLocaleString('fr-FR') + ' | ' + texDesc + ' | ' + status + ' |\n';
}

md += '\n## Modèles prioritaires à alléger (Triangles > 20 000 ou Poids > 1,5 Mo)\n\n';
const heavy = models.filter(m => m.triangles > 20000 || m.totalBytes > 1500000);
heavy.forEach((m, idx) => {
  md += (idx + 1) + '. **`' + m.name + '`** (' + m.source + ') : ' + m.sizeFormatted + ', ' + m.triangles.toLocaleString('fr-FR') + ' triangles, ' + m.vertices.toLocaleString('fr-FR') + ' sommets, ' + m.textureCount + ' textures.\n';
});

fs.writeFileSync('docs/ar/modeles_poids.md', md, 'utf8');
console.log('Written docs/ar/modeles_poids.md with ' + models.length + ' models. Heavy models: ' + heavy.length);
