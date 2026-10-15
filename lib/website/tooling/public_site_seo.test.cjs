const {test}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const os=require('node:os');const path=require('node:path');const {execFileSync}=require('node:child_process');
const {build,pages}=require('./public_site_seo.cjs');
test('generated public pages have unique canonical metadata and account shells remain noindex',()=>{
 const out=fs.mkdtempSync(path.join(os.tmpdir(),'circum-seo-'));try{
 fs.cpSync('web',out,{recursive:true});build(out);
 for(const [route,[title]] of Object.entries(pages)){
  const file=route==='/'?'index.html':route.endsWith('/')?route.slice(1)+'index.html':'seo/routes'+route+'.html';
  const html=fs.readFileSync(path.join(out,file),'utf8');assert(html.includes(title.replaceAll('&','&amp;')));assert(html.includes(`href="https://circumuk.com${route}"`));
  const ld=JSON.parse(html.match(/<script type="application\/ld\+json">(.*?)<\/script>/s)[1]);assert(ld['@graph'].some(n=>n['@type']==='WebPage'));
 }
 assert(fs.readFileSync(path.join(out,'seo/routes/send/profile.html'),'utf8').includes('noindex, follow'));
 const sitemap=fs.readFileSync(path.join(out,'sitemap.xml'),'utf8');assert(!sitemap.includes('/air'));assert(!sitemap.includes('/send'));assert(sitemap.includes('/delivery/'));
 assert(fs.readFileSync(path.join(out,'robots.txt'),'utf8').startsWith('User-agent: *'));
 assert(fs.readFileSync(path.join(out,'air/index.html'),'utf8').includes('noindex'));
 }finally{fs.rmSync(out,{recursive:true,force:true});}
});
test('certified backend guard rejects API, other target, header and unexpected route changes',()=>{
 const {validate}=require('./validate_website_hosting_change.cjs');
 const before=JSON.parse(execFileSync('git',['show','f1275c63ab3db56f220ee4f557582db44e257301:firebase.json'],{encoding:'utf8'}));const after=JSON.parse(fs.readFileSync('firebase.json'));
 validate(before,after);
 for(const mutate of [a=>a.hosting[0].rewrites[0].run.serviceId='bad',a=>a.hosting[1].public='bad',a=>a.hosting[0].headers=[],a=>a.hosting[0].rewrites.push({source:'**',destination:'/index.html'})]){const bad=structuredClone(after);mutate(bad);assert.throws(()=>validate(before,bad));}
});
test('AIR logos are scalable paths, with no embedded raster images',()=>{
 for(const name of ['air','one']){const svg=fs.readFileSync(`web/air/assets/circum-${name}-vector.svg`,'utf8');assert(svg.includes('<path'));assert(!svg.includes('<image'));assert(!svg.includes('base64'));assert(svg.includes('linearGradient'));}
});
