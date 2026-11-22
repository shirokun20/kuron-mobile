import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/domain/entities/entities.dart';
import 'package:extended_image/extended_image.dart';

import 'package:url_launcher/url_launcher.dart';

class CommentItemWidget extends StatelessWidget {
  final Comment comment;

  const CommentItemWidget({super.key, required this.comment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('MMM d, yyyy • HH:mm');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: DesignTokens.elevationNone,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Avatar
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.surfaceContainerHighest,
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                      width: 1,
                    ),
                    image:
                        comment.avatarUrl != null &&
                            comment.avatarUrl!.isNotEmpty
                        ? DecorationImage(
                            // Unified image cache: extended_image disk cache
                            // + the global ImageCache budgeted by
                            // MemoryBudgetCoordinator (replaces
                            // legacy provider).
                            image: ExtendedNetworkImageProvider(
                              comment.avatarUrl!,
                              cache: true,
                              cacheMaxAge: const Duration(days: 14),
                            ),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: comment.avatarUrl == null || comment.avatarUrl!.isEmpty
                      ? Icon(Icons.person, size: 20, color: theme.hintColor)
                      : null,
                ),
                const SizedBox(width: 12),

                // Username and Date
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        comment.username,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (comment.postDate != null)
                        Text(
                          dateFormat.format(comment.postDate!),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Comment Body (Markdown)
            MarkdownWidget(
              data: comment.body,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(0),
              config: MarkdownConfig(
                configs: [
                  PConfig(
                    textStyle: theme.textTheme.bodyMedium!.copyWith(
                      color: theme.colorScheme.onSurface,
                      height: 1.5,
                    ),
                  ),
                  LinkConfig(
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                    onTap: (url) async {
                      if (url.isNotEmpty) {
                        final uri = Uri.tryParse(url);
                        if (uri != null && await canLaunchUrl(uri)) {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      }
                    },
                  ),
                  BlockquoteConfig(
                    sideColor: theme.colorScheme.primary,
                    // backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    textColor: theme.colorScheme.onSurfaceVariant,
                  ),
                  CodeConfig(
                    style: TextStyle(
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
