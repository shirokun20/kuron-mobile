import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/constants/colors_const.dart';
import '../../core/constants/design_tokens.dart';
import '../../core/constants/text_style_const.dart';
import '../../core/di/service_locator.dart';
import '../../core/services/streak_widget_sync_service.dart';
import '../../domain/entities/reading_statistics.dart';
import '../../l10n/app_localizations.dart';
import '../cubits/streak/streak_cubit.dart';
import 'kuro_mascot.dart';

// Drawer-docked streak card (variant C). Answers one question —
// "am I still in a streak?" — with the count, Kuro's mood and one mood
// line. Deliberately no checklist and no CTA: the dots and the button
// made the card tall and noisy.
//
// Privacy: streak count and the mascot only. No title,
// cover, tag or source name ever reaches this surface.
class StreakCard extends StatefulWidget {
  const StreakCard({super.key, this.cubit});

  // Injected by tests; production resolves it from getIt and owns its life.
  final StreakCubit? cubit;

  @override
  State<StreakCard> createState() => _StreakCardState();
}

class _StreakCardState extends State<StreakCard> with WidgetsBindingObserver {
  static const double _mascotSize = 68;
  late final StreakCubit _cubit;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final injected = widget.cubit;
    if (injected != null) {
      _cubit = injected;
    } else {
      _cubit = getIt<StreakCubit>()..loadStreak();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // An injected cubit belongs to the caller — closing it here would end its
    // life mid-test.
    if (widget.cubit == null) _cubit.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // Recomputes streak + mood, so a phone whose date moved while the app
        // was closed shows the right face on return instead of yesterday's.
        _cubit.refresh();
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // Last chance to push to the launcher widget before the app may die.
        unawaited(_syncWidget());
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> _syncWidget() {
    final state = _cubit.state;
    return StreakWidgetSyncService.syncWidget(
      ReadingStatistics.streak(
        readingStreak: state.readingStreak,
        lastReadDate: state.lastReadDate,
        readDays: state.readDays,
        totalContentRead: state.totalContentRead,
      ),
      now: state.referenceDate,
    );
  }

  static String _moodCopy(KuroMood mood, AppLocalizations? l10n) {
    if (l10n != null) {
      return switch (mood) {
        KuroMood.happy => l10n.streakMoodHappy,
        KuroMood.reader => l10n.streakMoodReader,
        KuroMood.ghost => l10n.streakMoodGhost,
        KuroMood.cry => l10n.streakMoodCry,
        KuroMood.tsundere => l10n.streakMoodTsundere,
        KuroMood.frozenCry => l10n.streakMoodFrozen,
        KuroMood.waiting => l10n.streakMoodWaiting,
      };
    }
    return switch (mood) {
      KuroMood.happy => 'Kuro senang kamu baca hari ini. Pertahankan!',
      KuroMood.reader => 'Kuro tenggelam di bacaan bareng kamu!',
      KuroMood.ghost => 'Kuro diam-diam nemenin kamu baca hari ini.',
      KuroMood.cry => 'Kuro nangis nungguin kamu baca...',
      KuroMood.tsundere =>
        'Bukan berarti Kuro kangen, tapi udah lama gak buka!',
      KuroMood.frozenCry => 'Kuro membeku kesepian. Yuk lanjut baca!',
      KuroMood.waiting => 'Kuro nunggu kamu buka bacaan.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final kuronColors = Theme.of(context).extension<KuronColors>();
    final l10n = AppLocalizations.of(context);

    return BlocBuilder<StreakCubit, StreakState>(
      bloc: _cubit,
      builder: (context, state) {
        final isCry =
            state.mood == KuroMood.cry || state.mood == KuroMood.frozenCry;
        final defaultBorder =
            kuronColors?.cardBorder ?? colorScheme.outlineVariant;

        // Compact (<240dp, e.g. desktop 240px sidebar): maskot 44 + judul
        // lebih kecil + mood max 2 baris, biar "1 day streak" tidak patah
        // berantakan di kolom sempit. Wide path di bawah tidak berubah.
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 240;
            final mascotSize = compact ? 44.0 : _mascotSize;
            final headlineStyle = compact
                ? TextStyleConst.titleSmall.copyWith(
                    color: colorScheme.onSurface,
                  )
                : TextStyleConst.contentTitle.copyWith(
                    color: colorScheme.onSurface,
                  );
            return Container(
              padding: EdgeInsets.all(
                compact ? DesignTokens.spaceMd : DesignTokens.spaceLg,
              ),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
                border: Border.all(
                  color: isCry ? AppColors.info : defaultBorder,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.local_fire_department_rounded,
                              size: DesignTokens.spaceLg,
                              color: isCry
                                  ? AppColors.info
                                  : colorScheme.primary,
                            ),
                            const SizedBox(width: DesignTokens.spaceXs),
                            Text(
                              '${state.readingStreak}',
                              style: TextStyleConst.contentTitle.copyWith(
                                color: isCry
                                    ? AppColors.info
                                    : colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: DesignTokens.spaceXs),
                            Flexible(
                              child: Text(
                                l10n?.streakDaysConsecutive ?? 'hari beruntun',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: headlineStyle,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: DesignTokens.spaceXs),
                        Text(
                          _moodCopy(state.mood, l10n),
                          maxLines: compact ? 2 : null,
                          overflow: compact
                              ? TextOverflow.ellipsis
                              : TextOverflow.visible,
                          style: TextStyleConst.bodySmall.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spaceSm),
                  RepaintBoundary(
                    child: KuroMascot(
                      key: ValueKey(state.mood),
                      mood: state.mood,
                      size: mascotSize,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
