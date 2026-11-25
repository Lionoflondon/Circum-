import {parseRecoveryLink, createRecoveryFlow, recoveryError} from './recovery.mjs';

const status = document.getElementById('status');
const form = document.getElementById('reset-form');
const errorText = document.getElementById('error');
const password = document.getElementById('password');
const confirmation = document.getElementById('confirm');
const submit = document.getElementById('submit');
const returnLink = document.getElementById('return');
let action;
try { action = parseRecoveryLink(location.href); } catch { /* Invalid links never reach Auth. */ }
// Remove credentials from history before loading any network dependency.
history.replaceState(null, '', location.pathname);

if (!action) {
  status.textContent = 'This reset link is incomplete or invalid. Please request a new one from the login page.';
} else {
  returnLink.href = action.returnPath;
  initialise();
}

async function initialise() {
  let flow;
  try {
    const [{initializeApp}, sdk, response] = await Promise.all([
      import('https://www.gstatic.com/firebasejs/12.16.0/firebase-app.js'),
      import('https://www.gstatic.com/firebasejs/12.16.0/firebase-auth.js'),
      fetch('/__/firebase/init.json', {cache: 'no-store', credentials: 'omit', referrerPolicy: 'no-referrer'}),
    ]);
    if (!response.ok) throw new Error('configuration-unavailable');
    const config = await response.json();
    if (config.projectId !== 'circum-2797c') throw new Error('invalid-project');
    const auth = sdk.initializeAuth(initializeApp(config), {persistence: sdk.inMemoryPersistence});
    flow = createRecoveryFlow({
      verify: code => sdk.verifyPasswordResetCode(auth, code),
      validate: value => sdk.validatePassword(auth, value),
      confirm: (code, value) => sdk.confirmPasswordReset(auth, code, value),
    });
    const requirements = await flow.open(action.code);
    action.code = undefined;
    document.getElementById('requirements').replaceChildren(...requirements.map(text => {
      const item = document.createElement('li'); item.textContent = text; return item;
    }));
    status.textContent = 'Choose a new password for your CIRCUM account.';
    form.hidden = false;
    form.addEventListener('submit', async event => {
      event.preventDefault();
      if (submit.disabled) return;
      submit.disabled = true;
      submit.textContent = 'Securing your account…';
      errorText.textContent = '';
      try {
        const result = await flow.submit(password.value, confirmation.value);
        if (!result.ok) { errorText.textContent = result.message; return; }
        form.reset(); form.hidden = true;
        document.getElementById('form-title').textContent = 'Your password is updated';
        status.textContent = 'You can now log in with your new password. This reset link cannot be used again.';
        returnLink.textContent = 'Continue to login'; returnLink.classList.add('primary');
        returnLink.focus();
      } catch (error) {
        const state = recoveryError(error);
        errorText.textContent = state.message;
        if (state.terminal) { flow.clear(); form.reset(); form.hidden = true; status.textContent = state.message; }
      } finally { submit.disabled = false; submit.textContent = 'Reset password'; }
    });
    document.getElementById('show-password').addEventListener('click', event => {
      const show = password.type === 'password';
      password.type = confirmation.type = show ? 'text' : 'password';
      event.target.textContent = show ? 'Hide' : 'Show';
      event.target.setAttribute('aria-pressed', String(show));
    });
    window.addEventListener('pagehide', () => { flow.clear(); form.reset(); });
  } catch (error) {
    flow?.clear(); action.code = undefined;
    const state = recoveryError(error);
    status.textContent = state.terminal ? state.message : 'Secure recovery is temporarily unavailable. Reopen the link in your email to try again.';
  }
}
