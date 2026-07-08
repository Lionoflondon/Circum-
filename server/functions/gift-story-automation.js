/* eslint-disable max-len, require-jsdoc */
"use strict";

const crypto = require("crypto");
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");

const STORY_RETENTION_HOURS = 48;
const COMPLETE_STATUSES = new Set(["completed", "complete", "delivered"]);
const STORY_SKINS = new Set(["iridescent", "pink", "blue", "classic_dark"]);
const MAX_STORY_SLIDES = 16;

function text(value) {
  return `${value || ""}`.trim();
}

function normalizeEmail(value) {
  return text(value).toLowerCase();
}

function isComplete(value) {
  return COMPLETE_STATUSES.has(text(value).toLowerCase());
}

function isGiftDelivery(delivery) {
  return text(delivery.serviceType).toUpperCase() === "GIFTS" ||
    text(delivery.sourceModule).toLowerCase() === "gifts" ||
    Boolean(delivery.giftOrderId || delivery.giftRequestId);
}

function tokenHash(token) {
  return crypto.createHash("sha256").update(token).digest("hex");
}

function storyLink(token) {
  return `https://circumuk.com/story/${encodeURIComponent(token)}`;
}

function recipientStoryLink(token) {
  return `https://circumuk.com/story/${encodeURIComponent(token)}`;
}

function giftStoryStoragePaths(giftId) {
  return {
    source: `gifts/${giftId}/story/source/`,
    silent: `gifts/${giftId}/story/exports/silent/`,
    sound: `gifts/${giftId}/story/exports/sound/`,
    thumbs: `gifts/${giftId}/story/thumbs/`,
  };
}

function cleanSkin(value) {
  const skin = text(value).toLowerCase().replace(/-/g, "_");
  return STORY_SKINS.has(skin) ? skin : "iridescent";
}

function safeSlide(slide = {}) {
  return {
    type: text(slide.type || "why_chosen"),
    eyebrow: text(slide.eyebrow),
    headline: text(slide.headline),
    body: text(slide.body),
    mediaUrl: text(slide.mediaUrl || slide.imageUrl),
    durationMs: Math.max(2200, Math.min(Number(slide.durationMs || 5200), 12000)),
  };
}

function buildGiftStorySlides(gift = {}) {
  const existing = Array.isArray(gift.giftStorySlides) ? gift.giftStorySlides.map(safeSlide).filter((slide) => slide.headline || slide.body) : [];
  if (existing.length) {
    const capped = existing.slice(0, MAX_STORY_SLIDES);
    if (capped[capped.length - 1].type !== "finale") {
      capped.splice(MAX_STORY_SLIDES - 1, 1, finalStorySlide());
    }
    return capped;
  }
  const recipientName = text(gift.recipientName) || "there";
  const senderName = text(gift.senderName) || "Someone special";
  const slides = [
    {
      type: "arrival",
      eyebrow: "GIFTS BY CIRCUM",
      headline: `Your gift has arrived, ${recipientName}.`,
      body: "A small story before the reveal.",
      durationMs: 5200,
    },
  ];
  const voice = gift.voiceNote && typeof gift.voiceNote === "object" ? gift.voiceNote : {};
  const voiceUrl = text(voice.downloadUrl || voice.storagePath);
  if (voiceUrl) {
    slides.push({
      type: "voice_note",
      eyebrow: "A voice note",
      headline: "A message was left for you.",
      body: "Use the sound toggle to hear it.",
      mediaUrl: voiceUrl,
      durationMs: 6200,
    });
  } else {
    slides.push({
      type: "note",
      eyebrow: "A note",
      headline: text(gift.personalMessage || gift.senderMessageText) || "This was chosen with care.",
      body: `From ${senderName}`,
      durationMs: 6200,
    });
  }
  const items = Array.isArray(gift.giftItems) ? gift.giftItems :
    Array.isArray(gift.approvedGiftItems) ? gift.approvedGiftItems :
      Array.isArray(gift.giftStoryItems) ? gift.giftStoryItems : [];
  const safeItems = items.length ? items : [{name: text(gift.giftItemsSummary || gift.approvedRevealSummary || "Your gift"), why: text(gift.giftStoryCircumMessage || "Because it felt like you.")}];
  for (const item of safeItems) {
    if (slides.length >= MAX_STORY_SLIDES - 1) break;
    slides.push({
      type: "gift_reveal",
      eyebrow: "The reveal",
      headline: text(item.name || item.title) || "Your gift",
      body: "Chosen, prepared, and delivered for this moment.",
      mediaUrl: text(item.mediaUrl || item.imageUrl || item.photoUrl),
      durationMs: 5400,
    });
    if (slides.length >= MAX_STORY_SLIDES - 1) break;
    slides.push({
      type: "why_chosen",
      eyebrow: "Why we chose it",
      headline: text(item.why || item.whyChosen) || "Because it felt like you.",
      body: "The Gifts Team shaped this around the intention behind the gift.",
      durationMs: 5600,
    });
  }
  slides.push(finalStorySlide());
  return slides.slice(0, MAX_STORY_SLIDES);
}

function finalStorySlide() {
  return {
    type: "finale",
    eyebrow: "Finale",
    headline: "Tell sender thank you",
    body: "Replay story. Keep this story in the Circum app.",
    durationMs: 7000,
  };
}

function storySkinVars(skin) {
  switch (cleanSkin(skin)) {
    case "pink":
      return {violet: "#ffb3c9", violet2: "#ffd1e0", rosegold: "#fff0f5", champagne: "#ffc2d6", lilac: "#ff8fae"};
    case "blue":
      return {violet: "#7fc4f2", violet2: "#b8e2ff", rosegold: "#eaf6ff", champagne: "#d9f2ff", lilac: "#4fa8e0"};
    case "classic_dark":
      return {violet: "#d8c08d", violet2: "#f5e5b8", rosegold: "#f5f3ed", champagne: "#d8c08d", lilac: "#9f8d64"};
    default:
      return {violet: "#a8edea", violet2: "#c9b8ff", rosegold: "#ffd6e8", champagne: "#b8f0d8", lilac: "#d4c5ff"};
  }
}

function escapeHtml(value) {
  return text(value).replace(/[&<>"']/g, (char) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "\"": "&quot;",
    "'": "&#39;",
  })[char]);
}

function canRevealSender(gift = {}) {
  const mode = text(gift.senderRevealMode || "anonymous_forever");
  if (mode === "reveal_immediately") return true;
  if (mode === "reveal_after_delivery" && isComplete(gift.giftStatus || gift.status)) return true;
  return text(gift.senderRevealConsent) === "granted" && text(gift.recipientRevealRequestStatus) === "approved";
}

function renderGiftStoryHtml({token, giftId, gift, role}) {
  const skin = cleanSkin(gift.giftStorySkin);
  const vars = storySkinVars(skin);
  const slides = buildGiftStorySlides({
    ...gift,
    senderName: canRevealSender(gift) ? gift.senderName : "Someone special",
  });
  const slidesJson = JSON.stringify(slides).replace(/</g, "\\u003c");
  const appDeepLink = `https://circum-app-2797c.web.app/?app=sender&giftStoryToken=${encodeURIComponent(token)}#/sender-mobile/gifts/story`;
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow,noarchive"><title>Gifts by Circum Story</title><link rel="preconnect" href="https://fonts.googleapis.com"><link href="https://fonts.googleapis.com/css2?family=DM+Serif+Display:ital@0;1&family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet"><style>
:root{--void:#090B1D;--void-2:#10122A;--ink:#F5F3ED;--ink-dim:rgba(245,243,237,.58);--hairline:rgba(245,243,237,.14);--violet:${vars.violet};--violet-2:${vars.violet2};--rosegold:${vars.rosegold};--champagne:${vars.champagne};--lilac:${vars.lilac};--foil:conic-gradient(from 200deg,var(--violet),var(--violet-2),var(--rosegold),var(--champagne),var(--lilac),var(--violet));--serif:'DM Serif Display',serif;--sans:'Inter',-apple-system,sans-serif;--mono:'JetBrains Mono',monospace}*{box-sizing:border-box}html,body{margin:0;height:100%;background:var(--void);color:var(--ink);font-family:var(--sans);overflow:hidden}.story{position:fixed;inset:0;background:radial-gradient(ellipse 430px 360px at 50% 30%,color-mix(in srgb,var(--violet) 28%,transparent),transparent 70%),var(--void);isolation:isolate}.progress{position:absolute;top:12px;left:12px;right:12px;z-index:20;display:flex;gap:5px}.bar{height:2.5px;flex:1;background:rgba(245,243,237,.22);border-radius:3px;overflow:hidden}.fill{height:100%;width:0;background:linear-gradient(90deg,var(--violet-2),var(--champagne))}.head{position:absolute;top:24px;left:14px;right:14px;z-index:20;display:flex;align-items:center;justify-content:space-between}.who{display:flex;gap:8px;align-items:center}.avatar{width:24px;height:24px;border-radius:50%;background:var(--foil)}.name{font-size:12px;font-weight:700}.time{font-family:var(--mono);font-size:9.5px;color:var(--ink-dim)}button{font-family:inherit}.sound{width:30px;height:30px;border-radius:50%;border:1px solid rgba(245,243,237,.25);background:rgba(0,0,0,.25);color:var(--ink)}.slide{position:absolute;inset:0;display:flex;flex-direction:column;justify-content:flex-end;padding:24px 20px 30px;opacity:0;transform:scale(1.02);transition:opacity .25s ease}.slide.show{opacity:1;transform:scale(1)}.eyebrow{font-family:var(--mono);font-size:10px;letter-spacing:.1em;text-transform:uppercase;color:var(--violet-2);margin-bottom:10px}.headline{font-family:var(--serif);font-size:29px;line-height:1.14}.body{font-size:13px;color:var(--ink-dim);margin-top:10px;line-height:1.5}.center{justify-content:center;text-align:center;align-items:center}.orb{width:104px;height:104px;border-radius:50%;margin-bottom:26px;background:var(--foil);box-shadow:0 0 60px color-mix(in srgb,var(--violet) 55%,transparent);animation:spin 7s linear infinite;position:relative}.orb:after{content:'';position:absolute;inset:14px;border-radius:50%;background:var(--void);opacity:.9}@keyframes spin{to{transform:rotate(360deg)}}.note{background:rgba(245,243,237,.05);border:1px solid var(--hairline);border-radius:4px;padding:28px 22px;position:relative}.note:before{content:'';position:absolute;top:0;left:22px;width:34px;height:8px;background:color-mix(in srgb,var(--champagne) 45%,transparent);transform:rotate(-3deg)}.quote{font-family:var(--serif);font-style:italic;font-size:18px;line-height:1.55}.meta{margin-top:16px;font-family:var(--mono);font-size:10.5px;color:var(--ink-dim)}.candle{width:78px;height:118px;position:relative;margin:0 auto}.glass{position:absolute;bottom:0;left:0;right:0;height:88px;border-radius:6px 6px 10px 10px;background:linear-gradient(180deg,color-mix(in srgb,var(--rosegold) 18%,transparent),color-mix(in srgb,var(--violet) 14%,transparent));border:1px solid rgba(245,243,237,.18)}.wax{position:absolute;bottom:6px;left:6px;right:6px;height:40px;border-radius:3px;background:linear-gradient(180deg,var(--rosegold),var(--lilac));opacity:.9}.wick{position:absolute;bottom:44px;left:50%;width:2px;height:14px;background:#3a2c22;transform:translateX(-50%)}.flame{position:absolute;bottom:56px;left:50%;width:9px;height:16px;border-radius:50% 50% 50% 50%/60% 60% 40% 40%;background:radial-gradient(circle at 50% 70%,#fff,var(--violet-2) 50%,var(--lilac));transform:translateX(-50%);animation:flicker 2.4s ease-in-out infinite}@keyframes flicker{0%,100%{transform:translateX(-50%) scale(1)}30%{transform:translateX(-50%) scale(.94,1.05) rotate(-2deg)}60%{transform:translateX(-50%) scale(1.05,.96) rotate(2deg)}}.cta{display:block;width:100%;border:0;border-radius:14px;padding:14px;margin-top:10px;font-weight:800}.primary{background:var(--ink);color:#090B1D}.secondary{background:rgba(245,243,237,.08);color:var(--ink);border:1px solid var(--hairline)}.thank{display:none;position:absolute;inset:auto 16px 18px;z-index:30;background:#10122A;border:1px solid var(--hairline);border-radius:18px;padding:16px}.thank textarea{width:100%;min-height:80px;border-radius:12px;border:1px solid var(--hairline);background:#161A3A;color:var(--ink);padding:12px}.ribbon{position:absolute;inset:0;pointer-events:none;background:linear-gradient(115deg,transparent 35%,color-mix(in srgb,var(--violet-2) 22%,transparent),transparent 65%);transform:translateX(-120%);animation:ribbon 900ms ease}@keyframes ribbon{to{transform:translateX(120%)}}</style></head><body><main class="story" id="story"><div class="progress" id="progress"></div><div class="head"><div class="who"><div class="avatar"></div><div><div class="name">Gifts by Circum</div><div class="time">just now</div></div></div><button class="sound" id="sound">♪</button></div><div id="slides"></div><section class="thank" id="thank"><textarea id="thanks" placeholder="Write a thank-you message..."></textarea><button class="cta primary" id="sendThanks">Send thank you</button><a class="cta secondary" href="${appDeepLink}" style="text-align:center;text-decoration:none">Keep this story in the Circum app</a></section></main><script>
const slides=${slidesJson};const token=${JSON.stringify(token)};let i=0,timer=null,paused=false,muted=false;const root=document.getElementById('slides'),progress=document.getElementById('progress');function build(){progress.innerHTML=slides.map(()=>'<div class="bar"><div class="fill"></div></div>').join('');root.innerHTML=slides.map((s,idx)=>'<section class="slide '+(idx===0?'show':'')+'" data-type="'+s.type+'"></section>').join('');slides.forEach((s,idx)=>renderSlide(root.children[idx],s));run()}function renderSlide(el,s){if(s.type==='arrival'){el.className+=' center';el.innerHTML='<div class="orb"></div><div class="headline">'+esc(s.headline)+'</div><div class="body">'+esc(s.body)+'</div>';return}if(s.type==='note'||s.type==='voice_note'){el.style.justifyContent='center';el.innerHTML='<div class="note"><div class="quote">'+esc(s.headline)+'</div><div class="meta">'+esc(s.body)+'</div></div>';return}if(s.type==='gift_reveal'){el.style.justifyContent='space-between';el.style.paddingTop='70px';el.style.textAlign='center';el.innerHTML='<div class="candle"><div class="glass"></div><div class="wax"></div><div class="wick"></div><div class="flame"></div></div><div><div class="eyebrow">'+esc(s.eyebrow)+'</div><div class="headline">'+esc(s.headline)+'</div><div class="body">'+esc(s.body)+'</div></div>';return}if(s.type==='finale'){el.innerHTML='<div><div class="eyebrow">Finale</div><div class="headline">Tell sender thank you</div><div class="body">Replay story. Keep this story in the Circum app.</div><button class="cta primary" onclick="openThanks()">Tell sender thank you</button><button class="cta secondary" onclick="replay()">Replay story</button><a class="cta secondary" href="${appDeepLink}" style="text-align:center;text-decoration:none">Keep this story in the Circum app</a></div>';return}el.style.justifyContent='center';el.innerHTML='<div class="eyebrow">'+esc(s.eyebrow)+'</div><div class="headline">'+esc(s.headline)+'</div><div class="body">'+esc(s.body)+'</div>'}function esc(v){return String(v||'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]))}function show(n){i=Math.max(0,Math.min(slides.length-1,n));[...root.children].forEach((el,idx)=>el.classList.toggle('show',idx===i));run();const rib=document.createElement('div');rib.className='ribbon';document.body.appendChild(rib);setTimeout(()=>rib.remove(),900)}function run(){clearTimeout(timer);[...progress.children].forEach((b,idx)=>{const f=b.firstChild;f.style.transition='none';f.style.width=idx<i?'100%':'0%';if(idx===i){requestAnimationFrame(()=>{f.style.transition='width '+(slides[i].durationMs||5200)+'ms linear';f.style.width='100%'})}});timer=setTimeout(()=>{if(i<slides.length-1)show(i+1)},slides[i].durationMs||5200)}function replay(){show(0)}function openThanks(){document.getElementById('thank').style.display='block'}document.getElementById('story').addEventListener('pointerdown',e=>{paused=true;clearTimeout(timer)});document.getElementById('story').addEventListener('pointerup',e=>{if(document.getElementById('thank').style.display==='block')return; if(paused){paused=false; if(e.clientX<innerWidth/2)show(i-1); else show(i+1)}});document.getElementById('sound').onclick=()=>{muted=!muted;document.getElementById('sound').textContent=muted?'×':'♪'};document.getElementById('sendThanks').onclick=async()=>{const thankYouMessage=document.getElementById('thanks').value.trim();if(!thankYouMessage)return;await fetch('${submitThankYouUrl()}',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({token,thankYouMessage})}).catch(()=>null);document.getElementById('thank').innerHTML='<div class="headline" style="font-size:24px">Thank you sent.</div><div class="body">You can still keep this story in the Circum app.</div><a class="cta secondary" href="${appDeepLink}" style="text-align:center;text-decoration:none">Keep this story in the Circum app</a>'};build();
</script></body></html>`;
}

function safeStory(giftId, gift) {
  return {
    id: giftId,
    giftStoryEnabled: true,
    giftStoryApproved: gift.giftStoryApproved !== false,
    giftStoryShareEnabled: gift.giftStoryShareEnabled !== false,
    giftStorySharePrivacy: gift.giftStorySharePrivacy || "private",
    giftStoryVideoStatus: gift.giftStoryVideoStatus || "processing",
    giftStoryVideoExpiresAt: gift.giftStoryVideoExpiresAt || null,
    giftStoryMusicEnabled: gift.giftStoryMusicEnabled === true,
    giftStoryCustomAudioUrl: gift.giftStoryCustomAudioUrl || null,
    giftStoryPhotos: Array.isArray(gift.giftStoryPhotos) ? gift.giftStoryPhotos : [],
    giftStoryPhotoUrls: Array.isArray(gift.giftStoryPhotoUrls) ? gift.giftStoryPhotoUrls : [],
    giftStoryCircumMessage: gift.giftStoryCircumMessage || "",
    senderMessageText: gift.senderMessageText || gift.personalMessage || "",
    personalMessage: gift.personalMessage || "",
    senderName: gift.senderName || "Someone special",
    recipientName: gift.recipientName || "Recipient",
    relationship: gift.relationship || "",
    occasion: gift.occasion || "A special moment",
    deliveryDate: gift.deliveryDate || gift.deliveredAt || null,
    deliveryTimeWindow: gift.deliveryTimeWindow || "Delivered",
    interestTags: Array.isArray(gift.interestTags) ? gift.interestTags : [],
    interests: Array.isArray(gift.interests) ? gift.interests : [],
    giftItemsSummary: gift.giftItemsSummary || gift.approvedRevealSummary || "",
    approvedGiftPhotoUrls: Array.isArray(gift.approvedGiftPhotoUrls) ? gift.approvedGiftPhotoUrls : [],
    status: "delivered",
    giftStatus: "delivered",
  };
}

function list(value) {
  return Array.isArray(value) ? value.map((item) => text(item)).filter(Boolean) : [];
}

function bool(value) {
  if (value === true) return true;
  if (value === false || value == null) return false;
  return ["true", "yes", "accepted", "consented", "allow", "allowed"].includes(text(value).toLowerCase());
}

function hasActiveGiftDispute(gift = {}) {
  return bool(gift.activeDispute) ||
    bool(gift.activeInvestigation) ||
    bool(gift.deliveryInvestigationActive) ||
    bool(gift.activeDeliveryDispute) ||
    bool(gift.hasActiveDeliveryDispute) ||
    bool(gift.disputeOpen) ||
    ["open", "active", "investigating", "under_review"].includes(text(gift.disputeStatus).toLowerCase()) ||
    ["open", "active", "investigating", "under_review"].includes(text(gift.investigationStatus).toLowerCase());
}

function revealPolicyAllowsMutualReveal(policy) {
  const clean = text(policy).toLowerCase();
  if (!clean || clean === "anonymous_only" || clean === "anonymous") return false;
  return [
    "mutual_consent",
    "anonymous_until_consent",
    "reveal_after_delivery",
    "reveal_immediately",
    "mutual-reveal",
  ].includes(clean);
}

function participantRevealConsent(participant = {}) {
  return bool(participant.revealConsent) ||
    bool(participant.identityRevealConsent) ||
    bool(participant.senderRevealConsent) ||
    bool(participant.matchRevealConsent);
}

function storyViewedByRequiredUsers(gift = {}, participantA = {}, participantB = {}) {
  const viewedBy = new Set([
    ...list(gift.storyViewedBy),
    ...list(gift.giftStoryViewedBy),
    ...list(gift.giftStoryViewedByUserIds),
  ]);
  const aUserId = text(participantA.userId || participantA.uid);
  const bUserId = text(participantB.userId || participantB.uid);
  if (aUserId && bUserId) return viewedBy.has(aUserId) && viewedBy.has(bUserId);
  return bool(gift.storyViewedByBothParticipants) || bool(gift.giftStoryViewedByBothParticipants);
}

function campaignRevealMatchDecision({gift = {}, participantA = {}, participantB = {}} = {}) {
  const storyStatus = text(gift.giftStoryStatus || gift.storyStatus || (gift.giftStoryUnlocked ? "unlocked" : "")).toLowerCase();
  if (storyStatus !== "unlocked") return {create: false, reason: "story_locked"};
  if (!storyViewedByRequiredUsers(gift, participantA, participantB)) return {create: false, reason: "story_not_viewed"};
  if (!participantRevealConsent(participantA) || !participantRevealConsent(participantB)) {
    return {create: false, reason: "waiting_for_mutual_reveal_consent"};
  }
  if (!revealPolicyAllowsMutualReveal(gift.revealPolicy || gift.senderRevealMode || participantA.revealPolicy || participantB.revealPolicy)) {
    return {create: false, reason: "reveal_policy_blocks"};
  }
  if (hasActiveGiftDispute(gift)) return {create: false, reason: "active_dispute"};
  return {create: true, reason: "eligible"};
}

function safeName(participant = {}) {
  return text(participant.displayName || participant.name || participant.anonymousHandle || "Campaign match");
}

function buildRevealedCampaignMatchRecord({matchId, giftStoryId, gift = {}, participantA = {}, participantB = {}, now = null} = {}) {
  const sharedInterests = list(gift.sharedInterests).length ?
    list(gift.sharedInterests) :
    [...new Set([...list(participantA.interests), ...list(participantB.interests)].filter((interest) => list(participantA.interests).includes(interest) && list(participantB.interests).includes(interest)))];
  return {
    matchId,
    campaignId: text(gift.campaignId || participantA.campaignId || participantB.campaignId),
    giftStoryId: text(giftStoryId || gift.giftStoryId || gift.id),
    participantAUserId: text(participantA.userId || participantA.uid),
    participantBUserId: text(participantB.userId || participantB.uid),
    participantAName: safeName(participantA),
    participantBName: safeName(participantB),
    participantAProfilePhotoUrl: text(participantA.profilePhotoUrl || participantA.photoUrl),
    participantBProfilePhotoUrl: text(participantB.profilePhotoUrl || participantB.photoUrl),
    sharedInterests,
    matchDate: now,
    revealConfirmedAt: now,
    storyViewedAt: now,
    createdAt: now,
    status: "revealed",
    source: "gift_campaign",
  };
}

async function maybeCreateRevealedCampaignMatch(db, giftRef, giftId, gift, viewerUserId = "") {
  if (text(gift.giftType) !== "campaign" && text(gift.anonymousGiftType) !== "campaign" && text(gift.source) !== "gift_campaign") {
    return {created: false, reason: "not_campaign"};
  }
  const viewedBy = new Set([...list(gift.storyViewedBy), ...list(gift.giftStoryViewedBy)]);
  if (viewerUserId) viewedBy.add(viewerUserId);
  const nextGift = {
    ...gift,
    id: giftId,
    storyViewedBy: [...viewedBy],
    giftStoryStatus: gift.giftStoryStatus || (gift.giftStoryUnlocked ? "unlocked" : ""),
  };
  const participantAId = text(gift.campaignParticipantId || gift.participantAId || gift.senderCampaignParticipantId);
  const participantBId = text(gift.linkedParticipantId || gift.participantBId || gift.matchedParticipantId || gift.recipientCampaignParticipantId);
  if (!participantAId || !participantBId) return {created: false, reason: "missing_participants"};
  const [aSnap, bSnap] = await Promise.all([
    db.collection("giftCampaignParticipants").doc(participantAId).get(),
    db.collection("giftCampaignParticipants").doc(participantBId).get(),
  ]);
  if (!aSnap.exists || !bSnap.exists) return {created: false, reason: "participant_not_found"};
  const participantA = {id: aSnap.id, ...(aSnap.data() || {})};
  const participantB = {id: bSnap.id, ...(bSnap.data() || {})};
  const decision = campaignRevealMatchDecision({gift: nextGift, participantA, participantB});
  if (!decision.create) {
    await giftRef.set({
      storyViewedBy: [...viewedBy],
      giftStoryViewedBy: [...viewedBy],
      visibleMatchStatus: decision.reason,
      giftStoryUpdatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return {created: false, reason: decision.reason};
  }
  const matchId = text(gift.visibleMatchId || gift.matchId) || `${participantAId}_${participantBId}_${giftId}`;
  const now = FieldValue.serverTimestamp();
  const record = buildRevealedCampaignMatchRecord({
    matchId,
    giftStoryId: giftId,
    gift: nextGift,
    participantA,
    participantB,
    now,
  });
  const batch = db.batch();
  const matchRef = db.collection("matches").doc(matchId);
  batch.set(matchRef, record, {merge: true});
  for (const participant of [participantA, participantB]) {
    const userId = text(participant.userId || participant.uid);
    if (!userId) continue;
    batch.set(db.collection("users").doc(userId).collection("matches").doc(matchId), {
      matchId,
      campaignId: record.campaignId,
      giftStoryId: record.giftStoryId,
      status: "revealed",
      source: "gift_campaign",
      createdAt: now,
      revealConfirmedAt: now,
    }, {merge: true});
  }
  batch.set(giftRef, {
    storyViewedBy: [...viewedBy],
    giftStoryViewedBy: [...viewedBy],
    visibleMatchId: matchId,
    visibleMatchStatus: "revealed",
    visibleMatchRevealedAt: now,
    giftStoryUpdatedAt: now,
  }, {merge: true});
  batch.set(aSnap.ref, {visibleMatchId: matchId, visibleMatchStatus: "revealed", updatedAt: now}, {merge: true});
  batch.set(bSnap.ref, {visibleMatchId: matchId, visibleMatchStatus: "revealed", updatedAt: now}, {merge: true});
  await batch.commit();
  return {created: true, matchId};
}

async function findGift(db, delivery) {
  const directId = text(delivery.giftOrderId || delivery.giftRequestId);
  if (directId) {
    const direct = await db.collection("giftRequests").doc(directId).get();
    if (direct.exists) return direct;
  }
  const deliveryId = text(delivery.deliveryId || delivery.requestId || delivery.id);
  if (!deliveryId) return null;
  const query = await db.collection("giftRequests").where("deliveryId", "==", deliveryId).limit(1).get();
  return query.empty ? null : query.docs[0];
}

async function queueStoryEmail(db, {giftId, role, email, token, retryId = "", userId = "", phone = ""}) {
  if (!email || !email.includes("@")) return false;
  const sender = role === "sender";
  const suffix = retryId ? `_${retryId}` : "";
  const ref = db.collection("emailQueue").doc(`gift_story_${giftId}_${role}${suffix}`);
  const secureStoryUrl = storyLink(token);
  await ref.set({
    to: email,
    subject: sender ? "Your Circum Gift Story is ready" : "You have received a Circum Gift Story",
    body: sender ?
      `Hello,\n\nYour Circum Gift Story is ready.\n\nWatch your story:\n${secureStoryUrl}\n\nThis secure private link expires according to Gift Story policy.\n\nThoughtful gifting, delivered by Circum.\n\n— Circum` :
      `Hello,\n\nYour Circum Gift Story is ready.\n\nView your secure story here:\n${secureStoryUrl}\n\nThis private link has been created just for you and expires according to Gift Story policy.\n\n— Circum`,
    type: "gift_story_ready",
    recipientRole: role,
    giftRequestId: giftId,
    status: "queued",
    attempts: FieldValue.increment(1),
    updatedAt: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  await writeStoryNotification(db, {
    notificationId: storyNotificationId(giftId, `email_${role}`, retryId),
    giftStoryId: giftId,
    userId: text(userId),
    email,
    phone: text(phone),
    channel: "email",
    status: "queued",
    priority: 1,
    secureStoryUrl,
  });
  return true;
}

async function queueRecipientLinkNotification(db, {giftId, gift, token, retryId = ""}) {
  const contact = text(gift.recipientPhone || gift.recipientContactPhone || gift.recipientContact);
  const url = recipientStoryLink(token);
  const suffix = retryId ? `_${retryId}` : "";
  const writes = [];
  if (/^\+?[0-9 ]{8,}$/.test(contact)) {
    writes.push(db.collection("whatsappQueue").doc(`gift_story_${giftId}_recipient${suffix}`).set({
      to: contact,
      body: `🎁 Your Circum Gift Story is ready.\n\nView your secure story here:\n\n${url}\n\nThis private link has been created just for you.`,
      type: "gift_story_ready",
      giftRequestId: giftId,
      status: "queued",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true}));
    writes.push(writeStoryNotification(db, {
      notificationId: storyNotificationId(giftId, "whatsapp_recipient", retryId),
      giftStoryId: giftId,
      userId: text(gift.recipientUserId),
      phone: contact,
      channel: "whatsapp",
      status: "queued",
      priority: 2,
      secureStoryUrl: url,
    }));
  }
  await Promise.all(writes);
  return writes.length > 0;
}

function submitThankYouUrl() {
  return "https://us-central1-circum-2797c.cloudfunctions.net/submitGiftStoryThankYou";
}

function storyNotificationId(giftId, channel, retryId = "") {
  return `gift_story_${giftId}_${channel}${retryId ? `_${retryId}` : ""}`;
}

function storyNotificationRecord({
  notificationId,
  giftStoryId,
  userId = "",
  email = "",
  phone = "",
  channel,
  status = "queued",
  retryCount = 0,
  failedReason = "",
  priority = 1,
  secureStoryUrl = "",
  createdAt = null,
}) {
  return {
    notificationId,
    giftStoryId,
    userId,
    email,
    phone,
    channel,
    status,
    priority,
    retryCount,
    sentAt: null,
    deliveredAt: null,
    failedReason,
    secureStoryUrl,
    createdAt,
  };
}

async function writeStoryNotification(db, data) {
  const notification = storyNotificationRecord({
    ...data,
    createdAt: FieldValue.serverTimestamp(),
  });
  await db.collection("storyNotifications").doc(notification.notificationId).set(notification, {merge: true});
  return notification.notificationId;
}

async function unlockGiftStory(db, giftSnap, deliveryId, {forceNewToken = false, retryEmails = false} = {}) {
  const giftId = giftSnap.id;
  const gift = giftSnap.data() || {};
  const existingToken = text(gift.giftStoryAccessToken);
  const token = !forceNewToken && existingToken ? existingToken : crypto.randomBytes(32).toString("base64url");
  const existingRecipientToken = text(gift.recipientStoryToken);
  const recipientToken = !forceNewToken && existingRecipientToken ? existingRecipientToken : crypto.randomBytes(32).toString("base64url");
  const hash = tokenHash(token);
  const recipientHash = tokenHash(recipientToken);
  const expiresAt = Timestamp.fromMillis(Date.now() + STORY_RETENTION_HOURS * 60 * 60 * 1000);
  const tokenRef = db.collection("giftStoryAccessTokens").doc(hash);
  const recipientTokenRef = db.collection("giftStoryAccessTokens").doc(recipientHash);
  const giftRef = giftSnap.ref;
  const slides = buildGiftStorySlides(gift);
  const skin = cleanSkin(gift.giftStorySkin);
  await db.runTransaction(async (transaction) => {
    transaction.set(tokenRef, {
      giftRequestId: giftId,
      deliveryId,
      tokenHash: hash,
      role: "sender",
      status: "active",
      privacy: gift.giftStorySharePrivacy || "private",
      expiresAt,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      views: gift.giftStoryViews || 0,
      shares: gift.giftStoryShares || 0,
      downloads: gift.giftStoryDownloads || 0,
      videoPlays: gift.giftStoryVideoPlays || 0,
      completedViews: gift.giftStoryCompletedViews || 0,
    }, {merge: true});
    transaction.set(recipientTokenRef, {
      giftRequestId: giftId,
      deliveryId,
      tokenHash: recipientHash,
      role: "recipient",
      status: "active",
      privacy: "recipient_private",
      expiresAt,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      views: 0,
    }, {merge: true});
    transaction.set(giftRef, {
      status: "delivered",
      giftStatus: "delivered",
      deliveryId,
      giftStoryEnabled: true,
      giftStoryUnlocked: true,
      giftStoryStatus: "unlocked",
      storyStatus: "unlocked",
      giftStorySkin: skin,
      giftStorySlides: slides,
      giftStoryStoragePaths: giftStoryStoragePaths(giftId),
      giftStoryAccessToken: token,
      giftStoryAccessTokenHash: hash,
      giftStoryAccessExpiresAt: expiresAt,
      recipientStoryToken: recipientToken,
      recipientStoryTokenHash: recipientHash,
      recipientStoryUrl: recipientStoryLink(recipientToken),
      giftStoryVideoStatus: gift.giftStoryRenderedVideoPath ? "ready" : "processing",
      giftStoryMusicVideoStatus: gift.giftStoryMusicVideoStatus || "not_requested",
      giftStoryAutomationStatus: "ready",
      giftStoryAutomationError: FieldValue.delete(),
      giftStoryAvailableAt: FieldValue.serverTimestamp(),
      giftStoryUpdatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  });
  const senderEmail = normalizeEmail(gift.senderEmail);
  const recipientEmail = normalizeEmail(gift.recipientEmail || gift.recipientContact);
  const recipientPhone = text(gift.recipientPhone || gift.recipientContactPhone || gift.recipientContact);
  const retryId = retryEmails ? `${Date.now()}` : "";
  const emailResults = await Promise.allSettled([
    queueStoryEmail(db, {giftId, role: "sender", email: senderEmail, token, retryId, userId: text(gift.senderId || gift.userId)}),
    queueStoryEmail(db, {giftId, role: "recipient", email: recipientEmail, token: recipientToken, retryId, userId: text(gift.recipientUserId), phone: recipientPhone}),
    queueRecipientLinkNotification(db, {giftId, gift, token: recipientToken, retryId}),
  ]);
  const failures = emailResults.filter((result) => result.status === "rejected");
  if (failures.length) {
    await giftRef.set({
      giftStoryEmailStatus: "retry_required",
      giftStoryEmailError: failures.map((result) => `${result.reason}`).join(" | ").slice(0, 1000),
      giftStoryUpdatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  } else {
    await giftRef.set({
      giftStoryEmailStatus: "queued",
      giftStoryEmailError: FieldValue.delete(),
      giftStoryUpdatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  return {giftId, token, recipientToken, expiresAt};
}

async function markAutomationFailure(db, deliveryId, giftId, error) {
  const message = `${error && error.message ? error.message : error}`.slice(0, 1200);
  console.error("Gift Story automation failed", {deliveryId, giftId, message});
  const batch = db.batch();
  batch.set(db.collection("deliveryRequests").doc(deliveryId), {
    giftStoryAutomationStatus: "retry_required",
    giftStoryAutomationError: message,
    giftStoryAutomationUpdatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  if (giftId) {
    batch.set(db.collection("giftRequests").doc(giftId), {
      giftStoryAutomationStatus: "retry_required",
      giftStoryAutomationError: message,
      giftStoryUpdatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  await batch.commit();
}

exports.onGiftDeliveryCompleted = functions.firestore.document("deliveryRequests/{deliveryId}").onUpdate(async (change, context) => {
  const before = change.before.data() || {};
  const after = change.after.data() || {};
  if (!isGiftDelivery(after) || isComplete(before.status) || !isComplete(after.status)) return null;
  const db = getFirestore();
  let giftSnap = null;
  try {
    giftSnap = await findGift(db, {...after, id: context.params.deliveryId});
    if (!giftSnap) throw new Error("Linked gift request was not found.");
    await unlockGiftStory(db, giftSnap, context.params.deliveryId);
    await change.after.ref.set({
      giftStoryAutomationStatus: "ready",
      giftStoryAutomationUpdatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  } catch (error) {
    await markAutomationFailure(db, context.params.deliveryId, giftSnap && giftSnap.id, error);
  }
  return null;
});

async function tokenRecord(db, token) {
  const clean = text(token);
  if (!clean) return null;
  const snap = await db.collection("giftStoryAccessTokens").doc(tokenHash(clean)).get();
  if (!snap.exists) return null;
  const data = snap.data() || {};
  const expiry = data.expiresAt && data.expiresAt.toMillis ? data.expiresAt.toMillis() : 0;
  if (data.status !== "active" || !expiry || expiry <= Date.now()) return null;
  return {snap, data};
}

exports.resolveGiftStoryAccess = functions.https.onCall(async (data, context) => {
  const db = getFirestore();
  const record = await tokenRecord(db, data && data.token);
  if (!record) throw new functions.https.HttpsError("permission-denied", "This Gift Story link is invalid or expired.");
  const giftSnap = await db.collection("giftRequests").doc(record.data.giftRequestId).get();
  if (!giftSnap.exists) throw new functions.https.HttpsError("not-found", "Gift Story not found.");
  const gift = giftSnap.data() || {};
  if (!isComplete(gift.giftStatus || gift.status) || gift.giftStoryEnabled === false || gift.giftStoryApproved === false) {
    throw new functions.https.HttpsError("failed-precondition", "This Gift Story is not available yet.");
  }
  if (text(gift.giftStoryStatus) === "locked" || text(gift.giftStoryAccessStatus) === "revoked") {
    throw new functions.https.HttpsError("failed-precondition", "This Gift Story is currently locked.");
  }
  const viewerUserId = context.auth && context.auth.uid ? context.auth.uid : text(data && data.viewerUserId);
  await record.snap.ref.set({views: FieldValue.increment(1), lastViewedAt: FieldValue.serverTimestamp()}, {merge: true});
  const storyViewPatch = {
    giftStoryViews: FieldValue.increment(1),
    giftStoryUpdatedAt: FieldValue.serverTimestamp(),
  };
  if (viewerUserId) {
    storyViewPatch.storyViewedBy = FieldValue.arrayUnion(viewerUserId);
    storyViewPatch.giftStoryViewedBy = FieldValue.arrayUnion(viewerUserId);
  }
  await giftSnap.ref.set(storyViewPatch, {merge: true});
  await maybeCreateRevealedCampaignMatch(db, giftSnap.ref, giftSnap.id, gift, viewerUserId);
  return {story: safeStory(giftSnap.id, gift), expiresAt: record.data.expiresAt.toMillis()};
});

exports.recordGiftStoryEvent = functions.https.onCall(async (data, context) => {
  const db = getFirestore();
  const record = await tokenRecord(db, data && data.token);
  if (!record) throw new functions.https.HttpsError("permission-denied", "Gift Story access expired.");
  const event = text(data.event);
  const fields = {
    view: "views",
    play: "videoPlays",
    complete: "completedViews",
    download: "downloads",
    share: "shares",
  };
  const field = fields[event];
  if (!field) throw new functions.https.HttpsError("invalid-argument", "Unknown Gift Story event.");
  const viewerUserId = context.auth && context.auth.uid ? context.auth.uid : text(data && data.viewerUserId);
  const giftRef = db.collection("giftRequests").doc(record.data.giftRequestId);
  const giftPatch = {
    [`giftStory${field[0].toUpperCase()}${field.slice(1)}`]: FieldValue.increment(1),
    giftStoryUpdatedAt: FieldValue.serverTimestamp(),
  };
  if (event === "view" && viewerUserId) {
    giftPatch.storyViewedBy = FieldValue.arrayUnion(viewerUserId);
    giftPatch.giftStoryViewedBy = FieldValue.arrayUnion(viewerUserId);
  }
  await Promise.all([
    record.snap.ref.set({[field]: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp()}, {merge: true}),
    giftRef.set(giftPatch, {merge: true}),
  ]);
  if (event === "view" || event === "complete") {
    const giftSnap = await giftRef.get();
    if (giftSnap.exists) {
      await maybeCreateRevealedCampaignMatch(db, giftRef, giftSnap.id, giftSnap.data() || {}, viewerUserId);
    }
  }
  return {ok: true};
});

exports.updateGiftStoryPrivacy = functions.https.onCall(async (data, context) => {
  const db = getFirestore();
  const giftId = text(data.giftRequestId);
  const privacy = text(data.privacy).toLowerCase();
  if (!["private", "unlisted", "public"].includes(privacy)) throw new functions.https.HttpsError("invalid-argument", "Invalid Gift Story privacy.");
  const giftRef = db.collection("giftRequests").doc(giftId);
  const giftSnap = await giftRef.get();
  if (!giftSnap.exists) throw new functions.https.HttpsError("not-found", "Gift Story not found.");
  const gift = {...(giftSnap.data() || {}), id: giftId};
  if (!await participantAuthorized(context, gift, text(data.token))) throw new functions.https.HttpsError("permission-denied", "Gift Story access required.");
  await giftRef.set({giftStorySharePrivacy: privacy, giftStoryShareEnabled: privacy !== "private", giftStoryUpdatedAt: FieldValue.serverTimestamp()}, {merge: true});
  const hash = text(gift.giftStoryAccessTokenHash);
  if (hash) await db.collection("giftStoryAccessTokens").doc(hash).set({privacy, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  return {ok: true, privacy};
});

async function adminAuthorized(context) {
  if (!context.auth) return false;
  const roles = Array.isArray(context.auth.token.roles) ? context.auth.token.roles : [];
  if (roles.some((role) => ["admin", "super_admin", "gifts_admin", "operations_admin"].includes(role))) return true;
  const snap = await getFirestore().collection("adminUsers").doc(context.auth.uid).get();
  const role = snap.exists ? text(snap.data().role) : "";
  return ["admin", "super_admin", "gifts_admin", "operations_admin"].includes(role);
}

async function participantAuthorized(context, gift, suppliedToken) {
  if (await adminAuthorized(context)) return true;
  if (context.auth) {
    const uid = context.auth.uid;
    const email = normalizeEmail(context.auth.token.email);
    if (uid && [gift.senderId, gift.userId, gift.customerId].includes(uid)) return true;
    if (email && [normalizeEmail(gift.senderEmail), normalizeEmail(gift.recipientEmail || gift.recipientContact)].includes(email)) return true;
  }
  if (suppliedToken) {
    const record = await tokenRecord(getFirestore(), suppliedToken);
    return Boolean(record && record.data.giftRequestId === gift.id);
  }
  return false;
}

exports.createGiftStoryVideoUpload = functions.https.onCall(async (data, context) => {
  const db = getFirestore();
  const giftId = text(data.giftRequestId);
  const giftSnap = await db.collection("giftRequests").doc(giftId).get();
  if (!giftSnap.exists) throw new functions.https.HttpsError("not-found", "Gift Story not found.");
  const gift = {...(giftSnap.data() || {}), id: giftId};
  if (!isComplete(gift.giftStatus || gift.status)) throw new functions.https.HttpsError("failed-precondition", "Gift Story is not unlocked.");
  if (!await participantAuthorized(context, gift, text(data.token))) throw new functions.https.HttpsError("permission-denied", "Gift Story access required.");
  const extension = text(data.extension).toLowerCase() === "mp4" ? "mp4" : "webm";
  const mime = extension === "mp4" ? "video/mp4" : "video/webm";
  const nonce = crypto.randomBytes(12).toString("hex");
  const exportKind = text(data.version).toLowerCase() === "silent" ? "silent" : "sound";
  const storagePath = `gifts/${giftId}/story/exports/${exportKind}/${Date.now()}_${nonce}.${extension}`;
  const file = getStorage().bucket().file(storagePath);
  const [uploadUrl] = await file.getSignedUrl({
    version: "v4",
    action: "write",
    expires: Date.now() + 15 * 60 * 1000,
    contentType: mime,
  });
  return {uploadUrl, storagePath, mime};
});

exports.finalizeGiftStoryVideoUpload = functions.https.onCall(async (data, context) => {
  const db = getFirestore();
  const giftId = text(data.giftRequestId);
  const giftRef = db.collection("giftRequests").doc(giftId);
  const giftSnap = await giftRef.get();
  if (!giftSnap.exists) throw new functions.https.HttpsError("not-found", "Gift Story not found.");
  const gift = {...(giftSnap.data() || {}), id: giftId};
  if (!await participantAuthorized(context, gift, text(data.token))) throw new functions.https.HttpsError("permission-denied", "Gift Story access required.");
  const storagePath = text(data.storagePath);
  if (!storagePath.startsWith(`gifts/${giftId}/story/exports/silent/`) &&
      !storagePath.startsWith(`gifts/${giftId}/story/exports/sound/`)) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid story video path.");
  }
  const file = getStorage().bucket().file(storagePath);
  const [exists] = await file.exists();
  if (!exists) throw new functions.https.HttpsError("not-found", "Rendered video upload was not found.");
  const expiresAt = Timestamp.fromMillis(Date.now() + STORY_RETENTION_HOURS * 60 * 60 * 1000);
  const previousPath = text(gift.giftStoryRenderedVideoPath);
  if (previousPath && previousPath !== storagePath) await getStorage().bucket().file(previousPath).delete({ignoreNotFound: true}).catch(() => null);
  await giftRef.set({
    giftStoryRenderedVideoPath: storagePath,
    ...(storagePath.includes("/exports/silent/") ? {giftStorySilentVersionUrl: storagePath} : {giftStorySoundVersionUrl: storagePath}),
    giftStoryVideoMime: text(data.mime),
    giftStoryVideoStatus: "ready",
    giftStoryVideoRenderedAt: FieldValue.serverTimestamp(),
    giftStoryVideoExpiresAt: expiresAt,
    giftStoryUpdatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return {ok: true, expiresAt: expiresAt.toMillis()};
});

exports.getGiftStoryVideoDownload = functions.https.onCall(async (data, context) => {
  const db = getFirestore();
  const giftId = text(data.giftRequestId);
  const giftSnap = await db.collection("giftRequests").doc(giftId).get();
  if (!giftSnap.exists) throw new functions.https.HttpsError("not-found", "Gift Story not found.");
  const gift = {...(giftSnap.data() || {}), id: giftId};
  if (!await participantAuthorized(context, gift, text(data.token))) throw new functions.https.HttpsError("permission-denied", "Gift Story access required.");
  const storagePath = text(gift.giftStoryRenderedVideoPath);
  if (!storagePath || gift.giftStoryVideoStatus !== "ready") throw new functions.https.HttpsError("failed-precondition", "Gift Story video is still processing.");
  const expiry = gift.giftStoryVideoExpiresAt && gift.giftStoryVideoExpiresAt.toMillis ? gift.giftStoryVideoExpiresAt.toMillis() : 0;
  if (!expiry || expiry <= Date.now()) throw new functions.https.HttpsError("failed-precondition", "Gift Story video has expired.");
  const [downloadUrl] = await getStorage().bucket().file(storagePath).getSignedUrl({version: "v4", action: "read", expires: Math.min(expiry, Date.now() + 15 * 60 * 1000)});
  return {downloadUrl, mime: gift.giftStoryVideoMime || "video/webm", expiresAt: expiry};
});

exports.retryGiftStoryAutomation = functions.https.onCall(async (data, context) => {
  if (!await adminAuthorized(context)) throw new functions.https.HttpsError("permission-denied", "Admin access required.");
  const giftId = text(data.giftRequestId);
  const giftSnap = await getFirestore().collection("giftRequests").doc(giftId).get();
  if (!giftSnap.exists) throw new functions.https.HttpsError("not-found", "Gift request not found.");
  const gift = giftSnap.data() || {};
  if (!isComplete(gift.giftStatus || gift.status)) throw new functions.https.HttpsError("failed-precondition", "Gift must be delivered first.");
  const result = await unlockGiftStory(getFirestore(), giftSnap, text(gift.deliveryId), {
    forceNewToken: Boolean(data.regenerateToken),
    retryEmails: true,
  });
  return {ok: true, expiresAt: result.expiresAt.toMillis()};
});

exports.manageGiftStoryAccess = functions.https.onCall(async (data, context) => {
  if (!await adminAuthorized(context)) throw new functions.https.HttpsError("permission-denied", "Admin access required.");
  const db = getFirestore();
  const giftId = text(data.giftRequestId);
  const action = text(data.action);
  const giftRef = db.collection("giftRequests").doc(giftId);
  const giftSnap = await giftRef.get();
  if (!giftSnap.exists) throw new functions.https.HttpsError("not-found", "Gift request not found.");
  const gift = giftSnap.data() || {};
  const hash = text(gift.giftStoryAccessTokenHash);
  if (action === "revoke") {
    if (hash) await db.collection("giftStoryAccessTokens").doc(hash).set({status: "revoked", revokedAt: FieldValue.serverTimestamp()}, {merge: true});
    await giftRef.set({giftStoryShareEnabled: false, giftStoryAccessStatus: "revoked", giftStoryUpdatedAt: FieldValue.serverTimestamp()}, {merge: true});
  } else if (action === "extend") {
    const expiresAt = Timestamp.fromMillis(Date.now() + STORY_RETENTION_HOURS * 60 * 60 * 1000);
    if (hash) await db.collection("giftStoryAccessTokens").doc(hash).set({expiresAt, status: "active", updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    await giftRef.set({giftStoryAccessExpiresAt: expiresAt, giftStoryVideoExpiresAt: expiresAt, giftStoryUpdatedAt: FieldValue.serverTimestamp()}, {merge: true});
  } else if (action === "delete_assets") {
    const path = text(gift.giftStoryRenderedVideoPath);
    if (path) await getStorage().bucket().file(path).delete({ignoreNotFound: true});
    await giftRef.set({giftStoryRenderedVideoPath: FieldValue.delete(), giftStoryVideoStatus: "deleted", giftStoryUpdatedAt: FieldValue.serverTimestamp()}, {merge: true});
  } else {
    throw new functions.https.HttpsError("invalid-argument", "Unknown Gift Story action.");
  }
  return {ok: true};
});

exports.giftStoryLanding = functions.https.onRequest(async (req, res) => {
  res.set("X-Robots-Tag", "noindex, nofollow, noarchive");
  res.set("Cache-Control", "no-store");
  const token = text(req.path.split("/").filter(Boolean).pop() || req.query.token);
  const record = await tokenRecord(getFirestore(), token);
  if (!record) return res.status(410).send("<!doctype html><title>Gift Story expired</title><meta name=robots content=noindex><body style='background:#050816;color:white;font-family:Helvetica;padding:48px'><h1>This Gift Story link has expired.</h1></body>");
  const giftSnap = await getFirestore().collection("giftRequests").doc(record.data.giftRequestId).get();
  if (!giftSnap.exists) return res.status(404).send("Gift Story not found.");
  const gift = giftSnap.data() || {};
  if (text(gift.giftStoryStatus) === "locked" || text(gift.giftStoryAccessStatus) === "revoked") {
    return res.status(423).send("<!doctype html><title>Gift Story locked</title><meta name=robots content=noindex><body style='background:#090B1D;color:#F5F3ED;font-family:Helvetica;padding:48px'><h1>Gift Story locked</h1><p>This story is currently under review.</p></body>");
  }
  if (!isComplete(gift.giftStatus || gift.status) && gift.giftStoryAdminOverride !== true) {
    return res.status(423).send("<!doctype html><title>Gift Story locked</title><meta name=robots content=noindex><body style='background:#090B1D;color:#F5F3ED;font-family:Helvetica;padding:48px'><h1>Gift Story locked</h1><p>Your story will unlock after delivery is confirmed.</p></body>");
  }
  await maybeCreateRevealedCampaignMatch(getFirestore(), giftSnap.ref, giftSnap.id, gift, text(req.query.viewerUserId));
  return res.status(200).send(renderGiftStoryHtml({
    token,
    giftId: giftSnap.id,
    gift,
    role: record.data.role || "recipient",
  }));
});

exports.submitGiftStoryThankYou = functions.https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Headers", "content-type");
  if (req.method === "OPTIONS") return res.status(204).send("");
  if (req.method !== "POST") return res.status(405).json({ok: false});
  const token = text(req.body && req.body.token);
  const thankYouMessage = text(req.body && req.body.thankYouMessage).slice(0, 1200);
  if (!thankYouMessage) return res.status(400).json({ok: false, error: "missing_message"});
  const db = getFirestore();
  const record = await tokenRecord(db, token);
  if (!record) return res.status(403).json({ok: false, error: "invalid_token"});
  const giftRef = db.collection("giftRequests").doc(record.data.giftRequestId);
  const giftSnap = await giftRef.get();
  if (!giftSnap.exists) return res.status(404).json({ok: false, error: "not_found"});
  const gift = giftSnap.data() || {};
  if (text(gift.giftStoryStatus) === "locked" || text(gift.giftStoryAccessStatus) === "revoked") {
    return res.status(423).json({ok: false, error: "story_locked"});
  }
  if (!isComplete(gift.giftStatus || gift.status) && gift.giftStoryAdminOverride !== true) {
    return res.status(423).json({ok: false, error: "story_locked"});
  }
  await giftRef.set({
    thankYouMessage,
    thankYouMessageSource: "recipient_web",
    thankYouMessageCreatedAt: FieldValue.serverTimestamp(),
    giftStoryUpdatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return res.status(200).json({ok: true});
});

exports.onStoryNotificationWrite = functions.firestore.document("storyNotifications/{notificationId}").onUpdate(async (change) => {
  const before = change.before.data() || {};
  const after = change.after.data() || {};
  if (text(before.status) === text(after.status)) return null;
  if (text(after.channel) !== "email" || text(after.status) !== "failed") return null;
  const phone = text(after.phone);
  const secureStoryUrl = text(after.secureStoryUrl);
  const giftStoryId = text(after.giftStoryId);
  if (!phone || !secureStoryUrl || !giftStoryId) return null;
  const db = getFirestore();
  const fallbackId = storyNotificationId(giftStoryId, "whatsapp_fallback");
  await db.collection("storyNotifications").doc(fallbackId).set(storyNotificationRecord({
    notificationId: fallbackId,
    giftStoryId,
    userId: text(after.userId),
    phone,
    channel: "whatsapp",
    status: "queued",
    priority: 2,
    retryCount: Number(after.retryCount || 0),
    failedReason: "email_failed",
    secureStoryUrl,
    createdAt: FieldValue.serverTimestamp(),
  }), {merge: true});
  await db.collection("whatsappQueue").doc(fallbackId).set({
    to: phone,
    body: `🎁 Your Circum Gift Story is ready.\n\nView your secure story here:\n\n${secureStoryUrl}\n\nThis private link has been created just for you.`,
    type: "gift_story_ready",
    giftRequestId: giftStoryId,
    status: "queued",
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return null;
});

exports.cleanupExpiredGiftStories = functions.pubsub.schedule("every 60 minutes").onRun(async () => {
  const db = getFirestore();
  const expired = await db.collection("giftStoryAccessTokens").where("expiresAt", "<=", Timestamp.now()).limit(200).get();
  for (const tokenDoc of expired.docs) {
    const data = tokenDoc.data() || {};
    const giftRef = db.collection("giftRequests").doc(data.giftRequestId);
    const giftSnap = await giftRef.get();
    if (giftSnap.exists) {
      const gift = giftSnap.data() || {};
      const path = text(gift.giftStoryRenderedVideoPath);
      if (path) await getStorage().bucket().file(path).delete({ignoreNotFound: true}).catch((error) => console.error("Gift Story asset cleanup failed", error));
      await giftRef.set({
        giftStoryRenderedVideoPath: FieldValue.delete(),
        giftStoryAccessToken: FieldValue.delete(),
        giftStoryAccessTokenHash: FieldValue.delete(),
        giftStoryAccessStatus: "expired",
        giftStoryVideoStatus: "expired",
        giftStoryUpdatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    await tokenDoc.ref.delete();
  }
  return null;
});

module.exports.isGiftDelivery = isGiftDelivery;
module.exports.isComplete = isComplete;
module.exports.tokenHash = tokenHash;
module.exports.safeStory = safeStory;
module.exports.buildGiftStorySlides = buildGiftStorySlides;
module.exports.giftStoryStoragePaths = giftStoryStoragePaths;
module.exports.cleanSkin = cleanSkin;
module.exports.renderGiftStoryHtml = renderGiftStoryHtml;
module.exports.storyNotificationRecord = storyNotificationRecord;
module.exports.hasActiveGiftDispute = hasActiveGiftDispute;
module.exports.revealPolicyAllowsMutualReveal = revealPolicyAllowsMutualReveal;
module.exports.campaignRevealMatchDecision = campaignRevealMatchDecision;
module.exports.buildRevealedCampaignMatchRecord = buildRevealedCampaignMatchRecord;
