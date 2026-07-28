# Admin Hosting

Circum has isolated Firebase Hosting targets in this repository.

## Hosting targets

- `public`: public website, intended for `circumuk.com`.
- `app`: Sender app web surface, hosted at `circum-app-2797c.web.app`.
- `admin`: internal operations app, hosted at `circum-admin-2797c.web.app`.

The admin panel is not exposed through the public customer app. The Admin build uses `lib/main_admin_web.dart`, writes the `circum-admin-web` surface marker, and is deployed only through the isolated Admin pipeline.

## Firebase setup

`.firebaserc` maps:

- `public` to Firebase Hosting site `circum-2797c`
- `app` to Firebase Hosting site `circum-app-2797c`
- `admin` to Firebase Hosting site `circum-admin-2797c`

If the admin site does not exist yet, create it once:

```bash
../firebase hosting:sites:create circum-admin-2797c --project circum-2797c
```

Then connect `admin.circumuk.com` to the `circum-admin-2797c` site in Firebase Hosting and add the DNS records Firebase provides.

## Deploy commands

Deploy Sender App Web only:

```bash
scripts/deploy_sender_app_web.sh --branch origin/main
```

Deploy Public Web only:

```bash
scripts/deploy_public_web.sh --branch origin/main
```

Deploy admin app only:

```bash
scripts/deploy_admin_web.sh --branch origin/main
```

Broad multi-target web deployment is intentionally unavailable. Production
hosting deployments must run through the isolated deployment pipeline described
in `docs/isolated-deployment-pipeline.md`.

The Admin build requires `CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY` for App Check.

## Admin access

The admin panel uses Firebase Auth. There is no public admin signup. Access is granted only when one of these is present:

- Firebase custom claim: `adminRole`
- Firebase custom claim: `role`
- Firebase custom claim list: `roles`
- Firestore document: `adminUsers/{uid}.roles`

Accepted roles:

- `super_admin`
- `operations_admin`
- `support_agent`
- `finance_admin`
- `driver_manager`

Normal customers, senders, and drivers can sign in but are blocked from the panel if they have no admin role.

## Security rules

`firestore.rules` protects admin-only collections including:

- `adminUsers`
- `adminAuditLogs`
- `adminNotes`
- `supportTickets`
- finance/payment collections
- driver approval and performance management collections

Important admin actions are routed through callable backend authority where available and write an `adminAuditLogs` record. Simple recovery metadata that still uses Firestore rules must remain Admin-only and audited until a dedicated callable is added.

## Testing checklist

- Visit `circumuk.com` and confirm no admin link appears in public navigation.
- Visit `circumuk.com/?app=admin` and confirm the customer build does not open the admin panel.
- Visit `admin.circumuk.com` logged out and confirm the admin login page appears.
- Sign in as a normal sender/customer and confirm access is blocked.
- Sign in as a driver account and confirm access is blocked.
- Sign in as an admin account with one of the approved roles and confirm the dashboard loads.
- Confirm User, Sender, Driver, Delivery, Payment, Support, Metrics, and Audit sections load.
- Perform a safe admin action and confirm an `adminAuditLogs` record is created.
- Deploy Firestore rules only after validating current mobile sender/rider paths against the stricter rules.
