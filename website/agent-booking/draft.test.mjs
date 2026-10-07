import test from 'node:test';
import assert from 'node:assert/strict';
import {prepareDraft, reviewDraft, DRAFT_TTL_MS} from './draft.mjs';

const details = {pickup: 'Example collection address', dropoff: 'Example delivery address', description: 'A parcel of books', weightKg: 2};
test('a draft requires customer review and has no booking or payment authority', () => {
  const draft = prepareDraft(details, 1000);
  assert.equal(draft.status, 'customer_review_required');
  assert.deepEqual(draft.details, details);
  assert.deepEqual(Object.keys(draft).sort(), ['createdAt', 'details', 'expiresAt', 'status', 'version']);
  assert.equal(reviewDraft(draft, 1001), draft);
});
test('expired, future and tampered drafts cannot continue', () => {
  const draft = prepareDraft(details, 1000);
  assert.throws(() => reviewDraft(draft, 1000 + DRAFT_TTL_MS));
  assert.throws(() => reviewDraft(draft, 999));
  assert.throws(() => reviewDraft({...draft, status: 'approved'}, 1001));
  assert.throws(() => reviewDraft({...draft, expiresAt: draft.expiresAt + 1}, 1001));
});
test('rejects execution fields, invalid numbers, oversized text and control characters', () => {
  for (const input of [{...details, paid: true}, {...details, customerUid: 'someone'}, {...details, weightKg: '2'}, {...details, weightKg: Infinity}, {...details, weightKg: 0}, {...details, weightKg: 201}, {...details, pickup: 'x'.repeat(501)}, {...details, description: '\u0000parcel'}, {...details, description: null}]) {
    assert.throws(() => prepareDraft(input));
  }
});
