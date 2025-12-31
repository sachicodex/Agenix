// Replace these with values from your Google Cloud Console (APIs & Services → Credentials).
// Create a "Desktop" OAuth Client ID for Windows and copy the Client ID value (xxxxx.apps.googleusercontent.com).
// For Android, create an OAuth Client ID of type "Android" and provide package name + SHA-1.
// Note: using the wrong client type (e.g., Web) for desktop can result in OAuth errors like "invalid_client".
const String kAndroidClientId =
    '597556611694-lucfdvikmcfu9e8r64gq10iab6lqknf8.apps.googleusercontent.com';
const String kDesktopClientId =
    '597556611694-fncqigcterhtiedi16j6jk5j0b4kik5c.apps.googleusercontent.com';

// Optional: if you create a Web client for server-side code exchange (for refresh tokens
// on Android via serverAuthCode flow), include that here as well.
const String kWebClientId =
    '597556611694-mebnil2mqeho7a478sbonl3pkqur9gdt.apps.googleusercontent.com';

// Desktop client secret (keep private!). When using Google's "Installed app" (Desktop) flow
// some projects and configurations require the client secret to be included in the token
// exchange request even when PKCE is used. Store this secret securely and **do not** commit
// it to public repositories. For local development it's convenient to keep it here.
const String kDesktopClientSecret = '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';
