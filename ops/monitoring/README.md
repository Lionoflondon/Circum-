# CIRCUM Operations Monitoring

`apply-circum-operations-monitoring.sh` is the idempotent source for the Operations Brain monitoring baseline.

It provisions:

- five-minute HTTPS uptime checks for Sender, Rider, and Admin Hosting;
- log-based metrics for critical Function, payment, notification, and watchdog failures;
- low-noise Cloud Monitoring alert policies for those failure classes.

The delivery watchdog is deliberately separate from Cloud Monitoring. It reads at most 100 due `deliveryOperationalState` projections every five minutes, rather than scanning deliveries. It writes one deterministic `operationalIncidents` record and one deterministic Admin notification per logical condition. Lifecycle progress resolves the incident while preserving its audit record.

Cloud Monitoring notification channels are environment-owned and are not created by this script because destinations must be approved operational contacts. Alert policies still create visible Cloud Monitoring incidents without a channel. Bind an approved pager/email channel to these policies through the Google Cloud console when an operations destination is available.

Timeline events live under `deliveryRequests/{deliveryId}/timeline`; existing payment, notification, chat, evidence, and lifecycle documents remain the source records. The projection stores only bounded operational metadata and does not duplicate private payloads, photos, messages, or payment details.
