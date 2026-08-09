# CIRCUM operational data retention recommendations

Status: recommendation only. No deletion or TTL policy is enabled by this change.

| Data | Operational purpose | Recommended online period | Recommended later treatment |
| --- | --- | --- | --- |
| Delivery timeline | Lifecycle, disputes, payment and completion audit | 7 years for financial deliveries | Retain append-only; archive only under an approved legal policy |
| Delivery GPS samples | Active operations, route evidence and disputes | 90 days at full resolution | Reduce or archive after dispute window; retain immutable route facts |
| Notification attempts | Delivery proof and reliability diagnosis | 12 months | Aggregate reliability metrics before expiry |
| Chat messages | Delivery coordination and support evidence | 24 months after delivery | Legal/privacy review before deletion |
| Delivery evidence | Completion, claims and regulated custody | 7 years where required, otherwise policy-defined | Keep authorization and evidence metadata aligned |
| Admin and financial audit | Security, settlement and operator accountability | 7 years minimum | Append-only; never TTL independently of related financial records |
| Operational incidents | Reliability, SLA and intervention history | 24 months online | Preserve aggregate trends after archival |

Any future retention job must be server-owned, idempotent, bounded, observable,
and approved by Legal/Privacy before production activation.
