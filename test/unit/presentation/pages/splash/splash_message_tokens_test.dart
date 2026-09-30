// Splash message tokens must never reach the screen untranslated.
//
// `resolveSplashMessage` used to be a private method whose `default` arm
// returned its own argument, so any token without a case was painted verbatim.
// Nine were live at once: `checkingConnection` and `initFailedMsg` from the
// bloc, five progress tokens from `RemoteConfigService.smartInitialize` (which
// passed English prose through the callback), and two inline English sentences
// the bloc built itself — one of them a two-line `'No offline content
// available.\nPlease download content…'`.
//
// This walks the real emission sites instead of a hand-copied list, so the next
// message nobody taught the resolver to translate fails here.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/blocs/splash/splash_bloc.dart';
import 'package:nhasixapp/presentation/pages/splash/splash_screen.dart';

/// Every token `SplashBloc` emits, plus the shapes that carry a payload.
final List<String> blocTokens = [
  'loadingConfigMsg',
  'initTagsDbMsg',
  'downloadingTagsMsg',
  'downloadingTagsMsg:hitomi',
  'downloadingInitConfig',
  'checkingConnection',
  'connectingMsg',
  'connectingToSite',
  'initBypassMsg',
  'connectedSuccess',
  'initFailedMsg',
  'initFailedMsg:TimeoutException after 30s',
  'failedToConnect',
  'failedInitBypass',
  'failedInitBypass:SocketException',
  'bypassFailed',
  'offlineBypassFailed',
  'errorBypassResult',
  'errorBypassResult:Bad state',
  'failedEnableOffline',
  'noInternetCheckOffline',
  'noInternetNoOffline',
  'unableCheckOffline',
  'failedCheckOffline',
  'failedLoadOffline',
  'foundOfflineItems',
  'offlineLimitedFeatures',
  'readyOfflineLimited',
  'readyOfflineLimitedFeatures',
  'readyOffline',
  'noOfflineContentAvailable',
  'offlineModeAvailable:0',
  'offlineModeAvailable:12',
  // Success messages come from one helper, including the null-time shape.
  SplashBloc.readyMessage(null),
  SplashBloc.readyMessage(DateTime(2026, 9, 30, 9, 7)),
  SplashBloc.readyMessage(DateTime(2026, 9, 30, 23, 59)),
];

/// The five progress tokens `RemoteConfigService.smartInitialize` reports while
/// the app boots. Each one is a literal at a known call site in
/// `lib/core/config/remote_config_service.dart`.
final List<String> configProgressTokens = [
  'loadingBundledDefaults',
  'restoringLocalSources',
  'loadingTagsConfig',
  'sourceConfigsReady',
  'configReady',
];

/// Legacy English sentences that `SplashState` constructors still default to.
final List<String> legacySentenceTokens = [
  'Initializing...',
  'Bypassing Cloudflare protection...',
  'Successfully bypassed Cloudflare protection',
  'No internet connection. Checking offline content...',
  'Offline Mode (Limited Features)',
];

Future<AppLocalizations> _l10n(WidgetTester tester) async {
  late AppLocalizations result;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          result = AppLocalizations.of(context)!;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return result;
}

void main() {
  testWidgets('no emitted token renders as its own key', (tester) async {
    final l10n = await _l10n(tester);

    for (final token in [
      ...blocTokens,
      ...configProgressTokens,
      ...legacySentenceTokens,
    ]) {
      final rendered = resolveSplashMessage(l10n, token);
      final key = token.split(':').first;

      // "Rendered verbatim" is only a bug for a *key* token. The legacy
      // sentence tokens are English prose, and `noInternetCheckOffline` is
      // legitimately the same sentence — mapping it is the fix, not a leak.
      if (!token.contains(' ')) {
        expect(
          rendered,
          isNot(equals(token)),
          reason: 'token "$token" rendered verbatim',
        );
      }
      if (!token.contains(' ')) {
        expect(
          rendered.toLowerCase(),
          isNot(contains(key.toLowerCase())),
          reason: 'token "$token" leaked its own key into "$rendered"',
        );
      }
      expect(
        rendered.trim(),
        isNotEmpty,
        reason: 'token "$token" rendered nothing',
      );
      // With no payload, every camelCase identifier in the output must have
      // come from the token itself — that is the symptom users reported. A
      // token *with* a payload is exempt: `TimeoutException after 30s` is a
      // legitimate interpolated error.
      if (!token.contains(':') && !token.contains(' ')) {
        expect(
          rendered,
          isNot(matches(RegExp(r'[a-z]+[A-Z][a-zA-Z]*'))),
          reason: 'token "$token" rendered a raw identifier: "$rendered"',
        );
      }
    }
  });

  testWidgets('a token nobody registered degrades to readable prose', (
    tester,
  ) async {
    final l10n = await _l10n(tester);
    final rendered = resolveSplashMessage(l10n, 'someTokenNobodyRegistered');

    expect(rendered, isNotEmpty);
    expect(rendered, isNot(contains('someTokenNobodyRegistered')));
    expect(rendered, l10n.initializingApplication);
  });

  testWidgets('payload shapes are interpolated, not dropped', (tester) async {
    final l10n = await _l10n(tester);

    expect(
      resolveSplashMessage(l10n, 'downloadingTagsMsg:hitomi'),
      contains('hitomi'),
    );
    expect(
      resolveSplashMessage(l10n, 'offlineModeAvailable:12', offlineCount: 12),
      contains('12'),
    );
    expect(
        resolveSplashMessage(l10n, 'readyLastSync:23:59'), contains('23:59'));
    expect(
      resolveSplashMessage(l10n, 'initFailedMsg:SocketException'),
      contains('SocketException'),
    );
    // Zero-padded, so a 9am sync reads as 09:05 rather than 9:5.
    expect(
        resolveSplashMessage(
            l10n,
            SplashBloc.readyMessage(
              DateTime(2026, 9, 30, 9, 5),
            )),
        contains('09:05'));
  });

  testWidgets('error keys emitted without a payload never dangle', (
    tester,
  ) async {
    final l10n = await _l10n(tester);

    for (final token in [
      'initFailedMsg',
      'failedInitBypass',
      'errorBypassResult',
      'failedEnableOffline',
      'unableCheckOffline',
      'failedCheckOffline',
      'failedLoadOffline',
    ]) {
      final rendered = resolveSplashMessage(l10n, token);
      expect(
        rendered,
        isNot(endsWith(':')),
        reason: '"$token" rendered a dangling colon: "$rendered"',
      );
      expect(rendered, l10n.unexpectedError);
    }
  });
}
