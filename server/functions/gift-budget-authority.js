"use strict";

function pence(value) {
  const amount = Number(value);
  return Number.isFinite(amount) && amount >= 0 ? Math.round(amount) : 0;
}

function createGiftBudgetAuthority(submittedBudgetPence) {
  const budgetPence = pence(submittedBudgetPence);
  return {
    budgetPence,
    customerLiabilityPence: 0,
    remainingPence: budgetPence,
    allocations: {},
  };
}

function allocateGiftBudget(authority, key, amountPence) {
  const amount = pence(amountPence);
  const next = {...authority, allocations: {...authority.allocations}};
  const previous = pence(next.allocations[key]);
  const nextTotal = pence(next.customerLiabilityPence) + amount;
  if (nextTotal > pence(next.budgetPence)) {
    const error = new Error("Gift fulfilment exceeds the submitted budget.");
    error.code = "gift_budget_exceeded";
    throw error;
  }
  next.allocations[key] = previous + amount;
  next.customerLiabilityPence = nextTotal;
  next.remainingPence = pence(next.budgetPence) - nextTotal;
  return next;
}

module.exports = {allocateGiftBudget, createGiftBudgetAuthority};
