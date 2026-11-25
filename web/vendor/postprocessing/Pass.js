// FullScreenQuad : le seul élément de three/examples/jsm/postprocessing/Pass.js dont le path tracer a besoin.
// Un triangle qui couvre tout l'écran, dessiné avec le matériau donné (écrit ici : aucun fichier de plus à télécharger).
import { BufferGeometry, Float32BufferAttribute, Mesh, OrthographicCamera } from 'three';

const camera = new OrthographicCamera(-1, 1, 1, -1, 0, 1);

class FullscreenTriangleGeometry extends BufferGeometry {
  constructor() {
    super();
    this.setAttribute('position', new Float32BufferAttribute([-1, 3, 0, -1, -1, 0, 3, -1, 0], 3));
    this.setAttribute('uv', new Float32BufferAttribute([0, 2, 0, 0, 2, 0], 2));
  }
}

const geometry = new FullscreenTriangleGeometry();

export class FullScreenQuad {
  constructor(material) {
    this._mesh = new Mesh(geometry, material);
  }

  dispose() {
    this._mesh.geometry.dispose();
  }

  render(renderer) {
    renderer.render(this._mesh, camera);
  }

  get material() {
    return this._mesh.material;
  }

  set material(value) {
    this._mesh.material = value;
  }
}

export class Pass {
  constructor() {
    this.enabled = true;
    this.needsSwap = true;
    this.clear = false;
    this.renderToScreen = false;
  }
  setSize() {}
  render() {
    console.error('Pass.render() doit être redéfini.');
  }
  dispose() {}
}
