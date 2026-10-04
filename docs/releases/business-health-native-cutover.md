# Business and Health+ native transport: next release source gate

This change is source preparation only. Do not build, upload, attach or submit iOS/Android artifacts as part of this change.

The next Sender iOS and Android artifacts must be built from canonical main containing the native Business/Health transport change and backend PR #550 (26f1fcfda07faeec0ca2836331bd2be081fe5655). Reusing previously generated Sender artifacts does not include this transport change.

The 24 reviewed operations in `businessHealthCallableUrls` call the existing standalone Business invoice, Business Roth and Health+ owners directly. Native Business repository, Health+ booking/schedule and Operations controls use that transport. Other Firebase callables retain their existing transport. The response adapter preserves callable result/data and FirebaseFunctionsException semantics, including error details. Auth and existing required App Check contracts are preserved. Ambiguous timeout/connection/provider outcomes are not retried and never fall back to the original SDK URLs.

Rider has no callers to these 24 Business/Health operations. Its Health+ jobs continue through its existing delivery-authority path. The next Rider artifacts must contain canonical Rider main `7dd17fe103bc9948c4148184edd7466a13122a2a` or a descendant, including the merged location-permission, earnings and branded verification changes from PRs #126-#130. Re-fetch main before any later release.

For the next artifact batch, preserve live Stripe/Apple Pay merchant configuration, iOS Maps key injection, production App Attest/APNs, Android signing/payment configuration and Rider location declarations. This PR changes none of those settings or build numbers. Verify each produced artifact separately when builds are authorized.

Source tests and server-side QA do not certify an installed native app. On the next builds, verify real platform App Check plus Business access, booking/schedule controls, role denials, verified-email flows and safe payment re-entry after interruption. Use approved TEST fixtures; do not create real charges or clinical deliveries for certification. Rider go-online/location and earnings UI require separate device checks. Record source SHA, artifact digest, installed build and cleanup evidence. Original legacy SDK migration failure is not a reason to retry managed Gen 1 deployment for these client operations.
