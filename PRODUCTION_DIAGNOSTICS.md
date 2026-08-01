# Production Diagnostics

## Sender Web Startup Sequence

Sender Web records these startup stages:

1. Flutter initialization
2. Firebase.initializeApp()
3. Firebase Auth initialization
4. Firestore initialization
5. Callable initialization
6. App Check initialization
7. runApp()
8. Router construction
9. First frame rendered

Each record includes stage, status, timestamp, build hash, release tag, browser,
platform, exception, and stack trace when available.

## Error Capture Pipeline

Sender Web installs:

- `runZonedGuarded`
- `FlutterError.onError`
- `PlatformDispatcher.instance.onError`
- `window.onerror` on web
- `window.onunhandledrejection` on web

Diagnostics are recorded in memory and must never crash startup. Unexpected
errors still flow through Flutter's normal error presentation.

## Startup Recovery

If Sender Web fails before the first frame, customers see:

> We're having trouble starting Circum.
>
> Please try again.
>
> If the problem continues, contact support.

The recovery screen does not expose technical details. The Retry button attempts
the startup sequence again.

## Runtime Health Checklist

The internal runtime health panel is compile-time gated. It appears only in
debug builds or when the release is built with:

```bash
--dart-define=CIRCUM_WEB_DIAGNOSTICS_PANEL=true
```

The panel reports:

- Build hash
- Release tag
- Firebase initialized
- App Check state
- Auth initialized
- Authenticated
- Firestore connected
- Functions connected
- Maps ready
- Stripe ready
- Startup failure count

Do not enable the panel for ordinary production traffic.

## App Check Troubleshooting

For Sender Web, verify:

- The build receives `CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY`.
- The bundled site key belongs to the Sender Firebase Web App.
- The key is a reCAPTCHA Enterprise key.
- The key allows `circum-app-2797c.web.app`.
- The Firebase project is `circum-2797c`.
- App Check enforcement is expected for protected Firebase services.
- Token exchange succeeds in Chrome, Safari, Edge, and incognito.

Classify failures as:

- Expected warning: transient token refresh, blocked third-party script, or a
  signed-out request that recovers without blocking the app.
- Recoverable failure: App Check token retrieval fails after first frame but the
  user can retry or continue to non-protected UI.
- Blocking failure: App Check activation fails before protected Sender runtime
  can start. The recovery screen must render.

Never disable App Check to resolve a production incident.

## Release Source Maps

Sender Web release builds generate source maps but do not publish them.

The build script archives maps to:

```text
build/release_symbols/sender_app_web/<gitCommit>/
```

The public artifact removes `*.map` files and strips the public
`sourceMappingURL` reference from `main.dart.js`.

Archive the symbol directory with the release tag. Access should be limited to
engineering incident responders.

## Symbolication

1. Identify the deployed build hash from `circum-surface.json`.
2. Locate the matching archive:

```text
build/release_symbols/sender_app_web/<gitCommit>/main.dart.js.map
```

3. Use Chrome DevTools or an internal source-map tool to map
   `main.dart.js` stack frames back to Dart source.
4. Attach the original Dart file, line, exception, browser, and release tag to
   the incident record.

If the source map archive is missing, do not infer a Dart line from minified
JavaScript alone.
