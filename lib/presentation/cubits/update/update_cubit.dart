import '../../../../core/services/update_service.dart';
import '../base/base_cubit.dart';
import 'update_state.dart';

class UpdateCubit extends BaseCubit<UpdateState> {
  final UpdateService _updateService;

  UpdateCubit({
    required this._updateService,
    required super.logger,
  })  : super(initialState: UpdateInitial());

  Future<void> checkForUpdate({bool isManual = false}) async {
    if (state is UpdateChecking) return;

    try {
      emit(UpdateChecking());

      final updateInfo = await _updateService.checkForUpdate();

      if (updateInfo != null) {
        emit(UpdateAvailable(updateInfo));
      } else {
        emit(UpdateNotAvailable(isManualCheck: isManual));
      }
    } catch (e) {
      logger.e('UpdateCubit: Error checking for update', error: e);
      emit(UpdateError(e.toString(), isManualCheck: isManual));
    }
  }
}
