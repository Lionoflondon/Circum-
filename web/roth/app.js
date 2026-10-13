import {validateAccess, validateWallet, paymentMessage, checkoutDestination} from './state.mjs';
const form = document.querySelector('#account-form');
const verification = document.querySelector('#verification');
const statusLine = document.querySelector('#status');
const config = window.ROTH_CONFIG || {};
let access = null;
let challenge = null;
let busy = false;
let appCheckPromise;
const panel = document.createElement('div');
panel.hidden = true;
panel.innerHTML = '<p id="balance" aria-live="polite"></p><label for="amount">Test top-up amount (£)</label><input id="amount" type="number" min="1" max="100" step="1" value="1"><p id="quote">£1 adds 1 test ROTH.</p><button class="button" id="pay">Continue to Stripe TEST</button><button class="back" id="refresh-wallet">Refresh balance and payment</button><button class="back" id="logout">Log out</button>';
verification.after(panel);
const amount = document.querySelector('#amount');
amount.addEventListener('input', () => {
  const n = Number(amount.value);
  document.querySelector('#quote').textContent = Number.isInteger(n) && n >= 1 && n <= 100 ? `£${n} adds ${n} test ROTH.` : 'Choose a whole-pound amount between £1 and £100.';
});
async function secureToken() {
  if (!config.appCheckSiteKey) throw Error('Secure verification is unavailable.');
  if (!appCheckPromise) appCheckPromise = (async () => {
    const [{initializeApp}, {initializeAppCheck, ReCaptchaEnterpriseProvider, getToken}, response] = await Promise.all([
      import('https://www.gstatic.com/firebasejs/12.16.0/firebase-app.js'), import('https://www.gstatic.com/firebasejs/12.16.0/firebase-app-check.js'), fetch('/__/firebase/init.json', {cache: 'no-store'})]);
    const firebase = await response.json();
    if (!response.ok || firebase.projectId !== 'circum-2797c') throw Error('Invalid website configuration.');
    const app = initializeApp(firebase, 'roth-web');
    const check = initializeAppCheck(app, {provider: new ReCaptchaEnterpriseProvider(config.appCheckSiteKey), isTokenAutoRefreshEnabled: true});
    return async () => (await getToken(check)).token;
  })();
  return (await appCheckPromise)();
}
async function api(action, data) {
  if (!config.enabled) throw Error('Top-ups are not available yet. Nothing has been charged.');
  const response = await fetch(`/api/roth/${action}`, {method: 'POST', headers: {'Content-Type': 'application/json', 'X-Firebase-AppCheck': await secureToken()}, body: JSON.stringify(data)});
  let value;
  try {value = await response.json();} catch (_) {throw Error('Unable to read the server response.');}
  if (!response.ok) throw Error(value.error || 'Unable to complete this request.');
  return value;
}
async function run(operation) {
  if (busy) return;
  busy = true;
  document.querySelectorAll('.checkout button').forEach(b => b.disabled = true);
  try {await operation();} catch (error) {statusLine.textContent = error.message;}
  finally {busy = false; document.querySelectorAll('.checkout button').forEach(b => b.disabled = false);}
}
function reset() {
  access = null; challenge = null;
  sessionStorage.removeItem('roth-verification');
  panel.hidden = true; verification.hidden = true; form.hidden = false;
  document.querySelector('#balance').textContent = '';
  document.querySelector('#code').value = '';
  statusLine.textContent = 'Verify your registered account to view your test wallet.';
}
async function refresh() {
  const state = await api('status', validateAccess(access));
  statusLine.textContent = paymentMessage(state);
  document.querySelector('#balance').textContent = `Test wallet balance: ${validateWallet(state).balance} ROTH`;
}
form.addEventListener('submit', event => {
  event.preventDefault();
  if (!form.reportValidity()) return;
  run(async () => {
    challenge = await api('request', {identifier: document.querySelector('#account').value});
    if (!/^[a-f0-9]{64}$/.test(challenge.challengeId || '')) throw Error('Unable to verify this account.');
    form.hidden = true; verification.hidden = false;
    statusLine.textContent = 'If your account is eligible, check its registered email for a code. It expires in 10 minutes.';
    document.querySelector('#code').focus();
  });
});
document.querySelector('#verify-code').addEventListener('click', () => run(async () => {
  access = validateAccess(await api('verify', {...challenge, code: document.querySelector('#code').value}));
  sessionStorage.setItem('roth-verification', JSON.stringify(access));
  verification.hidden = true; panel.hidden = false;
  const wallet = validateWallet(await api('wallet', access));
  document.querySelector('#balance').textContent = `Test wallet balance: ${wallet.balance} ROTH`;
  statusLine.textContent = 'Account verified. Stripe TEST only; your real wallet remains separate.';
}));
document.querySelector('#back').addEventListener('click', reset);
document.querySelector('#pay').addEventListener('click', () => run(async () => {
  if (!amount.reportValidity()) return;
  const result = await api('checkout', {...validateAccess(access), amountPence: Math.round(Number(amount.value) * 100)});
  location.assign(checkoutDestination(result.checkoutUrl));
}));
document.querySelector('#refresh-wallet').addEventListener('click', () => run(refresh));
document.querySelector('#logout').addEventListener('click', () => run(async () => {await api('logout', validateAccess(access)); reset();}));
try {access = validateAccess(JSON.parse(sessionStorage.getItem('roth-verification')));} catch (_) {access = null; sessionStorage.removeItem('roth-verification');}
if (access) {
  form.hidden = true; panel.hidden = false;
  run(async () => {
    if (new URLSearchParams(location.search).get('payment') === 'cancelled') await api('cancel', access);
    await refresh();
  });
}
