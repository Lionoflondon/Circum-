# Legacy read endpoint recovery

Four sampled legacy HTTP endpoints still returned provider-level 500s after the first recovery pass. Preserve their native URLs with thin standalone Cloud Run facades, using the authorized temporary registration/detach procedure. Business logic stays on existing owners: Sender payment mode and Roth balance on Sender delivery payments, Rider earnings summary on Rider payouts, Gift Story video download on Gifts payments.

Reuse the original HTTP callable wrappers so Firebase Auth and mandatory App Check retain their original validation and error behavior. Gift Story download retains its original authenticated-participant or guest-token authorization; a guest token cannot select any payment operation. No financial mutation route, ledger calculation, participant authorization or signed-URL policy changes.

Runtime-only exports preserve both the original HTTP wrapper and `.run`, without exposing Firebase deployment metadata. This also keeps previously migrated Business handlers loadable by the existing payment-family server on future builds. Scoped managed deployment excludes these four reads and the previously migrated exports.

Protected CI and private canary checks must pass before owner traffic changes. Existing resource sizes, service accounts, IAM and financial configuration stay intact; disable startup CPU boost rather than reducing resources. Back up each old HTTP-only Function before removing its failed legacy registration. Detach the temporary registration, deploy the reviewed proxy image, verify private health, then restore the original public callable transport with business authorization still enforced by the existing owner. Retain the old owner revisions for rollback.

No native source, release binary or store artifact change is required. This source registry does not certify every remaining managed Function or unrelated scheduled backlog.
