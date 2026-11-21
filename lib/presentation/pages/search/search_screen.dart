import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/cubits/source/source_cubit.dart';
import 'package:nhasixapp/presentation/cubits/source/source_state.dart';
import 'package:nhasixapp/presentation/pages/search/dynamic_form_search_ui.dart';
import 'package:nhasixapp/presentation/pages/search/search_form_contract_adapter.dart';
import 'package:nhasixapp/presentation/widgets/app_scaffold_with_offline.dart';

class SearchScreen extends StatefulWidget {
  final String? query;

  const SearchScreen({super.key, this.query});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  int _configReloadNonce = 0;

  Key _searchUiKey(String sourceId) => ValueKey('search-ui-$sourceId');

  Future<void> _reloadSearchUi(String sourceId) async {
    setState(() {
      _configReloadNonce++;
    });

    context.read<SourceCubit>().refreshSources();

    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.reloadingSearchFilters)));
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffoldWithOffline(
      title: AppLocalizations.of(context)?.searchTitle ?? 'Search',
      actions: [
        IconButton(
          tooltip: AppLocalizations.of(context)!.reloadSearchUI,
          onPressed: () => _reloadSearchUi(
            context.read<SourceCubit>().state.activeSource?.id ?? 'nhentai',
          ),
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: BlocBuilder<SourceCubit, SourceState>(
        builder: (context, sourceState) {
          final sourceId = sourceState.activeSource?.id ?? 'nhentai';
          final remoteConfig = getIt<RemoteConfigService>();
          final canonicalSearchForm = remoteConfig.getCanonicalSearchForm(
            sourceId,
          );
          final searchForm = remoteConfig.getSearchFormConfig(sourceId);

          //  all sources migrated to searchForm. Priority:
          // 1) Canonical package-side contract → DynamicFormSearchUI
          // 2) Legacy searchForm → DynamicFormSearchUI
          // 3) Fallback
          if (canonicalSearchForm != null) {
            return DynamicFormSearchUI(
              key: _searchUiKey(sourceId),
              config: SearchFormContractAdapter.toSearchFormConfig(
                canonicalSearchForm,
              ),
              sourceId: sourceId,
              canonicalContract: canonicalSearchForm,
              reloadSignal: _configReloadNonce,
            );
          }

          if (searchForm != null) {
            return DynamicFormSearchUI(
              key: _searchUiKey(sourceId),
              config: searchForm,
              sourceId: sourceId,
              reloadSignal: _configReloadNonce,
            );
          }

          return _buildFallbackUI(sourceId);
        },
      ),
    );
  }

  Widget _buildFallbackUI(String sourceId) {
    final l10n = AppLocalizations.of(context)!;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.searchConfigUnavailable(sourceId),
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(l10n.checkInternetOrReload, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _reloadSearchUi(sourceId),
              icon: const Icon(Icons.refresh),
              label: Text(l10n.retrySearch),
            ),
          ],
        ),
      ),
    );
  }
}
