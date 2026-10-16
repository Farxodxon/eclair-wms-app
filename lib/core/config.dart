import 'package:wms_app/core/api_client.dart';

/// Server manzili - bulut (Render). Build vaqtida ustidan yozish mumkin:
/// `--dart-define=API_BASE_URL=https://example.onrender.com`
const String _defaultServerUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://eclair-wms-app.onrender.com',
);

/// Joriy server manzili. Faqat bulut - local server yo'q.
final String apiBaseUrl = _defaultServerUrl;

/// main() da, runApp'dan OLDIN chaqiriladi.
void initServerConfig() {
  ApiClient.setBaseUrl(apiBaseUrl);
}
