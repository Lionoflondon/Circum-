#!/usr/bin/env python3
"""Preserve healthy owners; patch only ROTH delegation and receipt exclusion."""
import hashlib,json,subprocess
from pathlib import Path
WEBHOOK_BASE='f0c24ebc763552f832c26838f14f4c679aa654d7'
EMAIL_BASE='b4b21042498793b3d2515adf7b22444ff1b1c60d'
root=Path(__file__).resolve().parents[1]
def source(sha,name):
    if subprocess.run(['git','cat-file','-e',sha+'^{commit}'],cwd=root,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode:
        subprocess.run(['git','fetch','origin',sha],cwd=root,check=True)
    return subprocess.check_output(['git','show',f'{sha}:server/functions/{name}'],cwd=root,text=True)
core=source(WEBHOOK_BASE,'stripe-webhook-core.js')
anchor='    if (["customer.subscription.created", "customer.subscription.updated", "customer.subscription.deleted"].includes(event.type)) {'
assert core.count(anchor)==1
addition='''    // Dedicated website LIVE owner; other payment routes retain their published implementation.
    const websiteMetadata = event.data?.object?.metadata || {};
    if (["checkout.session.completed", "checkout.session.async_payment_succeeded", "checkout.session.async_payment_failed", "checkout.session.expired", "payment_intent.succeeded", "payment_intent.processing", "payment_intent.payment_failed", "payment_intent.canceled", "charge.succeeded", "charge.failed"].includes(event.type) && event.livemode && runtimeConfig.mode === "live" && websiteMetadata.type === "website_roth_top_up" && websiteMetadata.websiteRealm === "live" && !websiteMetadata.testDatabase) {
      return finish({success: true, delegated: "website_roth_live"}, "website_roth_live_delegated");
    }

'''
patched_core=core.replace(anchor,addition+anchor)
assert patched_core.replace(addition,'')==core
publisher=source(EMAIL_BASE,'transactional-email-publishers.js')
addition_email='    if (lower(after.metadata && after.metadata.source) === "website_roth") return {status: "ignored", reason: "website_roth_has_dedicated_receipt", eventId};\n'
current=(root/'server/functions/transactional-email-publishers.js').read_text()
assert current.count(addition_email)==1 and current.replace(addition_email,'')==publisher, 'Unrelated publisher changes require separate review'
out=root/'server/functions'
(out/'stripe-webhook-core.roth-live-overlay.js').write_text(patched_core)
(out/'transactional-email-publishers.roth-live-overlay.js').write_text(current)
for name,file,target in [('webhook','stripe-webhook-core.roth-live-overlay.js','stripe-webhook-core.js'),('email','transactional-email-publishers.roth-live-overlay.js','transactional-email-publishers.js')]:
    (out/f'Dockerfile.roth-live-{name}-overlay').write_text('ARG BASE_IMAGE\nFROM ${BASE_IMAGE}\nARG ROTH_GUARD_SHA\nARG EXPECTED_SOURCE_HASH\nRUN node -e \"const fs=require(\\\"fs\\\"),crypto=require(\\\"crypto\\\");if(crypto.createHash(\\\"sha256\\\").update(fs.readFileSync(\\\"/app/'+target+'\\\")).digest(\\\"hex\\\")!==process.env.EXPECTED_SOURCE_HASH)throw Error(\\\"Published owner source drift\\\")\"\nCOPY '+file+' /app/'+target+'\nENV CIRCUM_ROTH_GUARD_SHA=$ROTH_GUARD_SHA\n')
proof={'webhookBase':WEBHOOK_BASE,'emailBase':EMAIL_BASE,'webhookOriginalHash':hashlib.sha256(core.encode()).hexdigest(),'webhookPatchedHash':hashlib.sha256(patched_core.encode()).hexdigest(),'emailOriginalHash':hashlib.sha256(publisher.encode()).hexdigest(),'emailPatchedHash':hashlib.sha256(current.encode()).hexdigest(),'unrelatedSourcePreserved':True}
(out/'roth-live-overlay-proof.json').write_text(json.dumps(proof,indent=2)+'\n')
print(json.dumps(proof))
