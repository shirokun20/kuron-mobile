import 'package:kuron_special/kuron_special.dart';
import 'package:kuron_native/kuron_native.dart';
import '../base/base_cubit.dart';

part 'crotpedia_auth_state.dart';

class CrotpediaAuthCubit extends BaseCubit<CrotpediaAuthState> {
  final WebViewSessionAdapter _adapter;

  CrotpediaAuthCubit({
    required WebViewSessionAdapter adapter,
    required super.logger,
  })  : _adapter = adapter,
        super(initialState: CrotpediaAuthInitial());

  Future<void> checkLoginStatus() async {
    if (isClosed) return;
    try {
      // Only check local state — no HTTP request (avoids CF block on Dio)
      if (_adapter.isLoggedIn) {
        emit(CrotpediaAuthSuccess(_adapter.username ?? 'User'));
      } else {
        emit(CrotpediaAuthInitial());
      }
    } catch (e) {
      logger.e('Failed to check login status', error: e);
      if (!isClosed) emit(CrotpediaAuthInitial());
    }
  }

  Future<void> login(String email, String password, bool rememberMe) async {
    if (isClosed) return;
    emit(CrotpediaAuthLoading());
    try {
      final result = await _adapter.login(
        email: email,
        password: password,
        rememberMe: rememberMe,
      );

      if (isClosed) return;
      if (result.success) {
        emit(CrotpediaAuthSuccess(result.username ?? email.split('@').first));
      } else {
        emit(CrotpediaAuthError(result.errorMessage ?? 'Login failed'));
      }
    } catch (e) {
      logger.e('Login error', error: e);
      if (!isClosed) {
        emit(const CrotpediaAuthError(
            'An unexpected error occurred during login'));
      }
    }
  }

  Future<void> externalLogin(String username, List<String> rawCookies) async {
    if (isClosed) return;
    emit(CrotpediaAuthLoading());
    try {
      await _adapter.setExternalLogin(
          username: username, rawCookies: rawCookies);
      if (!isClosed) emit(CrotpediaAuthSuccess(username));
    } catch (e, s) {
      logger.e('External login error: $e\n$s');
      if (!isClosed) {
        emit(const CrotpediaAuthError('Failed to capture session'));
      }
    }
  }

  Future<void> logout() async {
    // Always clear adapter even if cubit is closed
    try {
      await _adapter.logout();
      await KuronNative.instance.clearCookies();
    } catch (e) {
      logger.e('Logout error', error: e);
    }
    if (isClosed) return;
    emit(CrotpediaAuthInitial());
  }
}
