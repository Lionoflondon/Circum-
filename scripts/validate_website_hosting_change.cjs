const assert=require('node:assert/strict');
const {execFileSync}=require('node:child_process');
const fs=require('node:fs');
// Only public HTML routing may differ from the certified backend release.
// API rewrites, headers, other targets and all non-hosting settings stay exact.
function validate(before,after){
 if (require('node:util').isDeepStrictEqual(before,after)) return;
 const b=structuredClone(before),a=structuredClone(after);
 const bp=b.hosting.find(h=>h.target==='public'),ap=a.hosting.find(h=>h.target==='public');
 assert.deepEqual(ap.rewrites.filter(r=>r.run||r.function),bp.rewrites.filter(r=>r.run||r.function),'API routing changed');
 const publicRoutes=['rider','vanguard','support','privacy_policy','terms','cookie_policy','delete_account'];
 const privateRoutes=['send','send/profile','send/health','send/business','gifts','rider/onboarding','unsubscribe','newsletter'];
 const approved=[...bp.rewrites.filter(r=>r.run||r.function),...[...publicRoutes,...privateRoutes].map(r=>({source:`/${r}{,/}`,destination:`/seo/routes/${r}.html`})),...['send','rider','gifts','join'].map(r=>({source:`/${r}/**`,destination:'/seo/account.html'}))];
 assert.deepEqual(ap.rewrites,approved,'Unapproved public rewrite');
 const extra={source:'/delete-account',destination:'/delete_account',type:308};
 assert.deepEqual(ap.redirects,[...bp.redirects,extra],'Unapproved redirect');
 ap.rewrites=bp.rewrites;ap.redirects=bp.redirects;
 assert.deepEqual(a,b,'Protected hosting or backend configuration changed');
}
module.exports={validate};
if(require.main===module){
 const ref=process.argv[2];assert.match(ref,/^[a-f0-9]{40}$/);
 validate(JSON.parse(execFileSync('git',['show',`${ref}:firebase.json`],{encoding:'utf8'})),JSON.parse(fs.readFileSync('firebase.json')));
 console.log('Only approved public HTML routes changed; protected configuration is identical.');
}
