import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_native/kuron_native.dart';

// Production [ClearanceDriver]: solves challenges through the native
// WebView (headless first, visible fallback). The orchestration
// (caching, persistence, retry) lives in kuron_generic's ClearanceService.
class NativeClearanceDriver implements ClearanceDriver {
  const NativeClearanceDriver();

  @override
  Future<ClearanceSolution?> solve(String domainUrl) async {
    final result = await KuronNative.instance.getHeadlessClearance(
      url: domainUrl,
    );

    if (result != null) {
      final crt = result['token'] as String?;
      if (crt != null && crt.isNotEmpty) {
        return ClearanceSolution(
          token: crt,
          userAgent: result['userAgent'] as String?,
          cookies: result['cookies'] as String?,
        );
      }
    }

    final fallbackResult = await KuronNative.instance.showLoginWebView(
      url: domainUrl,
      pageFinishedScript: "window.localStorage.getItem('clearance')",
    );

    if (fallbackResult != null) {
      final scriptResult =
          fallbackResult['pageFinishedScriptResult'] as String?;
      final userAgent = fallbackResult['userAgent'] as String?;

      String? cookies;
      final cookiesData = fallbackResult['cookies'];
      if (cookiesData is List) {
        cookies = cookiesData.join('; ');
      } else if (cookiesData is String) {
        cookies = cookiesData;
      }

      // the script result might be wrapped in quotes
      final crt = scriptResult?.replaceAll('"', '');
      if (crt != null && crt != 'null' && crt.isNotEmpty) {
        return ClearanceSolution(
          token: crt,
          userAgent: userAgent,
          cookies: cookies,
        );
      }
    }

    return null;
  }
}
