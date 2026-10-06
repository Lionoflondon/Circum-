# Sender simulator authentication

Build a private debug artifact with signing enabled:

```sh
flutter build ios --simulator --debug
python3 scripts/verify_sender_simulator_keychain.py build/ios/iphonesimulator/Runner.app
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
```

Do not install an unsigned `--no-codesign` artifact for Firebase Auth QA. Xcode must embed the simulator's application identifier and its own Keychain group. Firebase Auth can create an identity remotely and then fail to persist it locally with `keychain-error` / OSStatus -34018. Recover that identity by signing in after rebuilding; do not retry signup automatically or reset its password.

Register a temporary App Check debug token for the Sender iOS Firebase app when testing protected services. Keep the token and debug build private, record the registration identifier privately, and revoke it after QA. Preserve release App Attest / DeviceCheck providers and backend enforcement. Firebase App Check activation alone does not prove token exchange succeeded.

Certify email/password sign-in, sign-out, repeat sign-in, restoration after relaunch, provider invocation, and reachable onboarding. New signup must stop at any legal agreement unless the user separately authorizes acceptance. Provider invocation is not provider authentication completion. No financial or operational actions are part of auth QA.
