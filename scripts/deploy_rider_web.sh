#!/usr/bin/env bash
set -euo pipefail

flutter build web --release --target lib/main_rider.dart
rm -rf build/web_rider
mv build/web build/web_rider
node scripts/hosting_manifest.js prepare rider
./scripts/verify_hosting_build.sh rider
firebase deploy --only hosting:rider --project circum-2797c
