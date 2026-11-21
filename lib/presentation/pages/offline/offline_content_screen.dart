import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/service_locator.dart';
import '../../../l10n/app_localizations.dart';
import '../../cubits/offline_search/offline_search_cubit.dart';
import '../../widgets/app_main_drawer_widget.dart';
import '../../widgets/app_scaffold_with_offline.dart';
import '../../widgets/app_main_header_widget.dart';
import '../../widgets/offline_content_body.dart';
import '../../mixins/offline_management_mixin.dart';

class OfflineContentScreen extends StatefulWidget {
  const OfflineContentScreen({super.key});

  @override
  State<OfflineContentScreen> createState() => _OfflineContentScreenState();
}

class _OfflineContentScreenState extends State<OfflineContentScreen>
    with OfflineManagementMixin<OfflineContentScreen> {
  late OfflineSearchCubit _offlineSearchCubit;

  @override
  void initState() {
    super.initState();
    _offlineSearchCubit = getIt<OfflineSearchCubit>();
    if (_offlineSearchCubit.state is OfflineSearchInitial) {
      _offlineSearchCubit.getAllOfflineContent();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return BlocProvider<OfflineSearchCubit>.value(
      value: _offlineSearchCubit,
      child: BlocBuilder<OfflineSearchCubit, OfflineSearchState>(
        builder: (context, state) {
          return AppScaffoldWithOffline(
            title: AppLocalizations.of(context)!.offlineContent,
            appBar: AppMainHeaderWidget(
              isOffline: true,
              offlineStats: _offlineSearchCubit.getOfflineStats(),
              onRefresh: () => _offlineSearchCubit.forceRefresh(),
              onImport: () => importFromBackup(context),
              onImportZip: () => importFromZip(context),
              title: AppLocalizations.of(context)!.offlineContent,
              isListMode: state is OfflineSearchLoaded
                  ? state.isListMode
                  : false,
              onToggleViewMode: () => _offlineSearchCubit.toggleViewMode(),
            ),
            backgroundColor: colorScheme.surface,
            drawer: AppMainDrawerWidget(context: context),
            body: const OfflineContentBody(),
          );
        },
      ),
    );
  }
}
