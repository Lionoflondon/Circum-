#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
node scripts/public/validate_public.js
firebase deploy --config firebase.json --only hosting:public --project circum-2797c
