import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/constants/design_tokens.dart';
import '../../core/constants/text_style_const.dart';
import '../../l10n/app_localizations.dart';
import '../../core/utils/responsive_grid_delegate.dart';
import '../../domain/entities/entities.dart';
import '../blocs/content/content_bloc.dart';
import '../cubits/settings/settings_cubit.dart';
import '../pages/main/widgets/main_featured_card.dart';
export '../../core/services/content_card_cache_service.dart';
import '../pages/main/widgets/main_grid_card.dart';

extension StringCapitalize on String {
  String get capitalize {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1).toLowerCase()}';
  }
}

// Widget that displays a grid of content with pagination support
// Designed to work with PaginationWidget for page navigation
///
// Usage:
// - Main screen: showHeader = false (default) - clean design like nhentai main page
// - Search/Browse: showHeader = true - shows metadata and pagination info
// - Content cards: showUploadDate controlled per card basis
class ContentListWidget extends StatefulWidget {
  const ContentListWidget({
    super.key,
    this.onContentTap,
    this.enablePullToRefresh = true,
    this.enableInfiniteScroll = false, // Disabled by default for pagination
    this.showHeader = false, // Hidden by default for main screen style
    this.blurThumbnails = false,
    this.shouldBlurContent, // NEW: Function to determine if content should be blurred
    this.shouldHighlightContent, // NEW: Function to determine if content should be highlighted
    this.highlightReason, // NEW: Function to get highlight reason
  });

  final void Function(Content content)? onContentTap;
  final bool enablePullToRefresh;
  final bool enableInfiniteScroll;
  final bool showHeader;
  final bool blurThumbnails;
  final bool Function(Content content)? shouldBlurContent; // NEW: Blur logic
  final bool Function(Content content)?
  shouldHighlightContent; // NEW: Highlight logic
  final String? Function(Content content)?
  highlightReason; // NEW: Highlight reason logic

  @override
  State<ContentListWidget> createState() => _ContentListWidgetState();
}

class _ContentListWidgetState extends State<ContentListWidget> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ContentBloc, ContentState>(
      listener: (context, state) {
        if (state is ContentError) {
          // Reset refresh state and notify controller
          // Show error snackbar
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.userFriendlyMessage),
              action: state.canRetry
                  ? SnackBarAction(
                      label: AppLocalizations.of(context)!.retry,
                      onPressed: () {
                        context.read<ContentBloc>().add(
                          const ContentRetryEvent(),
                        );
                      },
                    )
                  : null,
            ),
          );
        }
      },
      builder: (context, state) {
        if (state is ContentInitial) {
          return Center(
            child: Text(
              AppLocalizations.of(context)!.tapToLoadContent,
              style: TextStyleConst.placeholderText.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        if (state is ContentEmpty) {
          final l10n = AppLocalizations.of(context)!;

          // Resolve l10n key from message
          String getDisplayMessage(String key) {
            switch (key) {
              case 'noContentAtMoment':
                return l10n.noContentAtMoment;
              case 'noContentMatchingSearch':
                return l10n.noContentMatchingSearch;
              case 'noPopularContent':
                return l10n.noPopularContent;
              case 'noContentForTag':
                return l10n.noContentForTag;
              case 'noContentOnPage':
                return l10n.noContentOnPage;
              default:
                return key;
            }
          }

          // Resolve suggestion keys to l10n
          List<String> getSuggestions(List<String> keys) {
            return keys.map((key) {
              switch (key) {
                case 'tryAdjustingFilters':
                  return l10n.tryAdjustingFilters;
                case 'tryRemovingSomeFilters':
                  return l10n.tryAdjustingFilters;
                case 'tryBrowsingOtherTags':
                  return l10n.tryBrowsingOtherTags;
                case 'checkPopularContent':
                  return l10n.checkPopularContent;
                case 'checkInternetConnection':
                  return l10n.checkInternetConnectionSuggestion;
                case 'checkInternetConnectionSuggestion':
                  return l10n.checkInternetConnectionSuggestion;
                case 'tryADifferentSearchTerm':
                  return l10n.tryADifferentSearchTerm;
                default:
                  return key;
              }
            }).toList();
          }

          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.6),
                ),
                const SizedBox(height: DesignTokens.spaceLg),
                Text(
                  getDisplayMessage(state.message),
                  textAlign: TextAlign.center,
                  style: TextStyleConst.bodyMedium.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceSm),
                if (state.suggestions.isNotEmpty) ...[
                  Text(
                    l10n.suggestions,
                    style: TextStyleConst.bodyMedium.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spaceXs),
                  ...getSuggestions(state.suggestions).map(
                    (suggestion) => Text(
                      '• $suggestion',
                      style: TextStyleConst.bodyMedium.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                if (state.canRetry) ...[
                  const SizedBox(height: DesignTokens.spaceLg),
                  ElevatedButton(
                    onPressed: () {
                      context.read<ContentBloc>().add(
                        const ContentRetryEvent(),
                      );
                    },
                    child: Text(l10n.tryAgain),
                  ),
                ],
              ],
            ),
          );
        }

        if (state is ContentError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  state.errorIcon,
                  style: TextStyleConst.displayMedium.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceLg),
                Text(
                  state.errorType.displayName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: DesignTokens.spaceSm),
                Text(
                  state.userFriendlyMessage,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (state.canRetry) ...[
                  const SizedBox(height: DesignTokens.spaceLg),
                  ElevatedButton(
                    onPressed: () {
                      context.read<ContentBloc>().add(
                        const ContentRetryEvent(),
                      );
                    },
                    child: Text(AppLocalizations.of(context)!.retry),
                  ),
                ],
                if (state.hasPreviousContent) ...[
                  const SizedBox(height: DesignTokens.spaceSm),
                  TextButton(
                    onPressed: () {
                      // Show cached content
                      // This would require additional implementation
                    },
                    child: Text(
                      AppLocalizations.of(context)!.showCachedContent,
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        if (state is ContentLoaded) {
          return _buildContentGrid(state);
        }

        return const SizedBox.shrink();
      },
    );
  }

  // Build the content grid layout
  Widget _buildContentGrid(ContentLoaded state) {
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // Content type header (conditional based on showHeader parameter)
        if (widget.showHeader)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.contentTypeDescription,
                          style: TextStyleConst.bodyLarge.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          '${state.totalCount} ${AppLocalizations.of(context)?.content ?? 'items'} • ${AppLocalizations.of(context)?.pageOf ?? 'Page'} ${state.currentPage} ${AppLocalizations.of(context)?.ofWord ?? 'of'} ${state.totalPages}',
                          style: TextStyleConst.bodySmall.copyWith(
                            color: Theme.of(context).colorScheme.onSurface
                                .withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (state.lastUpdated != null)
                    Text(
                      '${AppLocalizations.of(context)!.lastUpdatedLabel} ${_formatTime(state.lastUpdated!)}',
                      style: TextStyleConst.bodySmall.copyWith(
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: 0.5),
                      ),
                    ),
                ],
              ),
            ),
          ),

        // Featured content card (first item displayed as full-width)
        if (state.contents.isNotEmpty && state.currentPage == 1)
          SliverToBoxAdapter(
            child: Builder(
              builder: (context) {
                final isBlacklisted =
                    widget.shouldBlurContent?.call(state.contents.first) ??
                    false;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: MainFeaturedCard(
                    content: state.contents.first,
                    onTap: () =>
                        widget.onContentTap?.call(state.contents.first),
                    blurThumbnails: widget.blurThumbnails,
                    isBlacklisted: isBlacklisted,
                  ),
                );
              },
            ),
          ),

        // Content grid (skip first item if on page 1 since it's featured)
        SliverPadding(
          padding: EdgeInsets.all(widget.showHeader ? 8.0 : 16.0),
          sliver: SliverGrid(
            gridDelegate: ResponsiveGridDelegate.createGridDelegate(
              context,
              context.read<SettingsCubit>(),
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                // Skip index 0 on page 1 (already shown as featured)
                final adjustedIndex = state.currentPage == 1
                    ? index + 1
                    : index;
                if (adjustedIndex >= state.contents.length) {
                  return const SizedBox.shrink();
                }
                final content = state.contents[adjustedIndex];

                final isBlacklisted =
                    widget.shouldBlurContent?.call(content) ?? false;
                return MainGridCard(
                  content: content,
                  onTap: () => widget.onContentTap?.call(content),
                  blurThumbnails: widget.blurThumbnails,
                  isBlacklisted: isBlacklisted,
                );
              },
              // Reduce child count by 1 on first page (featured card is separate)
              childCount: state.currentPage == 1
                  ? (state.contents.length > 1 ? state.contents.length - 1 : 0)
                  : state.contents.length,
            ),
          ),
        ),

        // Bottom padding
        const SliverToBoxAdapter(child: SizedBox(height: DesignTokens.spaceLg)),
      ],
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return AppLocalizations.of(context)!.justNow;
    } else if (difference.inHours < 1) {
      return AppLocalizations.of(
        context,
      )!.minutesAgo(difference.inMinutes, difference.inMinutes == 1 ? '' : 's');
    } else if (difference.inDays < 1) {
      return AppLocalizations.of(context)!
          .hoursAgo(difference.inHours, difference.inHours == 1 ? '' : 's');
    } else {
      return AppLocalizations.of(context)!
          .daysAgo(difference.inDays, difference.inDays == 1 ? '' : 's');
    }
  }
}

// ContentCard is now imported from content_card_widget.dart
