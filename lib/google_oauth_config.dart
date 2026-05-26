import 'package:flutter_dotenv/flutter_dotenv.dart';

const String _kDefaultDesktopClientId =
    '178139986306-kqfnv90cdi66r4qn78ir0mmtlg4hg03v.apps.googleusercontent.com';

const String _kDefaultOauthProxyTokenUrl =
    'https://oauth-proxy.hello-sachinthalakshan.workers.dev/oauth/token';

String _envOrDefault(String key, String fallback) {
  try {
    final raw = dotenv.env[key]?.trim();
    if (raw == null || raw.isEmpty || raw.startsWith('YOUR_')) {
      return fallback;
    }
    return raw;
  } catch (_) {
    return fallback;
  }
}

String get kDesktopClientId =>
    _envOrDefault('GOOGLE_OAUTH_CLIENT_ID', _kDefaultDesktopClientId);

String get kGoogleOauthProxyTokenUrl =>
    _envOrDefault('GOOGLE_OAUTH_PROXY_URL', _kDefaultOauthProxyTokenUrl);
