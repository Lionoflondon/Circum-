#!/usr/bin/env bash
set -euo pipefail
# Website TEST runtime and the required canonical TEST delegation guard only.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
: "${ROTH_CONTAINMENT_BASELINE:?Reviewed containment baseline required}"
python3 scripts/verify_roth_test_containment.py
SHA="${1:?Pass the approved merged main SHA}"
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || exit 64
git fetch origin main
git merge-base --is-ancestor "$SHA" origin/main
[[ "$(git rev-parse origin/main)" == "$SHA" ]] || { echo "Use exact current main." >&2; exit 1; }
: "${ROTH_TEST_ENV_FILE:?Private env YAML required}"
: "${ROTH_TEST_IMAGE_REPOSITORY:?Existing Artifact Registry repository required}"
: "${ROTH_TEST_OTP_VERSION:?Pinned dedicated OTP version required}"
: "${ROTH_TEST_WEBHOOK_VERSION:?Pinned dedicated TEST endpoint secret version required}"
[[ "$ROTH_TEST_IMAGE_REPOSITORY" == us-central1-docker.pkg.dev/circum-2797c/* ]] || exit 64
node - "$ROTH_TEST_ENV_FILE" <<'NODE'
const fs=require('fs');
const text=fs.readFileSync(process.argv[2],'utf8');
for(const [key,value] of Object.entries({WEBSITE_ROTH_ENABLED:'true',WEBSITE_ROTH_LIVE:'false',STRIPE_MODE:'test',FIRESTORE_DATABASE_ID:'roth-website-test'})) {
 const m=new RegExp('^'+key+': *["\x27]?([^"\x27\n]+)["\x27]? *$', 'm').exec(text);
 if(!m || m[1].trim()!==value) throw Error('Invalid TEST binding: '+key);
}
if(!/^WEBSITE_ROTH_TEST_UIDS: *["\x27]?[^"\x27\n]+/m.test(text)) throw Error('Approved account allowlist required');
if(/STRIPE_SECRET_KEY|WEBHOOK_SECRET|OTP_SECRET|RESEND_API_KEY/.test(text)) throw Error('Secrets must use Secret Manager references');
NODE
gcloud firestore databases describe --database=roth-website-test --project=circum-2797c --format='value(name)' >/dev/null
TMP="$(mktemp -d)"
trap 'git worktree remove --force "$TMP/source" >/dev/null 2>&1 || true; rmdir "$TMP" >/dev/null 2>&1 || true' EXIT
git worktree add --detach "$TMP/source" "$SHA"
cd "$TMP/source"
node scripts/deploy_guard.js --target=backend --base "$SHA"
node --test scripts/website_roth_routes.test.mjs
IMAGE="$ROTH_TEST_IMAGE_REPOSITORY/website-roth-test:$SHA"
gcloud builds submit server/functions --project=circum-2797c --region=us-central1 --config=server/functions/cloudbuild.website-roth.yaml --substitutions="_IMAGE=$IMAGE,_SOURCE_SHA=$SHA"
gcloud run deploy circum-website-roth-test --project=circum-2797c --region=us-central1 --image="$IMAGE" --service-account=circum-website-roth-test@circum-2797c.iam.gserviceaccount.com --min-instances=0 --max-instances=1 --concurrency=8 --cpu=1 --memory=256Mi --timeout=60 --no-cpu-boost --env-vars-file="$ROTH_TEST_ENV_FILE" --update-secrets="STRIPE_SECRET_KEY=STRIPE_SECRET_KEY:2,WEBSITE_ROTH_OTP_SECRET=WEBSITE_ROTH_TEST_OTP_SECRET:$ROTH_TEST_OTP_VERSION,WEBSITE_ROTH_WEBHOOK_SECRET=WEBSITE_ROTH_TEST_WEBHOOK_SECRET:$ROTH_TEST_WEBHOOK_VERSION,RESEND_API_KEY=RESEND_API_KEY:22" --allow-unauthenticated
curl --fail --silent --show-error https://circum-website-roth-test-516426305461.us-central1.run.app/health > "$TMP/health.json"
node - "$TMP/health.json" "$SHA" <<'NODE'
const health=JSON.parse(require('fs').readFileSync(process.argv[2]));
if(!health.ok || !health.isolationVerified || health.environment!=='test' || health.sourceSHA!==process.argv[3])throw Error('TEST runtime health or isolation rejected');
NODE
# Required TEST owner guard: preserve its env/secrets and verify TEST mode first.
gcloud run services describe circum-stripe-webhook --project=circum-2797c --region=us-central1 --format=json > "$TMP/test-owner.json"
node - "$TMP/test-owner.json" <<'NODE'
const fs=require('fs');const s=JSON.parse(fs.readFileSync(process.argv[2]));
const annotations=s.metadata.annotations || {};
if(annotations['run.googleapis.com/scalingMode']==='manual'&&annotations['run.googleapis.com/manualInstanceCount']==='0')throw Error('Suspended owner must not restart');
const env=s.spec.template.spec.containers[0].env;
if(!env.some(e=>e.name==='STRIPE_MODE'&&e.value==='test'))throw Error('Canonical owner must remain TEST');
const key=env.find(e=>e.name==='STRIPE_SECRET_KEY');
if(key?.valueFrom?.secretKeyRef?.name!=='STRIPE_SECRET_KEY'||key.valueFrom.secretKeyRef.key!=='2')throw Error('Unapproved TEST key');
NODE
REVISION="circum-stripe-webhook-roth-${SHA:0:12}"
gcloud run deploy circum-stripe-webhook --revision-suffix="roth-${SHA:0:12}" --project=circum-2797c --region=us-central1 --image="$IMAGE" --command=node --args=cloud-run-stripe-server.js --update-env-vars="CIRCUM_SOURCE_SHA=$SHA,SOURCE_SHA=$SHA" --no-traffic
gcloud run revisions describe "$REVISION" --project=circum-2797c --region=us-central1 --format=json > "$TMP/staged-revision.json"
node - "$TMP/staged-revision.json" "$SHA" <<'NODE'
const revision=JSON.parse(require('fs').readFileSync(process.argv[2]));
if(!revision.status.conditions.some(c=>c.type==='Ready'&&c.status==='True'))throw Error('Staged TEST revision is not ready');
if(!revision.spec.containers[0].env.some(e=>e.name==='CIRCUM_SOURCE_SHA'&&e.value===process.argv[3]))throw Error('Staged TEST revision source mismatch');
NODE
gcloud run services update-traffic circum-stripe-webhook --project=circum-2797c --region=us-central1 --to-revisions="$REVISION=100"


python3 scripts/verify_roth_test_containment.py
