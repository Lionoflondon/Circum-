import {DRAFT_KEY, bookingInputSchema, prepareDraft, reviewDraft} from './draft.mjs';

const form = document.querySelector('#draft-form');
const error = document.querySelector('#error');
const summary = document.querySelector('#summary');
const review = document.querySelector('#review');
const continueButton = document.querySelector('#continue');
let currentDraft;

function showDraft(input) {
  const next = prepareDraft(input);
  currentDraft = next;
  summary.replaceChildren();
  const labels = {pickup: 'Collection', dropoff: 'Delivery', description: 'Parcel', weightKg: 'Declared weight', receiverName: 'Receiver', receiverPhone: 'Receiver phone'};
  for (const [key, value] of Object.entries(next.details)) {
    if (value === '') continue;
    const term = document.createElement('dt');
    const detail = document.createElement('dd');
    term.textContent = labels[key];
    detail.textContent = key === 'weightKg' ? `${value} kg` : value;
    summary.append(term, detail);
    if (form.elements[key]) form.elements[key].value = String(value);
  }
  review.hidden = false;
  continueButton.disabled = false;
  error.textContent = '';
  return {status: next.status, draft: next.details, expiresAt: next.expiresAt,
    nextStep: 'Ask the customer to review the visible draft and choose Review in Circum. No booking, quote, payment or rider dispatch has been created.'};
}

form.addEventListener('submit', event => {
  event.preventDefault();
  const input = Object.fromEntries(new FormData(form));
  for (const key of ['receiverName', 'receiverPhone']) if (!input[key]) delete input[key];
  if (input.weightKg === '') delete input.weightKg;
  else input.weightKg = Number(input.weightKg);
  try { showDraft(input); } catch (failure) { error.textContent = failure.message; }
});

form.addEventListener('input', () => {
  currentDraft = undefined;
  review.hidden = true;
  continueButton.disabled = true;
});

continueButton.addEventListener('click', () => {
  try {
    const draft = reviewDraft(currentDraft);
    sessionStorage.setItem(DRAFT_KEY, JSON.stringify(draft));
    location.assign('/send?agentDraft=review');
  } catch (failure) {
    error.textContent = failure.message;
    continueButton.disabled = true;
  }
});

const modelContext = document.modelContext || navigator.modelContext;
if (modelContext?.registerTool) {
  try {
    await modelContext.registerTool({
      name: 'prepare_circum_booking_draft',
      description: 'Prepare a Circum personal parcel delivery draft for customer review in this browser. Collect parcel addresses and details with the customer’s permission. This tool does not create a booking, get a quote, charge a payment or dispatch a rider. Stop after preparing the draft and ask the customer to review it.',
      inputSchema: bookingInputSchema,
      execute: async input => showDraft(input),
      annotations: {readOnlyHint: false, untrustedContentHint: true},
    });
    document.querySelector('#agent-status').textContent = 'Browser agent tools are available.';
  } catch {
    document.querySelector('#agent-status').textContent = 'Use the form below to prepare a draft.';
  }
}
