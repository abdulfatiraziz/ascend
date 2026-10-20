import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

const canvas = document.querySelector('canvas');
const status = document.getElementById('status');
const bridge = (type, message = '') => window.webkit?.messageHandlers?.avatar?.postMessage({ type, message });
let state = { progress: 0, evolution: 0, finish: 'Obsidian', preview: false, compact: false, reduceMotion: false };
try {
  const renderer = new THREE.WebGLRenderer({ canvas, alpha: true, antialias: true, powerPreference: 'low-power' });
  renderer.setPixelRatio(Math.min(devicePixelRatio, 1.7));
  renderer.setClearColor(0, 0);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.15;
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(32, 1, 0.01, 40);
  const env = new THREE.Scene(); env.background = new THREE.Color('#17151e');
  function panel(color, intensity, x, y, z, w, h) {
    const mesh = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ color: new THREE.Color(color).multiplyScalar(intensity), side: THREE.DoubleSide }));
    mesh.position.set(x,y,z); mesh.lookAt(0,0,0); env.add(mesh);
  }
  panel('#ffffff',4,-3,2,3,1.4,6);
  panel('#d6d3ff',2,3,2,1,1,5);
  panel('#a18aff',2.6,1,1,-3,3,5);
  panel('#ffffff',2,0,4,0,4,2);
  const generator = new THREE.PMREMGenerator(renderer);
  const envMap = generator.fromScene(env, 0.035); scene.environment = envMap.texture;
  generator.dispose(); env.traverse(o => { o.geometry?.dispose(); o.material?.dispose(); });
  scene.add(new THREE.HemisphereLight('#ddd9ff','#120d19',1.2));
  const key = new THREE.DirectionalLight('#ffffff',2.7); key.position.set(-3,4,4); scene.add(key);
  const rim = new THREE.DirectionalLight('#a18aff',3); rim.position.set(3,1,-3); scene.add(rim);
  const fill = new THREE.DirectionalLight('#bac8ff',0.5); fill.position.set(2,1,3); scene.add(fill);
  const group = new THREE.Group(); group.rotation.y = -0.18; scene.add(group);
  const platform = new THREE.Mesh(new THREE.CylinderGeometry(.46,.49,.025,96),new THREE.MeshStandardMaterial({color:'#17141e',metalness:.65,roughness:.35}));
  platform.position.y = -.867; scene.add(platform);
  const ringMat = new THREE.MeshBasicMaterial({color:'#a18aff'});
  const baseRing = new THREE.Mesh(new THREE.TorusGeometry(.51,.0025,8,128),ringMat); baseRing.rotation.x=Math.PI/2; baseRing.position.y=-.85;scene.add(baseRing);
  const progressRing = new THREE.Mesh(new THREE.TorusGeometry(.545,.005,8,128,.001),ringMat);
  progressRing.rotation.x=Math.PI/2;progressRing.position.y=-.848;scene.add(progressRing);
  const halo = new THREE.Mesh(new THREE.TorusGeometry(.50,.0015,6,128),new THREE.MeshBasicMaterial({color:'#a18aff',transparent:true,opacity:.2}));
  halo.position.set(0,.2,-.18);halo.scale.y=1.3;scene.add(halo);
  let model = null, yaw = -.18, drag = null;
  const draw = () => { if (!document.hidden) renderer.render(scene,camera); };
  function resize() {
    const w=canvas.clientWidth,h=canvas.clientHeight;if(!w||!h)return;
    renderer.setSize(w,h,false);camera.aspect=w/h;
    const tangent=Math.tan(THREE.MathUtils.degToRad(camera.fov/2));
    const distance=state.compact?Math.max(.55/tangent,.36/(tangent*camera.aspect)):Math.max(1.04/tangent,.65/(tangent*camera.aspect));
    camera.position.set(0,state.compact?.43:.02,distance);
    camera.lookAt(0,state.compact?.43:-.02,0);camera.updateProjectionMatrix();draw();
  }
  function update(next) {
    state={...state,...next};
    document.body.classList.toggle('compact',state.compact);
    platform.visible=baseRing.visible=progressRing.visible=halo.visible=!state.compact;
    state.progress=Math.max(0,Math.min(1,Number(state.progress)||0));
    const evolved=state.preview?1:Math.max(0,Math.min(1,Number(state.evolution)||0));
    const finish=state.preview?'Ascendant':state.finish;
    if(model) model.traverse(o=>{
      if(!o.isMesh)return;
      const mats=Array.isArray(o.material)?o.material:[o.material];
      mats.forEach(m=>{
        const name=m.name.toLowerCase();
        if(name.includes('piping')){m.color.set('#a18aff');m.emissive?.set('#a18aff');m.emissiveIntensity=.15+evolved*2.8+state.progress*.45;return;}
        if(name.includes('flexible'))return;
        m.color.set(finish==='Ascendant'?'#b7b2c5':finish==='Titanium'?'#8c8e9d':'#383540');
        m.metalness=finish==='Ascendant'?.7:.82;
        m.roughness=name.includes('shell')?.19:.3;
      });
    });
    rim.intensity=2+state.progress*1.5+evolved*1.2;
    halo.material.opacity=.12+state.progress*.15+evolved*.25;
    progressRing.geometry.dispose();progressRing.geometry=new THREE.TorusGeometry(.545,.005,8,128,Math.max(.001,Math.PI*2*state.progress));
    resize();
  }
  window.ascend={update,rotate(delta){yaw+=delta;group.rotation.y=yaw;draw();}};
  const binary=atob(window.ASCEND_MODEL),bytes=new Uint8Array(binary.length);
  for(let i=0;i<binary.length;i++)bytes[i]=binary.charCodeAt(i);
  new GLTFLoader().parse(bytes.buffer,'',gltf=>{
    model=gltf.scene;
    const box=new THREE.Box3().setFromObject(model),center=box.getCenter(new THREE.Vector3());
    model.position.sub(center);group.add(model);update(state);
    status.hidden=true;bridge('ready');
  },error=>{status.textContent='Avatar unavailable';bridge('error',String(error));});
  canvas.addEventListener('pointerdown',e=>{drag=e.clientX;canvas.setPointerCapture(e.pointerId);});
  canvas.addEventListener('pointermove',e=>{if(drag===null)return;yaw+=(e.clientX-drag)*.012;drag=e.clientX;group.rotation.y=yaw;draw();});
  canvas.addEventListener('pointerup',()=>drag=null);canvas.addEventListener('pointercancel',()=>drag=null);
  document.querySelector('[data-left]').onclick=()=>window.ascend.rotate(-.3);
  document.querySelector('[data-right]').onclick=()=>window.ascend.rotate(.3);
  document.addEventListener('visibilitychange',()=>{if(!document.hidden)draw();});
  new ResizeObserver(resize).observe(document.documentElement);
  window.addEventListener('pagehide',()=>{renderer.dispose();envMap.dispose();});
  resize();
} catch(error) { status.textContent='Avatar unavailable';bridge('error',String(error)); }
