import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';

// Advanced pagination widget with page navigation and progress indicator
class PaginationWidget extends StatefulWidget {
  const PaginationWidget({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.hasNext,
    required this.hasPrevious,
    required this.onNextPage,
    required this.onPreviousPage,
    required this.onGoToPage,
    this.showProgressBar = true,
    this.showPercentage = true,
    this.showPageInput = false,
  });

  final int currentPage;
  final int totalPages;
  final bool hasNext;
  final bool hasPrevious;
  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;
  final Function(int) onGoToPage;
  final bool showProgressBar;
  final bool showPercentage;
  final bool showPageInput;

  @override
  State<PaginationWidget> createState() => _PaginationWidgetState();
}

class _PaginationWidgetState extends State<PaginationWidget> {
  final TextEditingController _pageController = TextEditingController();
  // bool _showPageInput = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  double get progressPercentage {
    if (widget.totalPages <= 0) return 0.0;
    return widget.currentPage / widget.totalPages;
  }

  void _showPageInputDialog() {
    _pageController.text = widget.currentPage.toString();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        title: Text(
          AppLocalizations.of(context)!.goToPage,
          style: TextStyleConst.headingSmall.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppLocalizations.of(context)!.enterPageNumber(widget.totalPages),
              style: TextStyleConst.bodyMedium.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pageController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              style: TextStyleConst.bodyLarge.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!
                    .pageNumber(widget.currentPage),
                hintStyle: TextStyleConst.placeholderText.copyWith(
                  fontSize: 16,
                ),
                border: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.outline
                        .withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              autofocus: true,
              onSubmitted: (value) {
                _goToPage();
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: TextStyleConst.buttonMedium.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              _goToPage();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
            child: Text(
              AppLocalizations.of(context)!.go,
              style: TextStyleConst.buttonMedium.copyWith(
                color: Theme.of(context).colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _goToPage() {
    final pageText = _pageController.text.trim();
    if (pageText.isEmpty) return;

    final page = int.tryParse(pageText);
    if (page == null || page < 1 || page > widget.totalPages) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!
                .validPageNumberError(widget.totalPages),
            style: TextStyleConst.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.onError,
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    widget.onGoToPage(page);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Main pagination row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              // Previous button
              IconButton(
                iconSize: 32,
                onPressed: widget.hasPrevious ? widget.onPreviousPage : null,
                icon: const Icon(Icons.chevron_left),
                color: widget.hasPrevious
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.4),
                tooltip: AppLocalizations.of(context)!.previousPageTooltip,
              ),

              const Spacer(),

              // Page info section
              Expanded(
                flex: 3,
                child: GestureDetector(
                  onTap: widget.showPageInput ? _showPageInputDialog : null,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Page text
                      Text(
                        AppLocalizations.of(context)!
                            .pageOfTotal(widget.currentPage, widget.totalPages),
                        style: TextStyleConst.bodyLarge.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      if (widget.showProgressBar) ...[
                        const SizedBox(height: 6),
                        // Progress bar
                        Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.outline
                                .withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: progressPercentage,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ],

                      if (widget.showPercentage) ...[
                        const SizedBox(height: 4),
                        // Progress percentage
                        Text(
                          '${(progressPercentage * 100).toStringAsFixed(1)}%',
                          style: TextStyleConst.caption,
                          textAlign: TextAlign.center,
                        ),
                      ],

                      if (widget.showPageInput) ...[
                        const SizedBox(height: 2),
                        Text(
                          AppLocalizations.of(context)!.tapToJumpToPage,
                          style: TextStyleConst.overline.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // Next button
              IconButton(
                iconSize: 32,
                onPressed: widget.hasNext ? widget.onNextPage : null,
                icon: const Icon(Icons.chevron_right),
                color: widget.hasNext
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.4),
                tooltip: AppLocalizations.of(context)!.nextPageTooltip,
              ),

              const Spacer(),
            ],
          ),

          // Additional info row (optional)
          if (widget.totalPages > 1000) ...[
            const SizedBox(height: 4),
            Text(
              'Total: ${widget.totalPages.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} pages',
              style: TextStyleConst.overline.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

// Simple pagination widget for basic use cases
class SimplePaginationWidget extends StatelessWidget {
  const SimplePaginationWidget({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.hasNext,
    required this.hasPrevious,
    required this.onNextPage,
    required this.onPreviousPage,
  });

  final int currentPage;
  final int totalPages;
  final bool hasNext;
  final bool hasPrevious;
  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Previous button
          TextButton.icon(
            onPressed: hasPrevious ? onPreviousPage : null,
            icon: const Icon(Icons.chevron_left),
            label: Text(AppLocalizations.of(context)!.previous),
            style: TextButton.styleFrom(
              foregroundColor: hasPrevious
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: 0.4),
            ),
          ),

          // Page info
          Text(
            '$currentPage / $totalPages',
            style: TextStyleConst.bodyLarge.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),

          // Next button
          TextButton.icon(
            onPressed: hasNext ? onNextPage : null,
            icon: const Icon(Icons.chevron_right),
            label: Text(AppLocalizations.of(context)!.next),
            style: TextButton.styleFrom(
              foregroundColor: hasNext
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}
