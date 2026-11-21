import 'package:material_ui/material_ui.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/services/legal_content_service.dart';
import 'package:nhasixapp/presentation/widgets/shimmer_loading_widgets.dart';

import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';

// Bottom sheet widget for displaying legal content (T&C, Privacy, FAQ)
class LegalContentSheet extends StatefulWidget {
  const LegalContentSheet({
    super.key,
    required this.contentType,
    required this.locale,
  });

  final LegalContentType contentType;
  final String locale;

  // Show the legal content bottom sheet
  static Future<void> show(
    BuildContext context, {
    required LegalContentType contentType,
    required String locale,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) =>
          LegalContentSheet(contentType: contentType, locale: locale),
    );
  }

  @override
  State<LegalContentSheet> createState() => _LegalContentSheetState();
}

class _LegalContentSheetState extends State<LegalContentSheet> {
  late final LegalContentService _service;
  String? _content;
  String? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _service = getIt<LegalContentService>();
    _loadContent();
  }

  Future<void> _loadContent() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final content = await _service.fetchContent(
        widget.contentType,
        widget.locale,
      );
      if (mounted) {
        setState(() {
          _content = content;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _service.getTitle(widget.contentType, widget.locale);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  tooltip: AppLocalizations.of(context)!.close,
                ),
              ],
            ),
          ),

          Divider(height: 1, color: theme.colorScheme.outlineVariant),

          // Content
          Expanded(child: _buildContent(theme)),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_isLoading) {
      return _buildLoadingState(theme);
    }

    if (_error != null) {
      return _buildErrorState(theme);
    }

    if (_content != null) {
      return _buildMarkdownContent(theme);
    }

    return const SizedBox.shrink();
  }

  Widget _buildLoadingState(ThemeData theme) {
    return KuronShimmer(
      baseColor: theme.colorScheme.surfaceContainerHighest,
      highlightColor: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 24,
              width: double.infinity,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              height: 16,
              width: double.infinity,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 16,
              width: MediaQuery.of(context).size.width * 0.7,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              height: 20,
              width: MediaQuery.of(context).size.width * 0.5,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 16,
              width: double.infinity,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.failedToLoadContent,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unknown error',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loadContent,
              icon: const Icon(Icons.refresh),
              label: Text(AppLocalizations.of(context)!.retryAction),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarkdownContent(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    return MarkdownWidget(
      data: _content!,
      padding: const EdgeInsets.all(20),
      config: MarkdownConfig(
        configs: [
          // H1 styling
          H1Config(
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          // H2 styling
          H2Config(
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          // H3 styling
          H3Config(
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          // Paragraph styling
          PConfig(
            textStyle: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          // Link styling
          LinkConfig(
            style: TextStyle(
              color: theme.colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
          ),
          // Blockquote styling
          BlockquoteConfig(
            sideColor: theme.colorScheme.primary,
            textColor: theme.colorScheme.onSurfaceVariant,
          ),
          // Code block styling
          PreConfig(theme: isDark ? darkMarkdownTheme : lightMarkdownTheme),
          // Table styling
          TableConfig(
            headerStyle: TextStyle(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
            bodyStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// Dark theme for code blocks
const darkMarkdownTheme = {
  'root': TextStyle(
    color: Color(0xffdcdcdc),
    backgroundColor: Color(0xff1e1e1e),
  ),
  'keyword': TextStyle(color: Color(0xff569cd6)),
  'string': TextStyle(color: Color(0xffce9178)),
  'number': TextStyle(color: Color(0xffb5cea8)),
  'comment': TextStyle(color: Color(0xff6a9955)),
};

// Light theme for code blocks
const lightMarkdownTheme = {
  'root': TextStyle(
    color: Color(0xff1e1e1e),
    backgroundColor: Color(0xfff5f5f5),
  ),
  'keyword': TextStyle(color: Color(0xff0000ff)),
  'string': TextStyle(color: Color(0xffa31515)),
  'number': TextStyle(color: Color(0xff098658)),
  'comment': TextStyle(color: Color(0xff008000)),
};
