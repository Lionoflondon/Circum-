export const returnPaths = Object.freeze({sender: '/send/profile', rider: '/rider?access=login'});

export function parseRecoveryLink(value) {
  const url = new URL(value);
  const params = new URLSearchParams(url.hash.slice(1));
  const allowed = ['mode', 'oobCode', 'app'];
  if (url.search || [...params.keys()].length !== 3 ||
      allowed.some(key => params.getAll(key).length !== 1) ||
      params.get('mode') !== 'resetPassword' ||
      !/^[A-Za-z0-9_-]{20,2048}$/.test(params.get('oobCode') || '') ||
      !Object.hasOwn(returnPaths, params.get('app'))) throw new Error('invalid-link');
  return {code: params.get('oobCode'), returnPath: returnPaths[params.get('app')]};
}

export function recoveryError(error) {
  switch (error?.code) {
    case 'auth/expired-action-code':
    case 'auth/invalid-action-code':
    case 'auth/user-disabled':
    case 'auth/user-not-found':
      return {terminal: true, message: 'This reset link has expired or has already been used. Please request a new one.'};
    case 'auth/weak-password':
    case 'auth/password-does-not-meet-requirements':
      return {terminal: false, message: 'Choose a password that meets all the requirements below.'};
    case 'auth/too-many-requests':
      return {terminal: false, message: 'Too many attempts. Please wait a few minutes before trying again.'};
    default:
      return {terminal: false, message: 'We could not confirm the change. Check your connection and try again.'};
  }
}

export function passwordRequirements(policy) {
  const options = policy?.customStrengthOptions || {};
  return [
    `Between ${options.minPasswordLength || 10} and ${options.maxPasswordLength || 4096} characters`,
    ...(options.containsLowercaseLetter ? ['At least one lowercase letter'] : []),
    ...(options.containsUppercaseLetter ? ['At least one uppercase letter'] : []),
    ...(options.containsNumericCharacter ? ['At least one number'] : []),
    ...(options.containsNonAlphanumericCharacter ? ['At least one symbol'] : []),
  ];
}

// Injectable Firebase adapter keeps UI state tests independent of real accounts.
export function createRecoveryFlow({verify, validate, confirm}) {
  let code;
  let busy = false;
  return {
    async open(actionCode) {
      code = undefined;
      await verify(actionCode);
      const policy = await validate('');
      code = actionCode;
      return passwordRequirements(policy.passwordPolicy);
    },
    async submit(password, confirmation) {
      if (!code || busy) throw new Error('unavailable');
      if (password !== confirmation) return {ok: false, message: 'The passwords do not match.'};
      busy = true;
      try {
        const policy = await validate(password);
        if (!policy.isValid) return {ok: false, message: 'Choose a password that meets all the requirements below.'};
        await confirm(code, password);
        code = undefined;
        return {ok: true};
      } finally { busy = false; }
    },
    clear() { code = undefined; },
  };
}
