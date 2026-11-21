import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:nhasixapp/core/utils/native_theme_helper.dart';

import 'package:nhasixapp/l10n/app_localizations.dart';

class CaptchaSolverPage extends StatefulWidget {
  final String provider;
  final String siteKey;
  final String? baseUrl;

  const CaptchaSolverPage({
    super.key,
    required this.provider,
    required this.siteKey,
    this.baseUrl,
  });

  @override
  State<CaptchaSolverPage> createState() => _CaptchaSolverPageState();
}

class _CaptchaSolverPageState extends State<CaptchaSolverPage> {
  late final String _resolvedBaseUrl;
  String? _error;
  String? _challengeErrorCode;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolvedBaseUrl = _normalizeBaseUrl(widget.baseUrl);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startNativeCaptcha();
    });
  }

  Future<void> _startNativeCaptcha() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
      _challengeErrorCode = null;
    });

    try {
      final result = await KuronNative.instance.showCaptchaWebView(
        provider: widget.provider,
        siteKey: widget.siteKey,
        baseUrl: _resolvedBaseUrl,
        backgroundColor: NativeThemeHelper.backgroundColorHex,
        textColor: NativeThemeHelper.textColorHex,
      );

      if (!mounted) return;

      final token = result?['token']?.toString().trim() ?? '';
      final success = result?['success'] == true && token.isNotEmpty;
      if (success) {
        context.pop(token);
        return;
      }

      final errorCode = result?['errorCode']?.toString().trim();
      final errorMessage = result?['errorMessage']?.toString().trim();
      setState(() {
        _challengeErrorCode = errorCode?.isEmpty == true ? null : errorCode;
        _error = (errorMessage == null || errorMessage.isEmpty)
            ? AppLocalizations.of(context)!.captchaCancelled
            : errorMessage;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppLocalizations.of(context)!
            .failedToOpenCaptcha(e.toString());
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.solveCaptchaTitle),
        actions: [
          IconButton(
            tooltip: AppLocalizations.of(context)!.reloadChallenge,
            onPressed: _startNativeCaptcha,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.all(12),
              child: Text(
                AppLocalizations.of(context)!.failedToLoadCaptcha(_error ?? ''),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          if (_challengeErrorCode == '110200')
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.all(12),
              child: Text(AppLocalizations.of(context)!.turnstileRejected),
            ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _loading
                      ? AppLocalizations.of(context)!.openingNativeCaptcha
                      : AppLocalizations.of(context)!.tapRefreshToRetry,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _normalizeBaseUrl(String? baseUrl) {
    final value = (baseUrl ?? '').trim();
    if (value.isEmpty) {
      // Keep a safe default when source config does not provide a captcha base URL.
      return 'https://localhost/';
    }

    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return 'https://localhost/';
    }

    return uri.origin;
  }
}
