const fs=require('node:fs');
const path=require('node:path');
const origin='https://circumuk.com';
const pages={
 '/':['London Parcel Delivery & Courier Services | CIRCUM','Book, track and manage deliveries across London and surrounding areas. Explore CIRCUM parcel delivery, thoughtful gifts, Health+ and business deliveries.'],
 '/delivery/':['Parcel Delivery in London | CIRCUM Courier Services','Arrange a London parcel delivery with CIRCUM. Add collection and delivery addresses, review the price and follow your delivery in your account.'],
 '/gifts/discover/':['Gift Delivery | Thoughtful Surprises by CIRCUM','Send a thoughtful gift with CIRCUM. Share their interests, occasion, budget and destination so the Gifts team can curate the surprise and plan delivery.'],
 '/health/discover/':['Pharmacy & Prescription Collection in London | CIRCUM Health+','Arrange eligible pharmacy and prescription collections in London with CIRCUM Health+. Review collection details, delivery options and availability.'],
 '/business/discover/':['Business Delivery Services | CIRCUM Business','Explore CIRCUM Business for company deliveries. Sign in to manage your business delivery requests, collection details and available options.'],
 '/rider':['Become a Delivery Rider | CIRCUM','Explore the CIRCUM Rider Order, learn about the application process and start rider onboarding.'],
 '/vanguard':['Vanguard | CIRCUM Delivery Protection','Explore Vanguard delivery protection with CIRCUM. Review the available options, eligibility and terms for your delivery.'],
 '/support':['Customer Support | CIRCUM Deliveries','Get help with your CIRCUM account, deliveries and payments. Find contact details and support for sign-in, delivery status and payment queries.'],
 '/privacy_policy':['Privacy Policy | CIRCUM','Read how Circum Technologies Ltd handles personal information across its delivery services, apps and websites.'],
 '/terms':['Terms & Conditions | CIRCUM','Read the terms and conditions for using CIRCUM services.'],
 '/cookie_policy':['Cookie & Storage Policy | CIRCUM','Learn about cookies and storage technologies on CIRCUM and how to manage your preferences.'],
 '/delete_account':['Delete Your Account | CIRCUM','Find information about requesting deletion of your CIRCUM account and related data.'],
 '/roth/':['ROTH Credits & Wallet Top-ups | CIRCUM','Learn about ROTH, CIRCUM credits held separately from cash. Verify your existing account to review top-up options.']
};
const privateRoutes=['/send','/send/profile','/send/health','/send/business','/gifts','/rider/onboarding','/unsubscribe','/newsletter'];
const esc=s=>s.replaceAll('&','&amp;').replaceAll('"','&quot;').replaceAll('<','&lt;');
function metadata(html,route,title,description,noindex=false){
 html=html.replace(/<html>/i,'<html lang="en-GB">');
 html=html.replace(/<title>[^<]*<\/title>/i,'').replace(/<meta\b[^>]*name=["'](?:description|robots)["'][^>]*>/gi,'').replace(/<link\b[^>]*rel=["']canonical["'][^>]*>/gi,'');
 const url=origin+route;
 const graph=[{'@type':'Organization','@id':origin+'/#organization',name:'Circum Technologies Ltd',url:origin+'/',logo:origin+'/icons/Icon-192.png',sameAs:['https://www.instagram.com/circumuk/','https://www.tiktok.com/@circumuk','https://x.com/circumuk']},{'@type':'WebSite','@id':origin+'/#website',url:origin+'/',name:'CIRCUM',publisher:{'@id':origin+'/#organization'}},{'@type':'WebPage','@id':url+'#page',url,name:title,description,isPartOf:{'@id':origin+'/#website'},inLanguage:'en-GB'}];
 if(route!=='/'&&!noindex)graph.push({'@type':'BreadcrumbList',itemListElement:[{'@type':'ListItem',position:1,name:'CIRCUM',item:origin+'/'},{'@type':'ListItem',position:2,name:title.split('|')[0].trim(),item:url}]});
 if(['/delivery/','/health/discover/','/business/discover/','/gifts/discover/'].includes(route)){
  const service={'@type':'Service',name:title.split('|')[0].trim(),description,url,provider:{'@id':origin+'/#organization'}};
  if(['/delivery/','/health/discover/'].includes(route))service.areaServed={'@type':'Place',name:'London'};
  graph.push(service);
 }
 const tags=`<title>${esc(title)}</title>\n<meta name="description" content="${esc(description)}">\n<link rel="canonical" href="${url}">\n<meta name="robots" content="${noindex?'noindex, follow':'index, follow, max-image-preview:large'}">\n<meta property="og:type" content="website"><meta property="og:site_name" content="CIRCUM"><meta property="og:locale" content="en_GB"><meta property="og:title" content="${esc(title)}"><meta property="og:description" content="${esc(description)}"><meta property="og:url" content="${url}"><meta property="og:image" content="${origin}/seo/circum-social.png"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630"><meta property="og:image:alt" content="CIRCUM — Move what matters"><meta name="twitter:card" content="summary_large_image">\n<script type="application/ld+json">${JSON.stringify({'@context':'https://schema.org','@graph':graph})}</script>\n`;
 return html.replace('</head>',tags+'</head>');
}
function build(out){
 const root=path.join(out,'index.html'),shell=fs.readFileSync(root,'utf8');
 fs.mkdirSync(path.join(out,'seo/routes'),{recursive:true});
 for(const [route,[title,description]] of Object.entries(pages)){
  const staticPath=route.endsWith('/')&&route!=='/'?path.join(out,route.slice(1),'index.html'):null;
  const source=staticPath&&fs.existsSync(staticPath)?fs.readFileSync(staticPath,'utf8'):shell;
  let html=metadata(source,route,title,description);
  if(source===shell){
   const fallback=`<section id="circum-loading-content" style="padding:32px;max-width:960px;margin:auto;font-family:Arial,sans-serif"><h1>${esc(title.split('|')[0].trim())}</h1><p>${esc(description)}</p><nav aria-label="CIRCUM services"><a href="/delivery/">London deliveries</a> · <a href="/gifts/discover/">Gift delivery</a> · <a href="/health/discover/">Health+</a> · <a href="/business/discover/">Business</a> · <a href="/support">Support</a></nav><noscript><p>JavaScript is needed for the interactive account and booking screens.</p></noscript></section><script>window.addEventListener('flutter-first-frame',function(){document.getElementById('circum-loading-content')?.remove();},{once:true});</script>`;
   html=html.replace('<body>','<body>'+fallback);
  }
  const target=route==='/'?root:staticPath&&fs.existsSync(staticPath)?staticPath:path.join(out,'seo/routes',route.slice(1)+'.html');
  fs.writeFileSync(target,html);
 }
 const account=metadata(shell,'/send','Sign In | CIRCUM','Sign in to manage your CIRCUM account and deliveries.',true);
 fs.writeFileSync(path.join(out,'seo/account.html'),account);
 for(const route of privateRoutes){
  const filename=path.join(out,'seo/routes',route.slice(1)+'.html');fs.mkdirSync(path.dirname(filename),{recursive:true});
  fs.writeFileSync(filename,metadata(shell,route,'Your Account | CIRCUM','Access your CIRCUM account and services.',true));
 }
 fs.writeFileSync(path.join(out,'robots.txt'),'User-agent: *\nAllow: /\nDisallow: /seo/routes/\nDisallow: /seo/account.html\n\nSitemap: '+origin+'/sitemap.xml\n');
 fs.writeFileSync(path.join(out,'sitemap.xml'),'<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'+Object.keys(pages).map(r=>`  <url><loc>${origin+r}</loc></url>`).join('\n')+'\n</urlset>\n');
 // Keep the previously submitted Search Console sitemap address valid.
 fs.copyFileSync(path.join(out,'sitemap.xml'),path.join(out,'sitemap.website.xml'));
}
module.exports={build,metadata,pages,privateRoutes};
if(require.main===module)build(process.argv[2]);
