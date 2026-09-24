/* eslint-disable max-len, require-jsdoc */
"use strict";

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

function displayName(value) {
  const cleaned = text(value).replace(/[\r\n<>]/g, " ").replace(/\s+/g, " ").trim();
  return cleaned || "there";
}

function pounds(value, fallback = "") {
  const amount = Number(value);
  if (!Number.isFinite(amount) || amount === 0) return fallback;
  return `£${Math.abs(amount).toFixed(2).replace(/\.00$/, "")}`;
}

function ctaFor(value) {
  return text(value) || "Open CIRCUM";
}

function render({subject, preheader, heading, paragraphs, cta = "Open CIRCUM", footer = "This essential service email relates to activity on your CIRCUM account."}) {
  const body = paragraphs.filter(Boolean).map(text);
  const visibleCta = ctaFor(cta);
  const textBody = [
    heading,
    "",
    ...body,
    "",
    visibleCta,
    "",
    footer,
  ].join("\n");
  const htmlBody = `<!doctype html><html><body style="font-family:Arial,sans-serif;color:#17151f;line-height:1.6"><div style="display:none;max-height:0;overflow:hidden">${escapeHtml(preheader)}</div><h1>${escapeHtml(heading)}</h1>${body.map((paragraph) => `<p>${escapeHtml(paragraph)}</p>`).join("")}<p><a href="https://circumuk.com" style="color:#5b21b6">${escapeHtml(visibleCta)}</a></p><p style="color:#635f70">${escapeHtml(footer)}</p></body></html>`;
  return {subject, preheader, heading, body, cta: visibleCta, footer, text: textBody, html: htmlBody};
}

function renderTransactionalEmail(eventType, context = {}) {
  const name = displayName(context.displayName || context.firstName);
  const reference = text(context.reference);
  const amount = pounds(context.amount, "the amount");
  const direction = Number(context.amount) < 0 ? "debit" : "credit";
  const type = text(eventType).toLowerCase();

  if (type === "sender_welcome") {
    return render({
      subject: "Welcome to CIRCUM",
      preheader: "£5 Roth has been added to help you get started.",
      heading: `Welcome to CIRCUM${name === "there" ? "" : `, ${name}`}`,
      paragraphs: [
        "Your CIRCUM account is ready.",
        "We have added £5 Roth to your wallet to help you get started. Roth is CIRCUM's wallet balance for eligible CIRCUM services, and you can see it in the app.",
        "No action is needed right now. Open CIRCUM whenever you are ready to explore.",
      ],
    });
  }

  if (type === "roth_movement_completed") {
    const kind = context.refund === true ? "refund" : direction;
    return render({
      subject: "Your CIRCUM wallet has been updated",
      preheader: `A Roth ${kind} has been recorded in your wallet.`,
      heading: "Your CIRCUM wallet has been updated",
      paragraphs: [
        `A Roth ${kind} of ${amount} has been recorded in your wallet.`,
        "This is a confirmation of account activity. You can open CIRCUM to review your current Roth balance.",
      ],
    });
  }

  if (type === "delivery_booking_paid") {
    return render({
      subject: "Your CIRCUM delivery booking is confirmed",
      preheader: "Your paid delivery booking is now in our system.",
      heading: "Your delivery booking is confirmed",
      paragraphs: [
        "Your paid CIRCUM delivery booking has been confirmed.",
        "We will keep you updated as your delivery progresses.",
      ],
    });
  }

  if (type === "delivery_completed") {
    return render({
      subject: "Your CIRCUM delivery has been delivered",
      preheader: "Your delivery has reached its destination.",
      heading: "Your delivery has been delivered",
      paragraphs: [
        "Your CIRCUM delivery has been delivered.",
        "You can open CIRCUM to review the delivery details.",
      ],
    });
  }

  if (type === "delivery_cancellation_settled") {
    return render({
      subject: "Your CIRCUM delivery cancellation is confirmed",
      preheader: "Your delivery cancellation has been processed.",
      heading: "Your delivery cancellation is confirmed",
      paragraphs: [
        "The cancellation of your CIRCUM delivery has been processed.",
        "You can open CIRCUM to review the latest account details.",
      ],
    });
  }

  if (type === "business_invoice_paid") {
    return render({
      subject: "Your CIRCUM Business invoice is paid",
      preheader: "Your invoice payment has been received.",
      heading: "Your CIRCUM Business invoice is paid",
      paragraphs: [
        `Payment for your CIRCUM Business invoice${reference ? ` ${reference}` : ""} has been received.`,
        "Sign in to CIRCUM Business to review the invoice and your account.",
      ],
      cta: "Open CIRCUM Business",
    });
  }

  if (type === "referral_award_finalized") {
    return render({
      subject: "Your CIRCUM referral reward is ready",
      preheader: "Your referral reward has been added to Roth.",
      heading: "Your referral reward is ready",
      paragraphs: [
        "Your CIRCUM referral reward has been added to Roth.",
        "Open CIRCUM to review your wallet and see what you can use it for.",
      ],
    });
  }

  if (type === "rider_application_decision") {
    const decision = text(context.decision).toLowerCase();
    const copy = decision === "approved" ? {
      subject: "Your CIRCUM Rider application was approved",
      preheader: "Your Rider application has been approved.",
      heading: "Your Rider application was approved",
      paragraphs: ["Your CIRCUM Rider application has been approved.", "Open the Rider app to review the next steps."],
    } : decision === "rejected" ? {
      subject: "An update on your CIRCUM Rider application",
      preheader: "There is an update on your Rider application.",
      heading: "An update on your Rider application",
      paragraphs: ["We have reviewed your CIRCUM Rider application.", "Open the Rider app to view the latest decision and available next steps."],
    } : {
      subject: "We need a little more information for your Rider application",
      preheader: "Your Rider application needs more information before it can continue.",
      heading: "We need a little more information",
      paragraphs: ["Your CIRCUM Rider application needs more information before it can continue.", "Open the Rider app to see what to do next."],
    };
    return render(copy);
  }

  if (type.startsWith("health_plus_")) {
    const status = type.slice("health_plus_".length);
    const health = {
      booking_created: ["Your Health+ collection is scheduled", "Your Health+ collection has been scheduled.", "Your collection is now in the CIRCUM Health+ schedule."],
      rider_assigned: ["A Health+ rider has been assigned", "A verified rider has been assigned to your Health+ collection.", "We will keep you updated as the collection progresses."],
      en_route_to_collection: ["Your Health+ collection is on the way", "Your Health+ rider is travelling to the collection point.", "Please keep your phone available in case the rider needs to reach you."],
      prescription_collected: ["Your prescription has been collected", "Your prescription has been collected securely through CIRCUM Health+.", "We will update you again when it is on the way."],
      en_route_to_customer: ["Your Health+ delivery is on the way", "Your Health+ delivery is on the way.", "We will let you know when it has been delivered."],
      delivered: ["Your Health+ delivery has been completed", "Your Health+ delivery has been completed.", "You can open CIRCUM to review the delivery details."],
      rescheduled: ["Your Health+ collection has been rescheduled", "Your Health+ collection has been rescheduled.", "Open CIRCUM to review the updated timing."],
      escalated: ["Your Health+ delivery needs review", "Your Health+ delivery has been referred to the CIRCUM team for review.", "We will contact you with the next update."],
      prescription_not_ready: ["Your prescription was not ready", "The prescription was not ready at the collection point.", "CIRCUM is coordinating the next step and will keep you updated."],
      customer_unavailable: ["We could not complete your Health+ delivery", "We could not complete your Health+ delivery.", "CIRCUM will help arrange the next step."],
      override_completion: ["Your Health+ delivery is complete", "Your Health+ delivery was completed following a CIRCUM team review.", "You can open CIRCUM to review the delivery details."],
    }[status];
    if (health) return render({subject: health[0], preheader: health[1], heading: health[0], paragraphs: [health[1], health[2]]});
  }

  if (type === "gift_delivered") {
    return render({
      subject: "Your Circum gift was delivered",
      preheader: "Your gift has reached its recipient.",
      heading: "Your CIRCUM gift was delivered",
      paragraphs: [
        `Your gift to ${text(context.recipientName) || "your recipient"} was marked as delivered${text(context.deliveredAt) ? ` on ${text(context.deliveredAt)}` : ""}.`,
        reference ? `Gift reference: ${reference}` : "",
        "Open CIRCUM to view your Gifts history.",
      ],
      cta: "Open CIRCUM Gifts",
      footer: "This essential service email confirms a gift you sent with CIRCUM.",
    });
  }

  if (type === "gift_story_ready") {
    const recipient = text(context.recipientRole) === "sender" ? "Your CIRCUM Gift Story is ready" : "You have received a CIRCUM Gift Story";
    return render({
      subject: recipient,
      preheader: "Your private Gift Story is ready to view.",
      heading: recipient,
      paragraphs: [
        "Your CIRCUM Gift Story is ready.",
        text(context.storyUrl) ? `View your secure story here: ${text(context.storyUrl)}` : "Use the secure link in this email to view your private story.",
        "The private link expires according to Gift Story policy.",
      ],
      cta: "View your Gift Story",
      footer: "This message contains a private story link created for you by CIRCUM.",
    });
  }

  throw new Error(`unsupported_transactional_email_template:${eventType}`);
}

const IMPLEMENTED_TEMPLATE_EVENTS = Object.freeze([
  "sender_welcome",
  "roth_movement_completed",
  "delivery_booking_paid",
  "delivery_completed",
  "delivery_cancellation_settled",
  "business_invoice_paid",
  "referral_award_finalized",
  "rider_application_decision",
  "health_plus_booking_created",
  "health_plus_rider_assigned",
  "health_plus_en_route_to_collection",
  "health_plus_prescription_collected",
  "health_plus_en_route_to_customer",
  "health_plus_delivered",
  "health_plus_rescheduled",
  "health_plus_escalated",
  "health_plus_prescription_not_ready",
  "health_plus_customer_unavailable",
  "health_plus_override_completion",
  "gift_delivered",
  "gift_story_ready",
]);

module.exports = {IMPLEMENTED_TEMPLATE_EVENTS, renderTransactionalEmail, escapeHtml};
