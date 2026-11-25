#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
: "${ROTH_CONTAINMENT_BASELINE:?Reviewed baseline required}"
: "${ROTH_TEST_CERTIFICATION_FILE:?Independent TEST certification required}"
: "${ROTH_LIVE_ENV_FILE:?Private restricted LIVE env required}"
: "${ROTH_LIVE_OTP_VERSION:?Pinned LIVE OTP version required}"
: "${ROTH_LIVE_WEBHOOK_VERSION:?Pinned LIVE endpoint secret required}"
python3 scripts/verify_roth_test_containment.py
SHA="${1:?Pass exact merged current main SHA}"
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || exit 64
git fetch origin main
[[ "$(git rev-parse origin/main)" == "$SHA" ]] || { echo 'Exact current main required.' >&2; exit 1; }
node - "$ROTH_TEST_CERTIFICATION_FILE" "$ROTH_LIVE_ENV_FILE" <<'NODE'
const fs=require('fs');const p=JSON.parse(fs.readFileSync(process.argv[2]));
if(p.decision!=='PASS' || !p.automaticSignedDelivery || !p.automaticProviderRetry || !p.exactlyOnceLedger || !p.emailIdempotency || !p.walletIsolation)throw Error('Incomplete TEST certification');
const s=fs.readFileSync(process.argv[3],'utf8');
for(const [key,value] of Object.entries({WEBSITE_ROTH_LIVE_ENABLED:'true',STRIPE_MODE:'live',FIRESTORE_DATABASE_ID:'(default)',WEBSITE_ROTH_LIVE_PUBLIC:'false'})){
 const m=new RegExp('^'+key+': *["\x27]?([^"\x27\n]+)["\x27]? *$', 'm').exec(s);
 if(!m||m[1].trim()!==value)throw Error('Restricted LIVE binding required: '+key);
}
if(!/^WEBSITE_ROTH_LIVE_UIDS: *["\x27]?[^"\x27\n]+/m.test(s))throw Error('Private account allowlist required');
if(/STRIPE_SECRET_KEY|WEBHOOK_SECRET|OTP_SECRET|RESEND_API_KEY/.test(s))throw Error('Secrets must use Secret Manager references');
NODE
TMP="$(mktemp -d)"
trap 'git worktree remove --force "$TMP/source" >/dev/null 2>&1 || true; rmdir "$TMP" >/dev/null 2>&1 || true' EXIT
git worktree add --detach "$TMP/source" "$SHA"
cd "$TMP/source"
node scripts/deploy_guard.js --target=backend --base "$SHA"
python3 scripts/prepare_roth_live_overlays.py
for SERVICE in circum-stripe-webhook-live circum-transactional-email; do
 gcloud run services describe "$SERVICE" --project=circum-2797c --region=us-central1 --format=json > "$TMP/$SERVICE.json"
 node - "$TMP/$SERVICE.json" "$SERVICE" <<'NODE'
const s=JSON.parse(require('fs').readFileSync(process.argv[2]));const a=s.metadata.annotations||{};const e=s.spec.template.spec.containers[0].env;const value=n=>e.find(x=>x.name===n)?.value;
if(a['run.googleapis.com/scalingMode']==='manual'&&a['run.googleapis.com/manualInstanceCount']==='0')throw Error('Suspended owner must not restart');
if(process.argv[3]==='circum-stripe-webhook-live'){
 if(value('STRIPE_MODE')!=='live'||value('CIRCUM_SOURCE_SHA')!=='f0c24ebc763552f832c26838f14f4c679aa654d7')throw Error('LIVE owner drift requires review');
 const k=e.find(x=>x.name==='STRIPE_SECRET_KEY')?.valueFrom?.secretKeyRef;
 if(k?.name!=='STRIPE_SECRET_KEY'||k.key!=='3')throw Error('LIVE key binding mismatch');
}else if(value('CIRCUM_RECOVERY_BASE_SHA')!=='b4b21042498793b3d2515adf7b22444ff1b1c60d'||value('CIRCUM_PASSWORD_RECOVERY_SHA')!=='8b4a31365fe090b52e099dd2ed869e87db384699')throw Error('Healthy email owner drift requires review');
NODE
 REV="$(node -e 'const s=JSON.parse(require("fs").readFileSync(process.argv[1]));console.log(s.status.traffic.find(t=>t.percent===100).revisionName)' "$TMP/$SERVICE.json")"
 gcloud run revisions describe "$REV" --project=circum-2797c --region=us-central1 --format='value(status.imageDigest)' > "$TMP/$SERVICE.image"
done
WEBHOOK_BASE="$(cat "$TMP/circum-stripe-webhook-live.image")"
EMAIL_BASE="$(cat "$TMP/circum-transactional-email.image")"
[[ "$WEBHOOK_BASE" == us-central1-docker.pkg.dev/circum-2797c/*@sha256:* && "$EMAIL_BASE" == us-central1-docker.pkg.dev/circum-2797c/*@sha256:* ]] || { echo 'Immutable owner images required.' >&2; exit 1; }
WEBHOOK_HASH="$(node -e 'console.log(require("./server/functions/roth-live-overlay-proof.json").webhookOriginalHash)')"
EMAIL_HASH="$(node -e 'console.log(require("./server/functions/roth-live-overlay-proof.json").emailOriginalHash)')"
REPOSITORY=us-central1-docker.pkg.dev/circum-2797c/circum-services
IMAGE="$REPOSITORY/website-roth-live:$SHA"
WEBHOOK_IMAGE="$REPOSITORY/roth-live-webhook-guard:$SHA"
EMAIL_IMAGE="$REPOSITORY/roth-live-email-guard:$SHA"
gcloud builds submit server/functions --project=circum-2797c --region=us-central1 --config=server/functions/cloudbuild.website-roth-live.yaml --substitutions="_SOURCE_SHA=$SHA,_IMAGE=$IMAGE,_WEBHOOK_BASE=$WEBHOOK_BASE,_EMAIL_BASE=$EMAIL_BASE,_WEBHOOK_IMAGE=$WEBHOOK_IMAGE,_EMAIL_IMAGE=$EMAIL_IMAGE,_WEBHOOK_HASH=$WEBHOOK_HASH,_EMAIL_HASH=$EMAIL_HASH"
gcloud run deploy circum-website-roth-live --project=circum-2797c --region=us-central1 --image="$IMAGE" --command=node --args=cloud-run-website-roth-live.js --service-account=circum-website-roth-live@circum-2797c.iam.gserviceaccount.com --min-instances=0 --max-instances=1 --concurrency=8 --cpu=1 --memory=256Mi --timeout=60 --no-cpu-boost --env-vars-file="$ROTH_LIVE_ENV_FILE" --update-secrets="STRIPE_SECRET_KEY=STRIPE_SECRET_KEY:3,WEBSITE_ROTH_OTP_SECRET=WEBSITE_ROTH_LIVE_OTP_SECRET:$ROTH_LIVE_OTP_VERSION,WEBSITE_ROTH_WEBHOOK_SECRET=WEBSITE_ROTH_LIVE_WEBHOOK_SECRET:$ROTH_LIVE_WEBHOOK_VERSION,RESEND_API_KEY=RESEND_API_KEY:22" --allow-unauthenticated
curl --fail --silent --show-error https://circum-website-roth-live-516426305461.us-central1.run.app/health > "$TMP/health.json"
node - "$TMP/health.json" "$SHA" <<'NODE'
const h=JSON.parse(require('fs').readFileSync(process.argv[2]));if(h.environment!=='live'||h.sourceSHA!==process.argv[3]||!h.ok||!h.isolationVerified||h.publicPurchasesEnabled!==false)throw Error('Restricted LIVE runtime failed health gate');
NODE
for SERVICE in circum-stripe-webhook-live circum-transactional-email; do
 if [[ "$SERVICE" == circum-stripe-webhook-live ]]; then OVERLAY="$WEBHOOK_IMAGE"; else OVERLAY="$EMAIL_IMAGE"; fi
 REVISION="$SERVICE-roth-${SHA:0:12}"
 gcloud run deploy "$SERVICE" --project=circum-2797c --region=us-central1 --image="$OVERLAY" --revision-suffix="roth-${SHA:0:12}" --update-env-vars="CIRCUM_ROTH_GUARD_SHA=$SHA" --no-traffic
 gcloud run revisions describe "$REVISION" --project=circum-2797c --region=us-central1 --format=json > "$TMP/revision.json"
 node - "$TMP/revision.json" "$SHA" <<'NODE'
const r=JSON.parse(require('fs').readFileSync(process.argv[2]));if(!r.status.conditions.some(c=>c.type==='Ready'&&c.status==='True')||!r.spec.containers[0].env.some(e=>e.name==='CIRCUM_ROTH_GUARD_SHA'&&e.value===process.argv[3]))throw Error('Scoped owner revision identity or readiness mismatch');
NODE
 gcloud run services update-traffic "$SERVICE" --project=circum-2797c --region=us-central1 --to-revisions="$REVISION=100"
done
python3 scripts/verify_roth_test_containment.py
