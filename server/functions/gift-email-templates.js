/* eslint-disable max-len, require-jsdoc */
"use strict";

const WORDMARK_URL = "https://circumuk.com/assets/assets/images/circum_wordmark.png";
const PRIVACY_URL = "https://circumuk.com/privacy_policy";
const TERMS_URL = "https://circumuk.com/terms";
const SUPPORT_URL = "mailto:info@circumuk.com";
const APP_STORE_URL = "https://apps.apple.com/gb/app/circum/id6463644284";
const PLAY_STORE_URL = "https://play.google.com/store/apps/details?id=com.circum.app";
const APP_STORE_BADGE_URL = "https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg";
const PLAY_STORE_BADGE_URL = "https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png";
const X_URL = "https://x.com/circumuk";
const INSTAGRAM_URL = "https://www.instagram.com/circumuk/";
const TIKTOK_URL = "https://www.tiktok.com/@circumuk";
const STORY_URL = /^https:\/\/circumuk\.com\/story\/[A-Za-z0-9_-]+$/;
const text = (value) => `${value || ""}`.trim();
const escapeHtml = (value) => text(value).replace(/[&<>"']/g, (character) => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;"}[character]));
const safeName = (value) => text(value).replace(/[<>_]/g, " ").replace(/\s+/g, " ").slice(0, 80) || "your recipient";

function build({templateId, subject, preheader, heading, paragraphs, label, value, ctaLabel = "", ctaUrl = "", message}) {
  if (ctaLabel && !STORY_URL.test(text(ctaUrl))) throw new Error("A secure Gift Story link is required.");
  const url = ctaLabel ? text(ctaUrl) : "";
  const footer = "Need help with the delivery record? Contact us at info@circumuk.com.";
  const body = [heading, ...paragraphs, `${label}: ${value}`, url ? `${ctaLabel}: ${url}` : "", footer,
    `Download Circum on the App Store: ${APP_STORE_URL}`, `Get Circum on Google Play: ${PLAY_STORE_URL}`,
    `Follow Circum on X: ${X_URL}`, `Instagram: ${INSTAGRAM_URL}`, `TikTok: ${TIKTOK_URL}`,
    `Privacy Policy: ${PRIVACY_URL}`, `Terms: ${TERMS_URL}`].filter(Boolean).join("\n\n");
  const bodyHtml = paragraphs.map((paragraph) => `<p style="margin:0 0 18px">${escapeHtml(paragraph)}</p>`).join("");
  const button = url ? `<p style="margin:25px 0"><a href="${escapeHtml(url)}" style="display:inline-block;padding:14px 23px;border-radius:100px;background:#5268c3;color:#fff;text-decoration:none;font-size:14px;font-weight:bold">${escapeHtml(ctaLabel)}</a></p>` : "";
  const storeLinksHtml = `<table role="presentation" align="center" cellpadding="0" cellspacing="0" border="0" style="margin:12px auto 16px"><tr><td style="padding:0 6px"><a href="${APP_STORE_URL}" style="display:inline-block;color:#5359a1;text-decoration:none"><img src="${APP_STORE_BADGE_URL}" alt="Download Circum on the App Store" width="124" height="42" style="display:block;width:124px;height:42px;border:0"></a></td><td style="padding:0 6px"><a href="${PLAY_STORE_URL}" style="display:inline-block;color:#5359a1;text-decoration:none"><img src="${PLAY_STORE_BADGE_URL}" alt="Get Circum on Google Play" width="174" height="52" style="display:block;width:174px;height:52px;border:0"></a></td></tr></table><p style="margin:0 0 10px"><a href="${APP_STORE_URL}" style="color:#5359a1">App Store</a> &nbsp;·&nbsp; <a href="${PLAY_STORE_URL}" style="color:#5359a1">Google Play</a></p>`;
  const socialLinksHtml = `<p style="margin:0 0 10px">Follow @circumuk: <a href="${X_URL}" style="color:#5359a1">X</a> &nbsp;·&nbsp; <a href="${INSTAGRAM_URL}" style="color:#5359a1">Instagram</a> &nbsp;·&nbsp; <a href="${TIKTOK_URL}" style="color:#5359a1">TikTok</a></p>`;
  const html = `<!doctype html><html lang="en"><body style="margin:0;background:#f5f7fc;color:#1b2139;font-family:Arial,Helvetica,sans-serif;line-height:1.55"><span style="display:none;font-size:1px;max-height:0;opacity:0;overflow:hidden">${escapeHtml(preheader)}</span><table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f5f7fc"><tr><td align="center" style="padding:30px 12px"><table role="presentation" width="620" cellpadding="0" cellspacing="0" border="0" style="width:100%;max-width:620px;background:#fff;border-radius:24px;overflow:hidden"><tr><td style="padding:32px 38px 38px;background:#637bd6;background-image:linear-gradient(125deg,#a9dcef 0%,#6684d7 38%,#957ddb 77%,#91cfc7 100%);color:#fff"><span style="display:inline-block;padding:8px 12px;border-radius:10px;background:#fff"><img src="${WORDMARK_URL}" alt="CIRCUM" width="160" style="display:block;width:160px;height:auto;border:0"></span><p style="margin:7px 0 29px;font-size:10px;font-weight:bold;letter-spacing:3px">GIFTS</p><h1 style="margin:0 0 10px;font-size:38px;line-height:1.1;letter-spacing:-1px;color:#fff">${escapeHtml(heading)}</h1><p style="margin:0;color:#f7f8ff">${escapeHtml(preheader)}</p></td></tr><tr><td style="padding:34px 38px 27px;font-size:16px">${bodyHtml}<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:22px 0;border:1px solid #e2e8f3;border-radius:18px;background:#f5f4ff"><tr><td style="padding:19px 22px"><p style="margin:0 0 5px;color:#7069b4;font-size:11px;font-weight:bold;letter-spacing:1px;text-transform:uppercase">${escapeHtml(label)}</p><p style="margin:0;font-size:22px;font-weight:bold">${escapeHtml(value)}</p></td></tr></table>${button}<p style="margin:0;color:#68708a;font-size:13px">${escapeHtml(footer)}</p></td></tr><tr><td align="center" style="padding:22px 20px 27px;border-top:1px solid #e8ebf4;color:#69708a;font-size:12px"><p style="margin:0 0 8px">CIRCUM Gifts</p>${storeLinksHtml}${socialLinksHtml}<a href="${PRIVACY_URL}" style="color:#5359a1">Privacy Policy</a> &nbsp;·&nbsp; <a href="${TERMS_URL}" style="color:#5359a1">Terms</a> &nbsp;·&nbsp; <a href="${SUPPORT_URL}" style="color:#5359a1">Contact us</a></td></tr></table></td></tr></table></body></html>`;
  return {templateId, subject, preheader, heading, text: body, html, footer, ctaLabel, ctaUrl: url,
    senderCategory: "gifts", providerTags: [{name: "product", value: "gifts"}, {name: "message", value: message}]};
}

function paymentConfirmed({recipientName = "", rothAmount = 0, split = false} = {}) {
  const recipient = safeName(recipientName);
  const amount = Number(rothAmount);
  if (!Number.isFinite(amount) || amount <= 0) throw new Error("A finalized Roth amount is required.");
  const roth = `${Number(amount.toFixed(2))} Roth`;
  return build({templateId: split ? "gift-payment-split" : "gift-payment-roth", subject: "Your CIRCUM Gift is confirmed",
    preheader: `Your Gift to ${recipient} is moving to the next stage.`, heading: "Your Gift is confirmed",
    paragraphs: split ? [`Your Gift to ${recipient} is confirmed and is moving to the next stage.`,
      "Your card payment receipt is provided separately for the card portion. We'll let you know when the Gift is delivered."] :
      [`We've received your payment of ${roth} for your Gift to ${recipient}. Your Gift is confirmed and is moving to the next stage.`,
        "We'll let you know when the Gift is delivered."],
    label: split ? "Gift status" : "Payment received", value: split ? "Confirmed" : roth, message: "payment-confirmed"});
}

function delivered({recipientName = "", storyUrl = ""} = {}) {
  const recipient = safeName(recipientName);
  return build({templateId: "gift-delivered", subject: "Your CIRCUM Gift has been delivered",
    preheader: "Your Gift Story is ready to view.", heading: "Your Gift has been delivered",
    paragraphs: [`Your Gift to ${recipient} has been delivered. This confirms the gift delivery.`, "Your Gift Story is ready to view."],
    label: "Delivery", value: `Delivered to ${recipient}`, ctaLabel: "View the Gift Story", ctaUrl: storyUrl, message: "delivered"});
}

function story({role, storyUrl} = {}) {
  const sender = role === "sender";
  return build({templateId: sender ? "gift-story-sender" : "gift-story-recipient",
    subject: sender ? "Your CIRCUM Gift Story is ready" : "You have received a CIRCUM Gift Story",
    preheader: sender ? "Your private Gift Story is ready to view." : "A private Gift Story has been prepared for you.",
    heading: sender ? "Your Gift Story is ready" : "You have received a Gift Story",
    paragraphs: sender ? ["Your private CIRCUM Gift Story is ready to view.", "Your private link is personal to you and is available for a limited time."] :
      ["A private CIRCUM Gift Story has been prepared for you. Open your Story to experience the moment behind your Gift.",
        "You can open your personal Story link in your browser. Your link is available for a limited time."],
    label: sender ? "Your Story" : "A Gift Story for you", value: "Ready to view",
    ctaLabel: "View your Gift Story", ctaUrl: storyUrl, message: "story"});
}

module.exports = {paymentConfirmed, delivered, story};
