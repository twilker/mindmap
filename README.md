# MindKite

Let ideas fly freely.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Configuring Google Sign-In for Cloud Sync

The Google Drive synchronization provider relies on the platform-specific
configuration that the `google_sign_in` plugin reads at runtime. Provide the
OAuth client information for each platform before attempting to connect a cloud
account:

- **Android:** Download your `google-services.json` from the Google Cloud
  Console and place it next to `android/app/google-services.json`, using the
  `google-services.json.example` template in the same directory as a guide. The
  Google Services Gradle plugin is already wired up and will generate the
  required resources when the real file is present.
- **iOS:** Add your `GoogleService-Info.plist` to `ios/Runner/` (see the
  `GoogleService-Info.plist.example` template). Update the
  `REVERSED_CLIENT_ID` placeholder in `ios/Runner/Info.plist` to match the value
  from your plist so iOS can route the authentication callback correctly.
- **Web:** Edit the `<meta name="google-signin-client_id">` tag in
  `web/index.html` with your web client ID and keep the Google APIs script tag
  (including the inline initializer that calls `gapi.load('client')`) in place
  so the sign-in SDK can hand OAuth tokens to the JavaScript client. In the
  Google Cloud Console enable the **People API** for the same project that hosts
  your OAuth clients; the web SDK issues a profile lookup against it after
  authorization and will return a 403 error if the API is disabled.

Only the public OAuth client IDs are required in the application bundle. Keep
any client secrets on the server side—Google Sign-In on mobile and web uses the
client ID alone to initiate the user consent flow, and the secure tokens are
retrieved through the SDK APIs at runtime.
