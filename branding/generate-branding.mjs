// SPDX-License-Identifier: MIT
// Original DS Bot Go artwork, 2026. No upstream path or illustration is reused.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const out = path.dirname(fileURLToPath(import.meta.url));
const write = (rel, data) => { const p = path.join(out, rel); fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, data); };
const k = .5522847498;
function roundRect(x,y,w,h,r) {
  return {start:[x+r,y], segments:[
    [x+r,y,x+w-r,y,x+w-r,y], [x+w-r+k*r,y,x+w,y+r-k*r,x+w,y+r],
    [x+w,y+r,x+w,y+h-r,x+w,y+h-r], [x+w,y+h-r+k*r,x+w-r+k*r,y+h,x+w-r,y+h],
    [x+w-r,y+h,x+r,y+h,x+r,y+h], [x+r-k*r,y+h,x,y+h-r+k*r,x,y+h-r],
    [x,y+h-r,x,y+r,x,y+r], [x,y+r-k*r,x+r-k*r,y,x+r,y]
  ]};
}
function polygon(points) { return {start:points[0],segments:points.slice(1).map((p,i)=>[...points[i],...p,...p])}; }
function reverse(s) {
  const starts=[s.start,...s.segments.map(p=>p.slice(4,6))];
  return {start:starts.at(-1),segments:s.segments.map((p,i)=>[...p.slice(2,4),...p.slice(0,2),...starts[i]]).reverse()};
}
function d(shapes) { return shapes.map(s=>`M${s.start.join(' ')} ${s.segments.map(a=>'C'+a.map(n=>+n.toFixed(4)).join(' ')).join(' ')} Z`).join(' '); }
const head=roundRect(29,35,53,42,19);
const parts={
  body:[roundRect(22,48,12,15,6),roundRect(78,47,9,15,4.5),roundRect(52,27,5,12,2.5),roundRect(50,20,9,9,4.5),roundRect(23,67,12,3.5,1.75),roundRect(26,73,10,3.5,1.75),head],
  fin:[{start:[30,60],segments:[[35,67,43,70,54,70],[68,70,78,63,82,53],[83,67,76,77,64,77],[53,77,44,79,37,73],[33,70,31,65,30,60]]}],
  belly:[{start:[35,44],segments:[[39,37,47,35,56,35],[62,35,68,36,71,39],[60,37,46,40,40,48],[37,51,34,49,35,44]]}],
  bubble:[roundRect(44,47,6.5,16,3.25),roundRect(63,44,6.5,16,3.25)]
};
// Fit every painted part inside the central 66dp circle of Android's 108dp grid.
let maxRadius=0;
for(const shapes of Object.values(parts))for(const s of shapes){let p=s.start;for(const a of s.segments){for(let i=0;i<=48;i++){const t=i/48,u=1-t,x=u*u*u*p[0]+3*u*u*t*a[0]+3*u*t*t*a[2]+t*t*t*a[4],y=u*u*u*p[1]+3*u*u*t*a[1]+3*u*t*t*a[3]+t*t*t*a[5];maxRadius=Math.max(maxRadius,Math.hypot(x-54,y-54));}p=a.slice(4,6);}}
const safeScale=Math.min(1,32.5/maxRadius);
for(const shapes of Object.values(parts))for(const s of shapes){s.start=s.start.map(n=>54+(n-54)*safeScale);s.segments=s.segments.map(a=>a.map(n=>54+(n-54)*safeScale));}
const tile=roundRect(18,18,72,72,20);
const palettes={light:{body:['#5776FF','#4D6BFE'],fin:['#4057D3','#4057D3'],belly:['#8C9EFF','#8C9EFF'],bubble:['#FFFFFF','#FFFFFF']},dark:{body:['#8CA2FF','#6886FF'],fin:['#506DE2','#506DE2'],belly:['#B1C0FF','#B1C0FF'],bubble:['#FFFFFF','#FFFFFF']}};
function gradients(p) {return Object.entries({tail:p.body,fin:p.fin,belly:p.belly,bubble:p.bubble}).map(([id,c])=>`<linearGradient id="${id}" gradientUnits="userSpaceOnUse" x1="30" y1="35" x2="80" y2="77"><stop offset="0" stop-color="${c[0]}"/><stop offset="1" stop-color="${c[1]}"/></linearGradient>`).join('');}
const ids={body:'body',fin:'fin-layer',belly:'belly-layer',bubble:'bubble-layer'};
function paths() {return Object.entries(parts).map(([name,shapes])=>`<path id="${ids[name]}" fill="url(#${name==='body'?'tail':name})" d="${d(shapes)}"/>`).join('\n');}
function svg(mode,withTile=false) {return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="${withTile?'0 0 108 108':'20 18 70 62'}"><!-- Original DS Bot Go mark. Copyright 2026 DS Bot Go contributors. MIT. --><defs>${gradients(palettes[mode])}</defs>${withTile?`<path d="${d([roundRect(6,6,96,96,25)])}" fill="${mode==='light'?'#F7F9FD':'#18243D'}"/>`:''}${paths()}</svg>\n`;}
for(const mode of ['light','dark']) write(`app/assets/brand/glyph-${mode}.svg`,svg(mode));
write('icon.svg',svg('light',true)); write('icon-dark.svg',svg('dark',true));
write('app/assets/brand/tile.svg',`<svg xmlns="http://www.w3.org/2000/svg" viewBox="18 18 72 72"><defs><linearGradient id="tile-bg" gradientUnits="userSpaceOnUse" x1="18" y1="18" x2="90" y2="90"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#EEF2F9"/></linearGradient>${gradients(palettes.light)}</defs><path id="tile" d="${d([tile])}" fill="url(#tile-bg)"/>${paths()}</svg>\n`);
const res='app/android/app/src/main/res';
const mono=d([...parts.body,...parts.bubble.map(reverse)]);
write(`${res}/drawable/ic_launcher_monochrome.xml`,`<?xml version="1.0" encoding="utf-8"?>\n<!-- Original DS Bot Go silhouette; white eyes are transparent cutouts. SPDX-License-Identifier: MIT -->\n<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108"><path android:fillColor="#FF000000" android:fillType="nonZero" android:pathData="${mono}"/></vector>\n`);
const variants=[{suffix:'',mode:'light',bg:'#F7F9FD'},{suffix:'_night',mode:'dark',bg:'#18243D'},{suffix:'_ink',mode:'dark',bg:'#243DAD'},{suffix:'_frost',mode:'light',bg:'#EAF3FF'}];
const densities={mdpi:[48,108],hdpi:[72,162],xhdpi:[96,216],xxhdpi:[144,324],xxxhdpi:[192,432]};
for(const v of variants) {
  write(`${res}/drawable/ic_launcher${v.suffix}_background.xml`,`<?xml version="1.0" encoding="utf-8"?><shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle"><solid android:color="${v.bg}"/></shape>\n`);
  for(const round of ['', '_round']) write(`${res}/mipmap-anydpi-v26/ic_launcher${v.suffix}${round}.xml`,`<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background android:drawable="@drawable/ic_launcher${v.suffix}_background"/><foreground android:drawable="@mipmap/ic_launcher${v.suffix}_foreground"/><monochrome android:drawable="@drawable/ic_launcher_monochrome"/></adaptive-icon>\n`);
}
write('artwork.json',JSON.stringify({schema:1,grid:108,maximumPaintedRadius:32.5,safeCircleRadius:33,safeScale,parts:Object.fromEntries(Object.entries(parts).map(([n,s])=>[n,d(s)])),palettes,variants,densities,mono},null,2)+'\n');
execFileSync('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(out,'render-branding.ps1'),'-Root',out],{stdio:'inherit',windowsHide:true});
const files=[];
function walk(folder,rel=''){for(const item of fs.readdirSync(folder,{withFileTypes:true})){const r=rel?rel+'/'+item.name:item.name;if(item.isDirectory())walk(path.join(folder,item.name),r);else if(!['MANIFEST.json'].includes(r)){const b=fs.readFileSync(path.join(folder,item.name));files.push({path:r,bytes:b.length,sha256:crypto.createHash('sha256').update(b).digest('hex')});}}}
walk(out);write('MANIFEST.json',JSON.stringify({schema:1,name:'DS Bot Go original icon',createdAt:new Date().toISOString(),license:'MIT',reference:'DS Bot visual language only: blue/white, rounded volume, two simple eyes; no upstream artwork path reused.',files},null,2)+'\n');
console.log(JSON.stringify({files:files.length,manifest:path.join(out,'MANIFEST.json')}));
