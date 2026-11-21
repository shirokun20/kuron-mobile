import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:nhasixapp/core/routing/app_route.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';

import '../../../widgets/widgets.dart';

// Widget displayed when history is empty
class HistoryEmptyWidget extends StatelessWidget {
  const HistoryEmptyWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return EmptyStateWidget(
      title: l10n.noReadingHistory,
      message: l10n.readingHistoryMessage,
      icon: Icons.history,
      onAction: () {
        // Navigate to main/browse screen
        context.go(AppRoute.main);
      },
      actionText: l10n.startReading,
      suggestions: [
        l10n.browsePopularContent,
        l10n.searchSomethingInteresting,
        l10n.checkOutFeaturedItems,
      ],
    );
  }
}
