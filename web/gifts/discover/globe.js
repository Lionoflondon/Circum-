(() => {
 const canvas=document.querySelector('#world'),ctx=canvas.getContext('2d');
 const motion=matchMedia('(prefers-reduced-motion: reduce)');
 let paused=motion.matches, visible=true, elapsed=0,last=0,frame=0,points=[],w=0,h=0,dpr=1;
 const cities=[[51.5,-.12],[48.86,2.35],[6.52,3.38],[40.71,-74],[34.05,-118],[35.67,139.6],[19.07,72.87],[28.6,77.2],[-23.55,-46.6],[-33.9,18.4],[30.04,31.2],[25.2,55.3],[1.35,103.8],[-33.87,151.2],[52.5,13.4]];
 function rng(seed){return()=>{seed=(seed*1664525+1013904223)>>>0;return seed/4294967296}}
 const random=rng(1641);
 function vector(lat,lon){let a=lat*Math.PI/180,b=lon*Math.PI/180;return [Math.cos(a)*Math.sin(b),Math.sin(a),Math.cos(a)*Math.cos(b)]}
 function resize(){let b=canvas.getBoundingClientRect();w=b.width;h=b.height;dpr=Math.min(devicePixelRatio||1,1.8);canvas.width=Math.round(w*dpr);canvas.height=Math.round(h*dpr);ctx.setTransform(dpr,0,0,dpr,0,0);render()}
 const routes=[[[51.5,-.12],[6.52,3.38]],[[51.5,-.12],[40.71,-74]],[[48.86,2.35],[25.2,55.3]],[[6.52,3.38],[-33.9,18.4]]].map(p=>p.map(c=>vector(...c)));
 function project(p,rot,r,cx,cy){let x=p[0]*Math.cos(rot)-p[2]*Math.sin(rot),z=p[0]*Math.sin(rot)+p[2]*Math.cos(rot);let tilt=.13,y=p[1]*Math.cos(tilt)-z*Math.sin(tilt);z=p[1]*Math.sin(tilt)+z*Math.cos(tilt);return{x:cx+x*r,y:cy-y*r,z}}
 function along(a,b,t){let dot=Math.max(-1,Math.min(1,a.reduce((s,v,i)=>s+v*b[i],0))),angle=Math.acos(dot),sa=Math.sin(angle);let f=Math.sin((1-t)*angle)/sa,g=Math.sin(t*angle)/sa;let lift=1+.17*Math.sin(t*Math.PI);return a.map((v,i)=>(v*f+b[i]*g)*lift)}
 function render(){if(!w)return;ctx.clearRect(0,0,w,h);let mobile=w<=650;let r=mobile?w*.72:Math.min(w*.39,h*.61),cx=mobile?w*.59:w*.755,cy=mobile?h*.68:h*.50;let rot=.31+elapsed*.022;
 // A restrained blue atmosphere, inspired by the supplied night-Earth reference.
 let glow=ctx.createRadialGradient(cx,cy,r*.93,cx,cy,r*1.085);glow.addColorStop(0,'#356d9500');glow.addColorStop(.48,'#6f9cb83b');glow.addColorStop(.65,'#37638926');glow.addColorStop(1,'#02080d00');ctx.fillStyle=glow;ctx.beginPath();ctx.arc(cx,cy,r*1.09,0,Math.PI*2);ctx.fill();
 ctx.save();ctx.beginPath();ctx.arc(cx,cy,r,0,Math.PI*2);ctx.clip();let ocean=ctx.createRadialGradient(cx-r*.35,cy-r*.6,r*.03,cx,cy,r);ocean.addColorStop(0,'#10202b');ocean.addColorStop(.46,'#080f16');ocean.addColorStop(.89,'#03070b');ocean.addColorStop(1,'#0f202e');ctx.fillStyle=ocean;ctx.fillRect(cx-r,cy-r,r*2,r*2);
 for(const p of points){let q=project(p.v,rot,r,cx,cy);if(q.z<.035)continue;let fade=Math.min(1,q.z*3),a=(p.b*.88+.14)*fade;ctx.fillStyle=`rgba(${p.hot?'235,211,177':'127,157,168'},${a})`;let size=(p.hot?.82:.55)*(r/450);ctx.fillRect(q.x,q.y,Math.max(.45,size),Math.max(.45,size));}
 // Delicate rim rather than a bright graphic outline.
 let shade=ctx.createLinearGradient(cx-r,cy-r,cx+r*.7,cy+r*.6);shade.addColorStop(0,'#06223b00');shade.addColorStop(.7,'#00000016');shade.addColorStop(1,'#000000bb');ctx.fillStyle=shade;ctx.fillRect(cx-r,cy-r,r*2,r*2);ctx.restore();ctx.strokeStyle='#a1cbe72d';ctx.lineWidth=.7;ctx.beginPath();ctx.arc(cx,cy,r-.5,0,Math.PI*2);ctx.stroke();
 routes.forEach(([a,b],i)=>{ctx.beginPath();let drawing=false;for(let j=0;j<=70;j++){let q=project(along(a,b,j/70),rot,r,cx,cy);if(q.z>0){if(!drawing)ctx.moveTo(q.x,q.y);else ctx.lineTo(q.x,q.y);drawing=true}else drawing=false;}ctx.strokeStyle=i%2?'#8badbb30':'#c2dace36';ctx.lineWidth=.7;ctx.stroke();let t=((elapsed*.045+i*.29)%1);let q=project(along(a,b,t),rot,r,cx,cy);if(q.z>.05){ctx.save();ctx.translate(q.x,q.y);ctx.shadowColor='#b4e9ec';ctx.shadowBlur=10;ctx.strokeStyle='#d4f0e9';ctx.lineWidth=.9;let sz=mobile?2.1:2.8;ctx.strokeRect(-sz,-sz,sz*2,sz*2);ctx.beginPath();ctx.moveTo(0,-sz);ctx.lineTo(0,sz);ctx.moveTo(-sz,0);ctx.lineTo(sz,0);ctx.stroke();ctx.restore();}
 let end=project(b,rot,r,cx,cy);if(end.z>.1){ctx.fillStyle='#b5d6d9';ctx.beginPath();ctx.arc(end.x,end.y,1.3,0,Math.PI*2);ctx.fill();let pulse=(elapsed*.28+i*.2)%1;ctx.strokeStyle=`rgba(173,217,220,${(1-pulse)*.24})`;ctx.beginPath();ctx.arc(end.x,end.y,3+pulse*12,0,Math.PI*2);ctx.stroke();}});
 }
 function tick(now){if(!paused&&visible){if(last)elapsed+=Math.min((now-last)/1000,.05);render()}last=now;frame=requestAnimationFrame(tick)}
 motion.addEventListener('change',()=>{paused=motion.matches;last=0;render()});document.addEventListener('visibilitychange',()=>{visible=!document.hidden;last=0});new IntersectionObserver(entries=>{visible=entries[0].isIntersecting&&!document.hidden;last=0},{threshold:.01}).observe(canvas);window.addEventListener('resize',resize);resize();
 fetch('assets/world.json').then(r=>{if(!r.ok)throw Error();return r.json()}).then(data=>{
  const map=document.createElement('canvas');map.width=1440;map.height=720;const c=map.getContext('2d',{willReadFrequently:true});c.fillStyle='#fff';
  const arcs=data.arcs.map(arc=>{let x=0,y=0;return arc.map(([dx,dy])=>{x+=dx;y+=dy;return[x*data.transform.scale[0]+data.transform.translate[0],y*data.transform.scale[1]+data.transform.translate[1]]})});
  function ring(ids){let out=[];ids.forEach(id=>{let a=id<0?arcs[~id].slice().reverse():arcs[id];out.push(...a)});return out}
  for(const geo of data.objects.countries.geometries){let polys=geo.type==='Polygon'?[geo.arcs]:geo.arcs;for(const polygon of polys){c.beginPath();for(const ids of polygon){let p=ring(ids);p.forEach(([lon,lat],i)=>{let x=(lon+180)*4,y=(90-lat)*4;if(i)c.lineTo(x,y);else c.moveTo(x,y)});c.closePath()}c.fill('evenodd')}}
  const pixels=c.getImageData(0,0,1440,720).data;
  for(let lat=-57;lat<77;lat+=.8){for(let lon=-180;lon<180;lon+=.8){let a=lat+(random()-.5)*.75,b=lon+(random()-.5)*.75;let px=Math.max(0,Math.min(1439,Math.floor((b+180)*4))),py=Math.max(0,Math.min(719,Math.floor((90-a)*4)));if(pixels[(py*1440+px)*4+3]<100)continue;let density=0;for(const city of cities){let d=(a-city[0])**2+((b-city[1])*Math.cos(a*Math.PI/180))**2;density=Math.max(density,Math.exp(-d/110))}let chance=.36+density*.55;if(random()>chance)continue;points.push({v:vector(a,b),b:.15+random()*.55+density*.27,hot:random()<.48+density*.45})}}
  canvas.dataset.ready='true';render();frame=requestAnimationFrame(tick);
 }).catch(()=>{canvas.setAttribute('aria-label','A softly lit globe');render();frame=requestAnimationFrame(tick)});
})();
