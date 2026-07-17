#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
node scripts/sender/validate_sender.js
firebase deploy --config firebase.json --only hosting:sender --project circum-2797c
