import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/domain/entities/ai_translation.dart'
    show MosaicQuality, TranslationStyle;
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/cubits/ai_settings/ai_settings_cubit.dart';

import 'settings_theme_widgets.dart';
import 'glossary_screen.dart';
import 'provider_manager_screen.dart';

/// AI Translation settings: provider management, target language,
/// translation style, cache clearing, privacy disclosure.
class AiSettingsScreen extends StatelessWidget {
  const AiSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AiSettingsCubit(
        providerRepository: getIt(),
        preferencesRepository: getIt(),
        providerFactory: getIt(),
        cacheRepository: getIt(),
        modelCatalog: getIt(),
        logger: getIt(),
        localizations: AppLocalizations.of(context),
      ),
      child: Scaffold(
        appBar: AppBar(title: const Text('AI Translation')),
        body: const _AiSettingsBody(),
      ),
    );
  }
}

class _AiSettingsBody extends StatelessWidget {
  const _AiSettingsBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return BlocBuilder<AiSettingsCubit, AiSettingsState>(
      builder: (context, state) {
        if (state is AiSettingsLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is AiSettingsError) {
          return Center(child: Text(state.message));
        }
        if (state is! AiSettingsLoaded) {
          return const SizedBox.shrink();
        }
        final cubit = context.read<AiSettingsCubit>();
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            buildSettingsSectionHeader(
              Icons.auto_awesome_outlined,
              'PROVIDERS',
              theme,
            ),
            const SizedBox(height: 12),
            buildSettingsCard([
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: Text(l10n.aiManageProviders),
                subtitle: Text(l10n.aiProvidersSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const ProviderManagerScreen(),
                  ),
                ),
              ),
            ], theme),
            const SizedBox(height: 24),
            buildSettingsSectionHeader(Icons.translate, 'TRANSLATION', theme),
            const SizedBox(height: 12),
            buildSettingsCard([
              buildSettingsDropdownTile<String>(
                context: context,
                title: l10n.aiTargetLanguage,
                subtitle: l10n.aiTargetLangSubtitle,
                value: state.targetLang,
                items: AiSettingsCubit.supportedLanguages
                    .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) cubit.setTargetLanguage(v);
                },
                theme: theme,
              ),
              buildSettingsDivider(theme),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                title: Text(
                  l10n.aiTranslationStyle,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  state.style.instruction,
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: DropdownButton<TranslationStyle>(
                  value: state.style,
                  underline: const SizedBox(),
                  items: TranslationStyle.values
                      .map(
                        (s) => DropdownMenuItem(value: s, child: Text(s.label)),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    if (v == TranslationStyle.kasar) {
                      _confirmKasarStyle(context, cubit, v);
                    } else {
                      cubit.setTranslationStyle(v);
                    }
                  },
                ),
              ),
              buildSettingsDivider(theme),
              SwitchListTile(
                title: Text(l10n.aiSkipSfx),
                subtitle: Text(l10n.aiSkipSfxSubtitle),
                value: state.skipSfx,
                onChanged: (v) => cubit.setSkipSfx(v),
              ),
              buildSettingsDivider(theme),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                title: Text(
                  l10n.aiMosaicQuality,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  l10n.aiMosaicQualitySubtitle,
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: DropdownButton<MosaicQuality>(
                  value: state.mosaicQuality,
                  underline: const SizedBox(),
                  items: MosaicQuality.values
                      .map(
                        (q) => DropdownMenuItem(value: q, child: Text(q.label)),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) cubit.setMosaicQuality(v);
                  },
                ),
              ),
            ], theme),
            const SizedBox(height: 24),
            buildSettingsSectionHeader(
              Icons.privacy_tip_outlined,
              'PRIVACY',
              theme,
            ),
            const SizedBox(height: 12),
            buildSettingsCard([
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: Text(l10n.aiPrivacyDisclosure),
                subtitle: Text(l10n.aiPrivacyDesc),
              ),
              buildSettingsDivider(theme),
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined),
                title: Text(l10n.aiClearCache),
                subtitle: Text(l10n.aiClearCacheSubtitle),
                onTap: () async {
                  await cubit.clearCache();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.aiClearCacheCleared)),
                    );
                  }
                },
              ),
              buildSettingsDivider(theme),
              ListTile(
                leading: const Icon(Icons.bookmarks_outlined),
                title: Text(l10n.aiGlossary),
                subtitle: Text(l10n.aiGlossarySubtitle),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const GlossaryScreen(),
                  ),
                ),
              ),
            ], theme),
          ],
        );
      },
    );
  }

  void _confirmKasarStyle(
    BuildContext context,
    AiSettingsCubit cubit,
    TranslationStyle style,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mode Kasar (18+)'),
        content: const Text(
          'Mode Kasar menggunakan kata-kata keras. Lanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              cubit.setTranslationStyle(style);
            },
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  }
}
