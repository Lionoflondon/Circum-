#!/usr/bin/env bash
set -euo pipefail

environment="${PAYMENT_ENVIRONMENT:-}"
publishable_key="${STRIPE_PUBLISHABLE_KEY:-}"

case "$environment" in
  test)
    [[ "$publishable_key" == pk_test_* ]] || {
      echo "Sender test build requires a Stripe test publishable key." >&2
      exit 1
    }
    ;;
  live)
    [[ "$publishable_key" == pk_live_* ]] || {
      echo "Sender live build requires a Stripe live publishable key." >&2
      exit 1
    }
    ;;
  *)
    echo "PAYMENT_ENVIRONMENT must be explicitly test or live." >&2
    exit 1
    ;;
esac
