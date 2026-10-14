import {validateAccess, validateWallet, paymentMessage, checkoutDestination} from './state.mjs';
const form = document.querySelector('#account-form');
const verification = document.querySelector('#verification');
const statusLine = document.querySelector('#status');
const config = window.ROTH_CONFIG || {};
const environment = config.environment === 'live' ? 'live' : 'test';
const test = environment === 'test';
const storageKey = test ? 'roth-verification' : 'roth-live-verification';
const apiPath = test ? '/api/roth' : '/api/roth-live';
if (!test) statusLine.textContent = 'Verify your registered Circum account to buy ROTH.';
let access = null;
let challenge = null;
let busy = false;
let completedOrder = false;
let appCheckPromise;
const panel = document.createElement('div');
panel.hidden = true;
panel.innerHTML = '<p id="balance" aria-live="polite"></p><label for="amount">Test top-up amount (£)</label><input id="amount" type="number" min="1" max="100000" step="1" value="1"><p id="quote">£1 adds 1 test ROTH.</p><button class="button" id="pay">Continue to Stripe TEST</button><button class="back" id="refresh-wallet">Refresh balance and payment</button><button class="back" id="logout">Log out</button>';
if (!test) {
  panel.querySelector('label').textContent = 'Top-up amount (£)';
  panel.querySelector('#quote').textContent = '£1 adds 1 ROTH.';
  panel.querySelector('#pay').textContent = 'Continue to Stripe';
}
verification.after(panel);
if (config.privateCertification) {
  const notice=document.createElement('p');
  notice.className='preview-note';
  notice.textContent='LIVE verification: this purchase uses real money. Public purchases remain unavailable.';
  panel.before(notice);
}
const amount = document.querySelector('#amount');
amount.addEventListener('input', () => {
  const n = Number(amount.value);
  document.querySelector('#quote').textContent = Number.isInteger(n) && n >= 1 && n <= 100000 ? `£${n.toLocaleString("en-GB")} adds ${n.toLocaleString("en-GB")}${test ? ' test' : ''} ROTH.` : 'Choose a whole-pound amount between £1 and £100,000.';
});
async function secureToken() {
  if (!config.appCheckSiteKey || !config.firebaseAppId) throw Error('Secure verification is unavailable.');
  if (!appCheckPromise) appCheckPromise = (async () => {
    const [{initializeApp}, {initializeAppCheck, ReCaptchaEnterpriseProvider, getToken}, response] = await Promise.all([
      import('https://www.gstatic.com/firebasejs/12.16.0/firebase-app.js'), import('https://www.gstatic.com/firebasejs/12.16.0/firebase-app-check.js'), fetch('/__/firebase/init.json', {cache: 'no-store'})]);
    const firebase = await response.json();
    if (!response.ok || firebase.projectId !== 'circum-2797c') throw Error('Invalid website configuration.');
    const app = initializeApp({...firebase, appId: config.firebaseAppId}, 'roth-web');
    const check = initializeAppCheck(app, {provider: new ReCaptchaEnterpriseProvider(config.appCheckSiteKey), isTokenAutoRefreshEnabled: true});
    return async () => (await getToken(check)).token;
  })();
  return (await appCheckPromise)();
}
async function api(action, data) {
  if (!config.enabled) throw Error('Top-ups are not available yet. Nothing has been charged.');
  const response = await fetch(`${apiPath}/${action}`, {method: 'POST', headers: {'Content-Type': 'application/json', 'X-Firebase-AppCheck': await secureToken()}, body: JSON.stringify(data)});
  let value;
  try {value = await response.json();} catch (_) {throw Error('Unable to read the server response.');}
  if (!response.ok) {
    if (/Verification required|Account changed/.test(value.error || '')) reset();
    throw Error(value.error || 'Unable to complete this request.');
  }
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
  access = null; challenge = null; completedOrder = false;
  sessionStorage.removeItem(storageKey);
  panel.hidden = true; verification.hidden = true; form.hidden = false;
  document.querySelector('#balance').textContent = '';
  document.querySelector('#code').value = '';
  statusLine.textContent = `Verify your registered account to view your ${test ? 'test ' : ''}wallet.`;
}
async function refresh() {
  const state = await api('status', validateAccess(access));
  statusLine.textContent = paymentMessage(state, environment);
  completedOrder = ['credited', 'failed', 'cancelled'].includes(state.status);
  document.querySelector('#pay').textContent = completedOrder ? 'Start a new top-up' : (test ? 'Continue to Stripe TEST' : 'Continue to Stripe');
  document.querySelector('#balance').textContent = `${test ? 'Test wallet' : 'Wallet'} balance: ${validateWallet(state, environment).balance} ROTH`;
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
  sessionStorage.setItem(storageKey, JSON.stringify(access));
  verification.hidden = true; panel.hidden = false;
  const wallet = validateWallet(await api('wallet', access), environment);
  document.querySelector('#balance').textContent = `${test ? 'Test wallet' : 'Wallet'} balance: ${wallet.balance} ROTH`;
  statusLine.textContent = test ? 'Account verified. Stripe TEST only; your real wallet remains separate.' : 'Account verified. Choose your ROTH top-up.';
}));
document.querySelector('#back').addEventListener('click', reset);
document.querySelector('#pay').addEventListener('click', () => run(async () => {
  if (completedOrder) {reset(); return;}
  if (!amount.reportValidity()) return;
  const result = await api('checkout', {...validateAccess(access), amountPence: Math.round(Number(amount.value) * 100)});
  location.assign(checkoutDestination(result.checkoutUrl));
}));
document.querySelector('#refresh-wallet').addEventListener('click', () => run(refresh));
document.querySelector('#logout').addEventListener('click', () => run(async () => {try {await api('logout', validateAccess(access));} finally {reset();}}));
try {access = validateAccess(JSON.parse(sessionStorage.getItem(storageKey)));} catch (_) {access = null; sessionStorage.removeItem(storageKey);}
if (access) {
  form.hidden = true; panel.hidden = false;
  run(async () => {
    if (new URLSearchParams(location.search).get('payment') === 'cancelled') await api('cancel', access);
    await refresh();
  });
}
