import 'package:material_ui/material_ui.dart';

// A reusable widget that highlights matching text within a string.
///
// When [highlight] is non-empty, splits [text] into segments and applies
// [highlightStyle] to portions matching the query (case-insensitive).
// All occurrences are highlighted, not just the first.
///
// Usage:
// ```dart
// HighlightedText(
//   text: 'Naruto Shippuden',
//   highlight: 'nar',
//   style: TextStyle(color: Colors.white),
// )
// ```
class HighlightedText extends StatelessWidget {
  final String text;
  final String highlight;
  final TextStyle? style;
  final TextStyle? highlightStyle;
  final int maxLines;
  final TextOverflow overflow;

  const HighlightedText({
    super.key,
    required this.text,
    required this.highlight,
    this.style,
    this.highlightStyle,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  @override
  Widget build(BuildContext context) {
    if (highlight.isEmpty) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }

    final colorScheme = Theme.of(context).colorScheme;

    final effectiveHighlightStyle =
        highlightStyle ??
        (style ?? DefaultTextStyle.of(context).style).copyWith(
          backgroundColor: colorScheme.primary.withValues(alpha: 0.2),
          fontWeight: FontWeight.w700,
          color: colorScheme.primary,
        );

    final spans = _buildSpans(effectiveHighlightStyle);

    return RichText(
      text: TextSpan(
        style: style ?? DefaultTextStyle.of(context).style,
        children: spans,
      ),
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  List<TextSpan> _buildSpans(TextStyle effectiveHighlightStyle) {
    final spans = <TextSpan>[];
    final lowerText = text.toLowerCase();
    final lowerHighlight = highlight.toLowerCase();
    int start = 0;

    while (start < text.length) {
      final index = lowerText.indexOf(lowerHighlight, start);
      if (index == -1) {
        // No more matches — add remaining text
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }

      // Add text before the match
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }

      // Add matched text with highlight style (preserve original casing)
      spans.add(
        TextSpan(
          text: text.substring(index, index + highlight.length),
          style: effectiveHighlightStyle,
        ),
      );

      start = index + highlight.length;
    }

    // Edge case: if text ends exactly at a match boundary
    if (spans.isEmpty) {
      spans.add(TextSpan(text: text));
    }

    return spans;
  }
}
