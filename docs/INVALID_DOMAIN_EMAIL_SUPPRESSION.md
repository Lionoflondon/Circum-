# Non-deliverable QA email safeguard

The canonical transactional-email dispatcher terminally suppresses recipients whose normalized domain ends in `.invalid`, including subdomains and an optional DNS root dot. RFC 2606 reserves `.invalid` for names that are certainly invalid: https://www.rfc-editor.org/rfc/rfc2606.html.

Suppression is recorded in `emailQueue` as `status: suppressed` and `failureReason: non_deliverable_domain`, before any Resend invocation. It applies to already queued records and `recipientEmail` legacy records as well as future publishers. Replayed events retain the terminal outcome. Account identity normalization, source validation, provider retry/backoff, and signed provider-failure alerts retain their existing behavior.

This rule does not infer QA status from a person's name or suppress valid-domain QA inboxes. It does not retroactively rewrite sent/bounced history or resend messages. Other domains, including lookalikes ending in `.invalid.com`, remain subject to the normal validation and provider outcome pipeline.

Deployment scope is the existing `circum-transactional-email` owner. Preserve its active runtime dependencies, IAM, internal ingress, sender configuration and secrets. The provider webhook and alert policy require no change. Native applications require no new artifact for this server safeguard.
