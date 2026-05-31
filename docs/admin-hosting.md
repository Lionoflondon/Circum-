# Admin Hosting

Circum has two Firebase Hosting targets in this repository.

## Hosting targets

- `main`: customer-facing web app, intended for `circumuk.com`.
- `admin`: internal operations app, intended for `admin.circumuk.com`.

The admin panel is not exposed through the public customer app. The public build ignores `?app=admin` and only the admin hosting build enables the operations panel through the compile-time flag `CIRCUM_ADMIN_HOSTING=true`.

## Firebase setup

`.firebaserc` maps:

- `main` to Firebase Hosting site `circum-app-2797c`
- `admin` to Firebase Hosting site `circum-admin-2797c`

If the admin site does not exist yet, create it once:

```bash
../firebase hosting:sites:create circum-admin-2797c --project circum-2797c
```

Then connect `admin.circumuk.com` to the `circum-admin-2797c` site in Firebase Hosting and add the DNS records Firebase provides.

## Deploy commands

Deploy customer app only:

```bash
scripts/deploy_main_web.sh
```

Deploy admin app only:

```bash
scripts/deploy_admin_web.sh
```

Deploy both:

```bash
scripts/deploy_all_web.sh
```

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

Important admin actions write an `adminAuditLogs` record from the operations panel.

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
