import 'dart:async';

import 'package:nhasixapp/presentation/cubits/base/base_cubit.dart';
import 'package:nhasixapp/core/services/source_auth_service.dart';

part 'source_auth_state.dart';

class SourceAuthCubit extends BaseCubit<SourceAuthState> {
  final SourceAuthService _sourceAuthService;

  void _emitSafe(SourceAuthState nextState) {
    if (isClosed) return;
    emit(nextState);
  }

  SourceAuthCubit({
    required this._sourceAuthService,
    required super.logger,
  })  : super(initialState: const SourceAuthState.initial());
  ({String url, String? autoCloseCookie, List<String>? successFilters})?
      getLoginUrls(String sourceId) {
    return _sourceAuthService.getLoginUrls(sourceId);
  }

  Future<void> saveWebViewSession({
    required String sourceId,
    required List<String> cookies,
    required String? cookieName,
  }) async {
    await _sourceAuthService.saveWebViewSession(
      sourceId: sourceId,
      cookies: cookies,
      cookieName: cookieName,
    );
    await initialize(sourceId);
  }


  Future<void> initialize(String sourceId) async {
    _emitSafe(state.copyWith(
      sourceId: sourceId,
      loading: true,
      clearError: true,
      authenticated: false,
      clearAccountName: true,
      clearProfileEmail: true,
      clearProfileSlug: true,
      loginFlowActive: false,
      loginFlowSuccess: false,
      loginFlowProgress: 0,
      clearLoginFlowMessage: true,
    ));

    try {
      var hasSession = await _sourceAuthService.hasSession(sourceId);
      SourceAuthBootstrap? bootstrap;
      if (!hasSession) {
        bootstrap = await _sourceAuthService.bootstrap(sourceId);
      }
      var accountName = hasSession
          ? await _sourceAuthService.getSessionDisplayName(sourceId)
          : null;
      String? profileEmail;
      String? profileSlug;

      if (hasSession) {
        try {
          final profile = await _sourceAuthService.getUserProfile(sourceId);
          final profileUsername = profile['username']?.toString().trim();
          accountName = (profileUsername != null && profileUsername.isNotEmpty)
              ? profileUsername
              : accountName;
          final email = profile['email']?.toString().trim();
          final slug = profile['slug']?.toString().trim();
          profileEmail = (email != null && email.isNotEmpty) ? email : null;
          profileSlug = (slug != null && slug.isNotEmpty) ? slug : null;
        } catch (e) {
          if (_isSessionExpiredError(e)) {
            hasSession = false;
            accountName = null;
            profileEmail = null;
            profileSlug = null;
            bootstrap ??= await _sourceAuthService.bootstrap(sourceId);
          } else {
            profileEmail = null;
            profileSlug = null;
          }
        }
      }

      _emitSafe(state.copyWith(
        loading: false,
        authenticated: hasSession,
        accountName: accountName,
        captchaProvider: bootstrap?.captchaProvider,
        captchaSiteKey: bootstrap?.captchaSiteKey,
        captchaBaseUrl: bootstrap?.captchaBaseUrl,
        powChallenge: bootstrap?.powChallenge,
        powDifficulty: bootstrap?.powDifficulty,
        clearCaptchaInfo: hasSession,
        clearPowInfo: hasSession,
        profileEmail: profileEmail,
        profileSlug: profileSlug,
        clearError: true,
        loginFlowActive: false,
        loginFlowSuccess: false,
        loginFlowProgress: 0,
        clearLoginFlowMessage: true,
      ));
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'initialize');
      _emitSafe(state.copyWith(
        loading: false,
        authenticated: false,
        errorMessage: e.toString(),
        loginFlowActive: false,
        loginFlowSuccess: false,
        loginFlowProgress: 0,
        clearLoginFlowMessage: true,
      ));
    }
  }

  Future<void> login({
    required String username,
    required String password,
    required String captchaResponse,
  }) async {
    final sourceId = state.sourceId;
    if (sourceId.isEmpty) {
      _emitSafe(state.copyWith(errorMessage: 'Source is not initialized'));
      return;
    }

    _emitSafe(state.copyWith(
      loading: true,
      clearError: true,
      loginFlowActive: true,
      loginFlowSuccess: false,
      loginFlowProgress: 0.1,
      loginFlowMessage: 'source_auth.flow.preparing_session',
    ));

    try {
      _emitSafe(state.copyWith(
        loginFlowProgress: 0.35,
        loginFlowMessage: 'source_auth.flow.solving_challenge',
      ));

      await _sourceAuthService.login(
        sourceId: sourceId,
        username: username,
        password: password,
        captchaResponse: captchaResponse,
      );

      _emitSafe(state.copyWith(
        loginFlowProgress: 0.72,
        loginFlowMessage: 'source_auth.flow.fetching_profile',
      ));

      String? accountName = username;
      String? profileEmail;
      String? profileSlug;
      try {
        final profile = await _sourceAuthService.getUserProfile(sourceId);
        final profileUsername = profile['username']?.toString().trim();
        accountName = (profileUsername != null && profileUsername.isNotEmpty)
            ? profileUsername
            : username;
        final email = profile['email']?.toString().trim();
        final slug = profile['slug']?.toString().trim();
        profileEmail = (email != null && email.isNotEmpty) ? email : null;
        profileSlug = (slug != null && slug.isNotEmpty) ? slug : null;
      } catch (e) {
        if (_isSessionExpiredError(e)) {
          rethrow;
        }
      }

      _emitSafe(state.copyWith(
        loading: false,
        authenticated: true,
        accountName: accountName,
        profileEmail: profileEmail,
        profileSlug: profileSlug,
        clearCaptchaInfo: true,
        clearPowInfo: true,
        clearError: true,
        loginFlowActive: true,
        loginFlowSuccess: true,
        loginFlowProgress: 1,
        loginFlowMessage: 'source_auth.flow.login_success',
      ));
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'login');
      _emitSafe(state.copyWith(
        loading: false,
        authenticated: false,
        errorMessage: e.toString(),
        loginFlowActive: false,
        loginFlowSuccess: false,
        loginFlowProgress: 0,
        clearLoginFlowMessage: true,
      ));
    }
  }

  void clearLoginFlowState() {
    _emitSafe(state.copyWith(
      loginFlowActive: false,
      loginFlowSuccess: false,
      loginFlowProgress: 0,
      clearLoginFlowMessage: true,
    ));
  }

  Future<void> logout() async {
    if (state.sourceId.isEmpty) return;

    final sourceId = state.sourceId;

    _emitSafe(state.copyWith(
      loading: true,
      clearError: true,
      authenticated: false,
      clearAccountName: true,
      clearProfileEmail: true,
      clearProfileSlug: true,
      clearCaptchaInfo: true,
      clearPowInfo: true,
      loginFlowActive: false,
      loginFlowSuccess: false,
      loginFlowProgress: 0,
      clearLoginFlowMessage: true,
    ));

    try {
      await _sourceAuthService.logout(sourceId);
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'logout');
    }

    // Always rebuild auth state from storage/config even if remote logout fails,
    // because local session was already cleared by the auth client.
    await initialize(sourceId);
  }

  Future<void> refreshProfile() async {
    if (state.sourceId.isEmpty || !state.authenticated) return;

    try {
      final profile = await _sourceAuthService.getUserProfile(state.sourceId);
      final profileUsername = profile['username']?.toString().trim();
      final email = profile['email']?.toString().trim();
      final slug = profile['slug']?.toString().trim();

      _emitSafe(state.copyWith(
        accountName: (profileUsername != null && profileUsername.isNotEmpty)
            ? profileUsername
            : state.accountName,
        profileEmail: (email != null && email.isNotEmpty) ? email : null,
        profileSlug: (slug != null && slug.isNotEmpty) ? slug : null,
        clearError: true,
      ));
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'refreshProfile');
      if (_isSessionExpiredError(e)) {
        await initialize(state.sourceId);
        return;
      }
      _emitSafe(state.copyWith(errorMessage: e.toString()));
    }
  }

  bool _isSessionExpiredError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('session expired') ||
        text.contains('unauthorized') ||
        text.contains('401') ||
        text.contains('403');
  }
}
