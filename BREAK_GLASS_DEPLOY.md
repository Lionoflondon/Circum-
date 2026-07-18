# Break-Glass Deployment

Break-glass deployment is allowed only for a production incident where CI deployment is unavailable and delaying deployment materially worsens customer impact.

Requirements:

- Incident ticket or incident channel reference.
- Two-person approval before credentials are used.
- Elevated credentials issued only for the incident window.
- Full command log retained.
- Exact commit SHA recorded before deployment.
- Exact Firebase project and target recorded before deployment.
- Post-incident review within one business day.
- Standing emergency credentials must not remain on developer laptops.

Break-glass does not bypass product isolation. The deployment guard must still run unless the incident is specifically that the guard infrastructure is unavailable.
