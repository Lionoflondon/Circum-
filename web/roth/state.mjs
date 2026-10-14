export function validateAccess(value) {
  if (!value || !/^[a-f0-9]{64}$/.test(value.challengeId || '') || !/^[a-f0-9]{64}$/.test(value.token || '')) throw Error('Please verify your account again.');
  return {challengeId: value.challengeId, token: value.token};
}
export function validateWallet(value, environment = 'test') {
  if (!value || !['test','live'].includes(environment) || value.environment !== environment || !Number.isFinite(value.balance) || value.balance < 0) throw Error('Unable to read your wallet safely.');
  return value;
}
export function paymentMessage(value, environment = 'test') {
  validateWallet(value, environment);
  if (!['pending', 'credited', 'failed', 'cancelled'].includes(value.status)) throw Error('Unknown payment status.');
  if (value.status === 'credited' && (!Number.isFinite(value.roth) || value.roth <= 0)) throw Error('Invalid purchase quantity.');
  return {pending: 'Payment is pending. We are waiting for confirmation.', credited: `${value.roth} ROTH added to your ${environment === 'test' ? 'test wallet' : 'Circum wallet'}.`, failed: 'Payment failed. No credit was awarded for this payment.', cancelled: 'Checkout cancelled or expired. No credit was awarded for this payment.'}[value.status];
}
export function checkoutDestination(value) {
  const url = new URL(value);
  if (url.protocol !== 'https:' || url.hostname !== 'checkout.stripe.com' || url.username || url.password) throw Error('Invalid payment destination.');
  return url.href;
}
