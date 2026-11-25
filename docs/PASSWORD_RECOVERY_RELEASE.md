# CIRCUM password recovery

Status: implemented for review; not deployed or production-certified.

## Incident and root cause

The 12 October 2026 reset email followed Website Sender `_sendSenderPasswordReset` -> Firebase client `sendPasswordResetEmail` -> Firebase DEFAULT mail -> `circum-2797c.firebaseapp.com/__/auth/action`. The deployed SHA was checked before this work. This is a missing recovery implementation, not an alternative Resend configuration or a stale branded recovery deployment.

Live Auth configuration read on 13 October confirms DEFAULT email delivery, generic password-reset HTML, Firebase callbackUri, email-enumeration protection enabled and enforced password length 10 to 4096. The custom mail DNS configuration names support.circumuk.com but reports NOT_STARTED. No Auth configuration was modified.

Direct defaults replaced in Circum AuthBloc, Website Sender and Website Rider. Companion Circum-Rider changes replace both ForgotPassword and ResetPassword handlers. Unused legacy new-password/OTP screens now lead to the same email request UI. Installed native binaries need a separately verified release; merging source does not update them.

## Security and delivery contract

* `POST /requestCircumPasswordReset` on existing account-bootstrap is the only signed-out operation. Firebase App Check is mandatory. Existing Auth-required operations keep their boundaries.
* Only email and client (`sender` or `rider`) are accepted. No Auth lookup in the public request path. All syntactically valid identities receive the same `{ok:true}` response; they take the same Firestore transaction regardless of account existence.
* Atomic private request and emailQueue record. Durable per-address 60-second cooldown and 3/hour limit; global 100/hour limit; existing instance-local 30/minute throttle adds a first bound. Rate counters are checked before creating new records. No trusted-IP assumption is introduced.
* Existing private transactional-email dispatcher checks source, age, recipient, disabled state and account identity. Unknown/disabled accounts suppress privately. Requests older than one hour are suppressed before generation or retry.
* Firebase Admin generates the supported reset action, with `returnOobLink`, not a second Firebase email. Only the expected project, mode and opaque code are accepted. The customer URL is `https://circumuk.com/reset-password/#mode=resetPassword&oobCode=...&app=sender|rider`. No API key or Firebase-hosted action URL is included in HTML/plaintext.
* Existing provider lease and Resend idempotency key remain authoritative. The generated message is persisted privately before send and reused byte-for-byte on ambiguous retries; cleared on success/terminal delivery failure. Provider errors are sanitized for recovery. No default-email fallback exists.
* The standalone page strips the fragment before loading dependencies, uses in-memory Auth, no analytics/storage/logging, no-referrer, restrictive CSP and no-store Hosting policy. Firebase verifies/consumes the code and enforces the live password policy. Password confirmation, duplicate-submit guard and expired/reused/invalid terminal states are covered. Return destinations are fixed paths, never arbitrary continue URLs.
* Private request/rate/message documents inherit the Firestore catch-all deny. A dedicated emulator test covers unauthenticated, Sender, Rider and admin client attempts.
* New recovery uses the existing Info Resend identity, existing wordmark and HTML escaping/customer-content checks. It does not change working verification output.

## Other Auth email families

| Family | Evidence and limitation |
| --- | --- |
| Verification | Current callers use authenticated `sendCircumVerificationEmail`, Admin generation, private emailQueue and Resend. Branded template exists. Its underlying action links still use Firebase's handler; visible URL hiding is not a custom handler. Firebase fallback template itself remains generic. |
| Password reset / forgotten password | This change adds the complete branded email and action handler. Existing native versions remain on their old SDK path until released. |
| Email address change | Sender native, Website Sender/Rider and Rider profile use Firebase `verifyBeforeUpdateEmail`. Preserve verification-before-update and recent-login protection. No insecure Admin email replacement. |
| Email change reversal / MFA security | Firebase-managed security emails retain provider issuance and revocation semantics. DEFAULT templates and Firebase callback remain. Full replacement requires distinct verified handlers; the reset-only page must not be set as a global callback. |
| Account deletion | Existing account-closure verified event and central dispatcher remain unchanged. Auth deletion alone is not evidence of email receipt. |

## Readiness, exact scope and rollback

Before deployment, required checks on the exact protected PR heads must pass. Do not ship new callers ahead of the handler and dispatcher.

1. Recheck budget state, active unheld backlog, all 25 original holds, retry manual zero and staged #579 at zero. The user's later instruction authorizes a cap lift if needed, but a Cloud Run budget cannot isolate two named services. It restores Cloud Run across the project. A finite target and safe transition must be resolved before any lift; Functions remains £5 and held queues/schedules remain untouched.
2. The transactional-email service account currently has datastore.user and firebaseauth.viewer. Generation additionally needs `firebaseauth.users.sendEmail`. Grant only that single permission through a reviewed custom project role; retain the existing read role. Do not grant Firebase Auth Admin or change service identity. No IAM mutation has been made by this source change.
3. Deploy existing transactional-email and account-bootstrap images only, preserving every existing environment/secret/service identity/ingress/scale/traffic setting. This change has no functions/index export and must not trigger a broad Functions deployment. Verify existing health and missing-token denial before directing callers to it.
4. Deploy public Hosting, which carries the standalone handler and Website callers, then Sender Web and Rider Web. Rider Web is a separate repository/service. Do not rebuild or upload native stores as an implicit consequence of a web release.
5. Test the authorized recipient, exactly one inbox receipt, correct branded origin, real App Check from signed-out clients, valid/expired/reused links, new login success and old-password rejection. Password entry/submission in browser requires user handoff. iPhone Safari and Android Chrome evidence must come from those devices, not a desktop viewport.
6. Keep prior image digests/Hosting versions as rollback. Roll back clients before removing the new backend operation. Never delete or replay historical queues for rollback.

Production health on 13 October returned HTTP 500, with Cloud Run log text `The request failed because billing is disabled for this project.` Project billingEnabled is true; both service spend caps are ENFORCED at £5. Initial 403 reads were resolved by the proper quota-project header and v1 Budget API. The offline containment checker passes all existing holds/scaling/cap invariants. No queue operation, deployment, credential change, payment, IAM or cap mutation has occurred.

October 13 gate decision, October 20 preservation and October 30 containment review remain unchanged. No backlog preservation is claimed.

## Validation

Focused backend/mail/page/Auth suite: 101 passed before additional rule tests. Sender recovery and auth regressions: 40 passed. Rider transport tests: 8 passed; broader CI remains authoritative. The initial full backend run found two unrelated Business Gifts fixtures pinned to yesterday (12 October); changed only those fixtures to a relative future date, preserving the existing past-date rejection test and runtime logic.

This document must be updated with PR SHAs, final CI, scoped release identity, inbox evidence and device results before certification. Mocks are not production proof.
