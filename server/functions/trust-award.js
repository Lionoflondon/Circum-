/* eslint-disable require-jsdoc */

function highestTrustAward(delivery = {}) {
  const category = `${delivery.category || delivery.deliveryType || delivery.serviceType || ""}`.toLowerCase();
  const enabled = (key) => delivery[key] === true;
  if (enabled("isHealthPlus") || enabled("healthPlus") || category.includes("health")) return 6;
  if (enabled("isGift") || enabled("gift") || category.includes("gift")) return 5;
  if (enabled("isScheduled") || enabled("scheduled") || delivery.scheduledAt || category.includes("scheduled")) return 5;
  if (enabled("requiresVanguard") || enabled("vanguard") || category.includes("vanguard")) return 4;
  if (enabled("isHeavyDuty") || enabled("heavyDuty") || category.includes("heavy")) return 4;
  if (enabled("isBusiness") || enabled("business") || category.includes("business")) return 3;
  if (enabled("isMarketplace") || enabled("marketplace") || category.includes("marketplace")) return 2;
  return 1;
}

module.exports = {highestTrustAward};
