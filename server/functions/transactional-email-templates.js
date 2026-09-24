/* eslint-disable max-len, require-jsdoc */
"use strict";

const APP_URL = "https://circumuk.com";
const WELCOME_IMAGE_URL = "https://circumuk.com/assets/assets/images/circum-welcome.png";
const SUPPORT_TEXT = "Need help? Reply to this email or contact Circum support from your account.";
const FORBIDDEN_CUSTOMER_TOKENS = [
  "roth_movement_completed",
  "sender_",
  "rider_",
  "delivery_in_progress",
  "business_invoice_",
  "health_plus_",
  "gift_story_ready",
  "firestore",
  "eventarc",
  "notificationid",
  "sourcecollection",
  "sourcerequiredstatus",
];

const text = (value) => `${value || ""}`.trim();

function escapeHtml(value) {
  return text(value).replace(/[&<>"']/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "\"": "&quot;",
    "'": "&#39;",
  }[character]));
}

function safeName(value) {
  return text(value).replace(/[<>_]/g, " ").replace(/\s+/g, " ").slice(0, 80);
}

function firstName(value) {
  return safeName(value).split(" ")[0] || "there";
}

function safeReference(value) {
  return text(value).replace(/[^A-Za-z0-9 .#/-]/g, "").slice(0, 80);
}

function money(value) {
  const amount = Number(value);
  return Number.isFinite(amount) && amount >= 0 ? `£${amount.toFixed(2)}` : "";
}

function layout({preheader, heading, paragraphs, ctaLabel = "", ctaUrl = "", footer = SUPPORT_TEXT, imageUrl = ""}) {
  const safeUrl = /^https:\/\/circumuk\.com(?:[/?#].*)?$/.test(text(ctaUrl)) ? text(ctaUrl) : "";
  const safeImageUrl = /^https:\/\/circumuk\.com\/(?:assets\/)+[A-Za-z0-9._/-]+\.(?:png|jpg|jpeg|webp)$/.test(text(imageUrl)) ? text(imageUrl) : "";
  const image = safeImageUrl ? `<p><img src="${escapeHtml(safeImageUrl)}" alt="Welcome to Circum" style="display:block;width:100%;max-width:560px;height:auto;border:0"></p>` : "";
  const htmlParagraphs = paragraphs.map((paragraph) => `<p>${escapeHtml(paragraph)}</p>`).join("");
  const cta = safeUrl ? `<p><a href="${escapeHtml(safeUrl)}" style="display:inline-block;background:#5b21b6;color:#fff;padding:12px 18px;border-radius:6px;text-decoration:none">${escapeHtml(ctaLabel || "Open Circum")}</a></p>` : "";
  const textBody = [heading, ...paragraphs, safeUrl ? `${ctaLabel || "Open Circum"}: ${safeUrl}` : "", footer]
      .filter(Boolean).join("\n\n");
  const html = `<!doctype html><html><body style="font-family:Arial,sans-serif;color:#17151f;line-height:1.6"><span style="display:none;max-height:0;overflow:hidden;opacity:0">${escapeHtml(preheader)}</span>${image}<h1>${escapeHtml(heading)}</h1>${htmlParagraphs}${cta}<p style="color:#635f70">${escapeHtml(footer)}</p></body></html>`;
  return {preheader, heading, text: textBody, html, footer, ctaLabel: safeUrl ? ctaLabel || "Open Circum" : "", ctaUrl: safeUrl};
}

function result({templateId, subject, preheader, heading, paragraphs, ctaLabel, ctaUrl, footer, imageUrl, senderCategory, tags = []}) {
  const rendered = layout({preheader, heading, paragraphs, ctaLabel, ctaUrl, footer, imageUrl});
  const copy = {templateId, subject, senderCategory, providerTags: tags, ...rendered};
  assertCustomerFacingContent(copy);
  return copy;
}

function welcome({displayName = "", amount = 5, ctaUrl = APP_URL} = {}) {
  const name = safeName(displayName);
  return result({
    templateId: "sender-welcome",
    subject: "Welcome to Circum — £5 Roth has been added to your wallet",
    preheader: "Your Circum account is ready. Here’s a little something to help you get started.",
    heading: name ? `Welcome to Circum, ${firstName(name)}` : "Welcome to Circum",
    paragraphs: [
      "Thanks for joining us — your account is ready to use.",
      `To help you get started, we’ve added ${money(amount) || "£5"} Roth to your wallet. Roth is Circum credit that can be used toward eligible Circum services and deliveries, subject to our current service rules.`,
      "Whenever you’re ready, you can explore Circum and see what’s available.",
    ],
    ctaLabel: "Explore Circum",
    ctaUrl,
    footer: "Warmly,\n\nThe Circum team",
    imageUrl: WELCOME_IMAGE_URL,
    senderCategory: "info",
    tags: [{name: "product", value: "account"}, {name: "message", value: "welcome"}],
  });
}

function bookingConfirmed({reference = "", ctaUrl = APP_URL} = {}) {
  const ref = safeReference(reference);
  return result({
    templateId: "delivery-booking-confirmed",
    subject: "Your CIRCUM delivery booking is confirmed",
    preheader: "Your payment has been confirmed and your delivery is ready to follow.",
    heading: "Your delivery booking is confirmed",
    paragraphs: [
      "Your CIRCUM delivery booking is confirmed and your payment has been received.",
      "You can follow the delivery in Circum as it moves through each stage.",
      ref ? `Booking reference: ${ref}` : "",
    ].filter(Boolean),
    ctaLabel: "View delivery",
    ctaUrl,
    senderCategory: "info",
    tags: [{name: "product", value: "delivery"}, {name: "message", value: "booking-confirmed"}],
  });
}

function deliveryCompleted({reference = "", ctaUrl = APP_URL} = {}) {
  const ref = safeReference(reference);
  return result({
    templateId: "delivery-completed",
    subject: "Your CIRCUM delivery has arrived",
    preheader: "Your delivery has been completed.",
    heading: "Your delivery is complete",
    paragraphs: [
      "Your CIRCUM delivery has been completed. This message confirms the final handover.",
      ref ? `Booking reference: ${ref}` : "",
    ].filter(Boolean),
    ctaLabel: "View delivery",
    ctaUrl,
    senderCategory: "info",
    tags: [{name: "product", value: "delivery"}, {name: "message", value: "completed"}],
  });
}

function cancellationSettled({reference = "", ctaUrl = APP_URL} = {}) {
  const ref = safeReference(reference);
  return result({
    templateId: "delivery-cancellation-settled",
    subject: "Your CIRCUM delivery cancellation is complete",
    preheader: "Your cancellation and any applicable payment settlement have been completed.",
    heading: "Your delivery cancellation is complete",
    paragraphs: [
      "The cancellation for your CIRCUM delivery has been completed.",
      "Any applicable refund or fee settlement has been recorded against the booking.",
      ref ? `Booking reference: ${ref}` : "",
    ].filter(Boolean),
    ctaLabel: "View payment details",
    ctaUrl,
    senderCategory: "info",
    tags: [{name: "product", value: "delivery"}, {name: "message", value: "cancellation"}],
  });
}

function businessInvoicePaid({reference = "", ctaUrl = APP_URL} = {}) {
  const ref = safeReference(reference);
  return result({
    templateId: "business-invoice-paid",
    subject: "Your CIRCUM Business invoice is paid",
    preheader: "Your CIRCUM Business payment has been received and your invoice is settled.",
    heading: "Your CIRCUM Business invoice is paid",
    paragraphs: [
      "We have received payment for your CIRCUM Business invoice.",
      "Your account is up to date. Sign in to review the invoice and payment record.",
      ref ? `Invoice reference: ${ref}` : "",
    ].filter(Boolean),
    ctaLabel: "View invoice",
    ctaUrl,
    senderCategory: "business",
    tags: [{name: "product", value: "business"}, {name: "message", value: "invoice-paid"}],
  });
}

function rothActivity({displayName = "", movement = "updated", amount = null, reference = "", ctaUrl = APP_URL} = {}) {
  const amountText = money(amount);
  const descriptions = {
    credited: amountText ? `${amountText} Roth has been added to your wallet.` : "Roth has been added to your wallet.",
    debited: amountText ? `${amountText} Roth has been used from your wallet.` : "Roth has been used from your wallet.",
    refunded: amountText ? `${amountText} Roth has been returned to your wallet.` : "Roth has been returned to your wallet.",
    restored: amountText ? `${amountText} Roth has been restored to your wallet.` : "Roth has been restored to your wallet.",
    updated: "Your Roth wallet has been updated.",
  };
  const description = descriptions[movement] || descriptions.updated;
  return result({
    templateId: "roth-activity",
    subject: "Your CIRCUM Roth wallet has been updated",
    preheader: description,
    heading: displayName ? `Your Roth wallet, ${firstName(displayName)}` : "Your Roth wallet has been updated",
    paragraphs: [description, "Roth can be used toward eligible Circum services and deliveries under the current product rules.", reference ? `Reference: ${safeReference(reference)}` : ""].filter(Boolean),
    ctaLabel: "View Roth wallet",
    ctaUrl,
    senderCategory: "info",
    tags: [{name: "product", value: "roth"}, {name: "message", value: "wallet-update"}],
  });
}

function referralReward({ctaUrl = APP_URL} = {}) {
  return result({
    templateId: "referral-reward",
    subject: "Your CIRCUM referral reward is ready",
    preheader: "Your referral reward has been added to your Roth wallet.",
    heading: "Your referral reward is ready",
    paragraphs: ["Your referral reward has been added to your Roth wallet.", "You can use Roth toward eligible Circum services and deliveries under the current product rules."],
    ctaLabel: "View your wallet",
    ctaUrl,
    senderCategory: "info",
    tags: [{name: "product", value: "referrals"}, {name: "message", value: "reward"}],
  });
}

function riderDecision({decision, ctaUrl = APP_URL} = {}) {
  const copy = {
    approved: {
      subject: "Your CIRCUM Rider application has been approved",
      preheader: "Your Rider application has been approved. Review the next steps in the Rider app.",
      heading: "Your Rider application is approved",
      body: "Your Rider application has been approved. Open the Rider app to review the next steps before you begin.",
    },
    rejected: {
      subject: "An update about your CIRCUM Rider application",
      preheader: "There is an update about your Rider application.",
      heading: "An update about your Rider application",
      body: "There is an update about your Rider application. Open the Rider app to review the information available to you.",
    },
    more_information_requested: {
      subject: "A little more information is needed for your CIRCUM Rider application",
      preheader: "Please open the Rider app to see what is needed next.",
      heading: "A little more information is needed",
      body: "Please open the Rider app to see the next step for your application. We only ask for information needed to review your application.",
    },
  }[text(decision).toLowerCase()] || null;
  if (!copy) throw new Error("Unsupported Rider application decision.");
  return result({
    templateId: `rider-application-${text(decision).toLowerCase()}`,
    subject: copy.subject,
    preheader: copy.preheader,
    heading: copy.heading,
    paragraphs: [copy.body],
    ctaLabel: "Open Rider",
    ctaUrl,
    senderCategory: "info",
    tags: [{name: "product", value: "rider"}, {name: "message", value: "application-update"}],
  });
}

const HEALTH_COPY = Object.freeze({
  scheduled: ["Your Health+ collection is scheduled", "Your Health+ collection has been scheduled. We will keep you updated as it progresses."],
  assigned: ["A rider has been assigned to your Health+ collection", "A verified rider has been assigned to your Health+ collection."],
  en_route_pickup: ["Your Health+ rider is on the way", "Your rider is travelling to the collection point."],
  awaiting_pharmacy_collection: ["Your Health+ rider is ready at the collection point", "Your rider is ready to collect from the pharmacy."],
  collected: ["Your Health+ prescription has been collected", "Your prescription has been collected securely and is now moving through the next step."],
  out_for_delivery: ["Your Health+ delivery is on the way", "Your Health+ delivery is on its way to you."],
  delivered: ["Your Health+ delivery is complete", "Your Health+ delivery has been completed."],
  prescription_not_ready: ["Your Health+ collection needs an update", "The prescription was not ready when our rider arrived. Circum is coordinating the next step."],
  customer_unavailable: ["We need to rearrange your Health+ delivery", "We could not complete the delivery. Circum will help arrange the next step."],
  escalated: ["Your Health+ delivery needs our attention", "Your Health+ delivery has been referred to our team for review. We will update you when the next step is confirmed."],
  rescheduled: ["Your Health+ collection has been rescheduled", "Your Health+ collection has been rescheduled. We will keep you updated with the arranged time."],
  override_completed: ["Your Health+ delivery is complete", "Your Health+ delivery has been completed following a review."],
  reminder_24h: ["Your Health+ collection is tomorrow", "Your Health+ collection is scheduled for tomorrow. Please keep the arranged time available."],
  reminder_2h: ["Your Health+ collection is due soon", "Your Health+ collection is scheduled in approximately two hours."],
});

function healthUpdate({type, ctaUrl = APP_URL} = {}) {
  const copy = HEALTH_COPY[text(type).toLowerCase()];
  if (!copy) throw new Error("Unsupported Health+ notification.");
  return result({
    templateId: `health-update-${text(type).toLowerCase()}`,
    subject: copy[0],
    preheader: copy[1],
    heading: copy[0],
    paragraphs: [copy[1]],
    ctaLabel: "View Health+",
    ctaUrl,
    senderCategory: "health",
    tags: [{name: "product", value: "health-plus"}, {name: "message", value: "status-update"}],
  });
}

function giftDelivered({giftId = "", recipientName = "", deliveredAt = "", ctaUrl = "https://circumuk.com/?app=gifts"} = {}) {
  const recipient = safeName(recipientName) || "your recipient";
  const timing = text(deliveredAt) ? ` on ${text(deliveredAt)}` : "";
  return result({
    templateId: "gift-delivered",
    subject: "Your CIRCUM gift was delivered",
    preheader: "Your gift has reached its recipient.",
    heading: "Your CIRCUM gift was delivered",
    paragraphs: [`Your gift to ${recipient} was marked as delivered${timing}.`, giftId ? `Gift reference: ${safeReference(giftId)}` : "", "This is an essential service message about a gift you sent with Circum."].filter(Boolean),
    ctaLabel: "Open Circum Gifts",
    ctaUrl,
    senderCategory: "gifts",
    tags: [{name: "product", value: "gifts"}, {name: "message", value: "delivered"}],
  });
}

function giftStory({role, storyUrl} = {}) {
  const sender = role === "sender";
  const url = /^https:\/\/circumuk\.com(?:[/?#].*)?$/.test(text(storyUrl)) ? text(storyUrl) : "";
  if (!url) throw new Error("Gift Story link is required.");
  return result({
    templateId: sender ? "gift-story-sender" : "gift-story-recipient",
    subject: sender ? "Your CIRCUM Gift Story is ready" : "You have received a CIRCUM Gift Story",
    preheader: sender ? "Your private Gift Story is ready to view." : "A private Gift Story has been created for you.",
    heading: sender ? "Your Gift Story is ready" : "You have received a Gift Story",
    paragraphs: [sender ? "Your private CIRCUM Gift Story is ready to view." : "Someone has created a private CIRCUM Gift Story for you.", "This secure link is personal to you and expires according to Gift Story policy."],
    ctaLabel: "View Gift Story",
    ctaUrl: url,
    senderCategory: "gifts",
    tags: [{name: "product", value: "gifts"}, {name: "message", value: "story"}],
  });
}

function assertCustomerFacingContent(copy) {
  const fields = [copy.subject, copy.preheader, copy.heading, copy.text, copy.html, copy.ctaLabel, copy.footer].filter(Boolean).join(" ").toLowerCase();
  if (/[a-z][a-z0-9]*_[a-z0-9_]+/.test(fields)) throw new Error("customer_copy_contains_snake_case");
  for (const token of FORBIDDEN_CUSTOMER_TOKENS) {
    if (fields.includes(token)) throw new Error(`customer_copy_contains_internal_token:${token}`);
  }
  return true;
}

module.exports = {
  APP_URL,
  FORBIDDEN_CUSTOMER_TOKENS,
  assertCustomerFacingContent,
  bookingConfirmed,
  businessInvoicePaid,
  cancellationSettled,
  deliveryCompleted,
  giftDelivered,
  giftStory,
  healthUpdate,
  referralReward,
  riderDecision,
  rothActivity,
  welcome,
};
