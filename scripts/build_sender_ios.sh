#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${STRIPE_PUBLISHABLE_KEY:?Missing Sender Stripe publishable key}"
: "${PAYMENT_ENVIRONMENT:?Missing explicit Sender payment environment}"
: "${SENDER_IOS_GOOGLE_MAPS_API_KEY:?Missing Sender iOS Maps key}"
case "$PAYMENT_ENVIRONMENT:$STRIPE_PUBLISHABLE_KEY" in
  test:pk_test_*) ;;
  live:pk_live_*) ;;
  *) echo 'Stripe key does not match payment environment.' >&2; exit 1 ;;
esac
if [[ "${1:-}" == --validate-only ]]; then
  echo "Sender iOS payment configuration valid ($PAYMENT_ENVIRONMENT)."
  exit 0
fi
GOOGLE_MAPS_API_KEY="$SENDER_IOS_GOOGLE_MAPS_API_KEY" flutter build ipa \
  --release --target=lib/main.dart \
  --dart-define=STRIPE_PUBLISHABLE_KEY="$STRIPE_PUBLISHABLE_KEY" \
  --dart-define=PAYMENT_ENVIRONMENT="$PAYMENT_ENVIRONMENT" "$@"
