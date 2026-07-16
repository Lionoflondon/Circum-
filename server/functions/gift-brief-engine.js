/* eslint-disable max-len, require-jsdoc */
"use strict";

const SCHEMA_VERSION = "2026-07-07.v1";
const GENERATED_BY = "IRIS";

const CANONICAL_INTEREST_SIGNALS = new Map([
  ["fashion", "fashionInterest"],
  ["beauty", "beautyInterest"],
  ["makeup", "beautyInterest"],
  ["skincare", "skincareInterest"],
  ["fragrance", "fragranceInterest"],
  ["jewellery", "jewelleryInterest"],
  ["jewelry", "jewelleryInterest"],
]);

function text(value) {
  return `${value == null ? "" : value}`.trim();
}

function list(value) {
  if (Array.isArray(value)) {
    return value.map(text).filter(Boolean);
  }
  if (typeof value === "string") {
    return value.split(/[,;\n]/).map(text).filter(Boolean);
  }
  return [];
}

function unique(values) {
  return [...new Set(values.map(text).filter(Boolean))];
}

function sentence(parts, fallback) {
  const clean = parts.map(text).filter(Boolean);
  return clean.length ? clean.join(" ") : fallback;
}

function firstNonEmpty(...values) {
  return values.map(text).find(Boolean) || "";
}

function lowerTerms(values) {
  return unique(values).map((value) => value.toLowerCase());
}

function scoreFromTerms(terms, needles) {
  const matches = terms.filter((term) => needles.some((needle) => term.includes(needle)));
  return Math.min(100, matches.length * 24);
}

function supportedSignals(interests) {
  const signals = [];
  const unsupported = [];
  for (const interest of unique(interests)) {
    const signal = CANONICAL_INTEREST_SIGNALS.get(interest.toLowerCase());
    if (signal) signals.push({interest, signal});
    else unsupported.push(interest);
  }
  return {signals, unsupported};
}

function pendingInterestRecords(customInterests, giftRequestId) {
  return unique(customInterests).map((interest) => ({
    interest,
    status: "pending",
    source: "sender_mobile_gifts",
    giftRequestId,
    reviewedBy: null,
    reviewedAt: null,
  }));
}

function voiceSummary(gift) {
  const transcript = firstNonEmpty(gift.voiceTranscript, gift.voiceNoteTranscript);
  const summary = firstNonEmpty(gift.voiceSummary, gift.voiceEmotionalSummary);
  const sentiment = firstNonEmpty(gift.voiceSentiment);
  if (!transcript && !summary && !sentiment) {
    return {
      transcript: "",
      language: "",
      durationSeconds: null,
      sentiment: "not_available",
      keyPhrases: [],
      emotionalSummary: "No voice note supplied.",
    };
  }
  return {
    transcript,
    language: firstNonEmpty(gift.voiceLanguage, "unknown"),
    durationSeconds: Number.isFinite(Number(gift.voiceDurationSeconds)) ? Number(gift.voiceDurationSeconds) : null,
    sentiment: sentiment || "pending_analysis",
    keyPhrases: list(gift.voiceKeyPhrases),
    emotionalSummary: summary || transcript.slice(0, 220),
  };
}

function buildGiftBrief(gift, options = {}) {
  const giftRequestId = text(options.giftRequestId || gift.giftRequestId || gift.id);
  const recipientName = firstNonEmpty(gift.recipientName, "the recipient");
  const relationship = firstNonEmpty(gift.relationship, "Not specified");
  const occasion = firstNonEmpty(gift.occasion, "Not specified");
  const notes = firstNonEmpty(gift.notes, gift.recipientDescription, gift.aboutRecipient);
  const personalMessage = firstNonEmpty(gift.personalMessage, gift.senderMessageText);
  const interests = unique([...list(gift.interests), ...list(gift.interestTags)]);
  const customInterests = unique([
    ...list(gift.customInterest),
    ...list(gift.customInterests),
  ]).filter((interest) => !interests.map((item) => item.toLowerCase()).includes(interest.toLowerCase()));
  const allInterests = unique([...interests, ...customInterests]);
  const {signals, unsupported} = supportedSignals(allInterests);
  const sizes = gift.sizesAndPreferences && typeof gift.sizesAndPreferences === "object" ? gift.sizesAndPreferences : {};
  const colours = unique([
    ...list(gift.favouriteColours),
    ...list(gift.favoriteColours),
    ...list(sizes.favouriteColours),
  ]);
  const brands = unique([
    ...list(gift.likedBrands),
    ...list(gift.brandsLiked),
    ...list(sizes.brandsLiked),
  ]);
  const terms = lowerTerms([relationship, occasion, notes, personalMessage, ...allInterests, ...brands, ...colours]);
  const romanticScore = scoreFromTerms(terms, ["partner", "wife", "husband", "fiancé", "fiancée", "anniversary", "romantic", "love"]);
  const sentimentalScore = scoreFromTerms(terms, ["memory", "meaning", "family", "thank", "appreciation", "personal", "heart", "special"]);
  const humourScore = scoreFromTerms(terms, ["funny", "joke", "playful", "humour", "humor"]);
  const experienceScore = scoreFromTerms(terms, ["travel", "dining", "spa", "experience", "concert", "theatre", "adventure"]);
  const luxuryPreference = terms.some((term) => ["luxury", "jewellery", "watch", "designer", "fine dining", "fragrance"].some((needle) => term.includes(needle)));
  const practicalPreference = terms.some((term) => ["practical", "useful", "work", "business", "home", "fitness"].some((needle) => term.includes(needle)));
  const confidenceScore = Math.min(96, 42 +
    (relationship !== "Not specified" ? 10 : 0) +
    (occasion !== "Not specified" ? 10 : 0) +
    (notes ? 12 : 0) +
    (personalMessage ? 8 : 0) +
    (allInterests.length ? 8 : 0) +
    (brands.length ? 3 : 0) +
    (colours.length ? 3 : 0));
  const missingInformation = [
    relationship === "Not specified" ? "Relationship" : "",
    occasion === "Not specified" ? "Occasion" : "",
    notes ? "" : "Recipient description",
    allInterests.length ? "" : "Interests",
    text(gift.deliveryAddress) ? "" : "Delivery address",
    text(gift.deliveryDate) ? "" : "Delivery date",
  ].filter(Boolean);
  const avoidSignals = [
    unsupported.length ? `Unsupported interest coverage: ${unsupported.join(", ")}` : "",
    text(gift.senderRevealMode).includes("anonymous") ? "Do not reveal sender identity before consent." : "",
    missingInformation.length ? "Avoid precise sourcing decisions until missing information is reviewed." : "",
  ].filter(Boolean);
  const voice = voiceSummary(gift);

  return {
    summary: sentence([
      `A ${occasion.toLowerCase()} gift for ${recipientName}.`,
      relationship !== "Not specified" ? `Relationship: ${relationship}.` : "",
      notes ? `Recipient context: ${notes}` : "",
    ], "IRIS needs more sender context before producing a confident gift brief."),
    relationship,
    occasion,
    recipientProfile: notes || "No recipient description supplied.",
    emotionalTone: sentimentalScore >= romanticScore ? "Warm, considered, emotionally attentive." : "Personal, polished, relationship-led.",
    writingStyle: personalMessage ? "Mirror the sender's personal message tone; keep it intimate and concise." : "Premium, warm and concise.",
    voiceSummary: voice.emotionalSummary,
    voiceSentiment: voice.sentiment,
    voice,
    interestSummary: allInterests.length ? allInterests.join(", ") : "No interests supplied.",
    brandSummary: brands.length ? brands.join(", ") : "No brand affinity supplied.",
    colourSummary: colours.length ? colours.join(", ") : "No colour affinity supplied.",
    styleSummary: sentence([
      sizes.clothingSize ? `Size notes: ${sizes.clothingSize}.` : "",
      sizes.shoeSize ? `Shoe: ${sizes.shoeSize}.` : "",
      sizes.ringSize ? `Ring: ${sizes.ringSize}.` : "",
    ], "No size or fit preferences supplied."),
    experienceDirection: experienceScore > 0 ? "Experience-led gift direction is appropriate." : "Curated object or intimate gesture direction is appropriate.",
    giftDirection: luxuryPreference ? "Luxury concierge curation with restraint." : "Thoughtful, personal curation before product selection.",
    giftSignals: unique(signals.map((entry) => entry.signal)),
    giftSignalDetails: signals,
    avoidSignals,
    confidenceScore,
    manualReviewRequired: confidenceScore < 70 || missingInformation.length > 0 || unsupported.length > 0,
    missingInformation,
    outstandingQuestions: missingInformation.map((field) => `Confirm ${field.toLowerCase()} before final sourcing.`),
    interestClusters: allInterests,
    brandAffinity: brands,
    colourAffinity: colours,
    lifestyleIndicators: terms.filter((term) => ["travel", "fitness", "work", "home", "food", "music", "art", "books"].some((needle) => term.includes(needle))).slice(0, 8),
    luxuryPreference,
    practicalPreference,
    humourScore,
    romanticScore,
    sentimentalScore,
    experienceScore,
    knownRestrictions: list(gift.knownRestrictions || gift.restrictions || gift.allergies),
    knownUncertainties: unsupported,
    pendingInterests: pendingInterestRecords([...customInterests, ...unsupported], giftRequestId),
    generatedAt: options.generatedAt || new Date().toISOString(),
    generatedBy: GENERATED_BY,
    schemaVersion: SCHEMA_VERSION,
  };
}

function giftBriefUpdate(gift, options = {}) {
  const giftBrief = buildGiftBrief(gift, options);
  return {
    giftBrief,
    irisGiftBriefStatus: "complete",
    irisGiftBriefGeneratedBy: GENERATED_BY,
    irisGiftBriefSchemaVersion: SCHEMA_VERSION,
    irisPendingInterests: giftBrief.pendingInterests,
  };
}

module.exports = {
  SCHEMA_VERSION,
  CANONICAL_INTEREST_SIGNALS,
  buildGiftBrief,
  giftBriefUpdate,
  senderGiftIrisSignalsForThemes: (themes) => unique(supportedSignals(themes).signals.map((entry) => entry.signal)),
};
