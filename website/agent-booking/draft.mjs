export const DRAFT_KEY = 'circum.agentBookingDraft.v1';
export const DRAFT_TTL_MS = 15 * 60 * 1000;

const fields = {
  pickup: {type: 'string', minLength: 3, maxLength: 500, description: 'Collection address. The customer must select an address suggestion in Circum.'},
  dropoff: {type: 'string', minLength: 3, maxLength: 500, description: 'Delivery address. The customer must select an address suggestion in Circum.'},
  description: {type: 'string', minLength: 3, maxLength: 2000, description: 'Describe the parcel and handling needs.'},
  weightKg: {type: 'number', exclusiveMinimum: 0, maximum: 200, description: 'Optional declared parcel weight in kilograms; subject to Circum verification.'},
  receiverName: {type: 'string', maxLength: 120},
  receiverPhone: {type: 'string', maxLength: 40},
};

export const bookingInputSchema = Object.freeze({
  type: 'object', additionalProperties: false,
  properties: fields, required: ['pickup', 'dropoff', 'description'],
});

export function prepareDraft(input, now = Date.now()) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('Provide booking details as an object.');
  if (Object.keys(input).some(key => !Object.hasOwn(fields, key))) throw new Error('Unsupported booking field. Only parcel and receiver details are accepted.');
  const details = {};
  for (const [key, spec] of Object.entries(fields)) {
    const value = input[key];
    if (value === undefined) {
      if (bookingInputSchema.required.includes(key)) throw new Error(`${key} is required.`);
      continue;
    }
    if (spec.type === 'number') {
      if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0 || value > spec.maximum) throw new Error('Weight must be between 0 and 200 kg.');
      details[key] = value;
    } else {
      if (typeof value !== 'string' || /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/u.test(value)) throw new Error(`${key} must be plain text without control characters.`);
      const text = value.trim();
      if (text.length < (spec.minLength || 0) || text.length > spec.maxLength) throw new Error(`${key} has an invalid length.`);
      details[key] = text;
    }
  }
  return {version: 1, createdAt: now, expiresAt: now + DRAFT_TTL_MS, status: 'customer_review_required', details};
}

export function reviewDraft(draft, now = Date.now()) {
  if (!draft || draft.version !== 1 || draft.status !== 'customer_review_required' ||
      !Number.isFinite(draft.createdAt) || !Number.isFinite(draft.expiresAt) ||
      draft.createdAt > now || draft.expiresAt <= now || draft.expiresAt - draft.createdAt !== DRAFT_TTL_MS) {
    throw new Error('This draft has expired. Prepare a new draft.');
  }
  prepareDraft(draft.details, draft.createdAt);
  return draft;
}
