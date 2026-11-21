import 'package:material_ui/material_ui.dart';

import '../../core/constants/design_tokens.dart';
import '../../core/constants/text_style_const.dart';

// Search widget for filter data with modern design
class FilterDataSearchWidget extends StatelessWidget {
  const FilterDataSearchWidget({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    this.hintText = 'Search...',
    this.enabled = true,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final String hintText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        border: Border.all(
          color: focusNode.hasFocus
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline,
          width: focusNode.hasFocus ? 2 : 1,
        ),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        onChanged: onChanged,
        style: TextStyleConst.bodyLarge.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyleConst.bodyLarge.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant
                .withValues(alpha: 0.6),
          ),
          prefixIcon: Icon(
            Icons.search,
            color: focusNode.hasFocus
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.6),
          ),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: Theme.of(context).colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.6),
                  ),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
    );
  }
}

// Search widget with real-time suggestions
class FilterDataSearchWithSuggestions extends StatefulWidget {
  const FilterDataSearchWithSuggestions({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.suggestions,
    this.hintText = 'Search...',
    this.enabled = true,
    this.onSuggestionTap,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final List<String> suggestions;
  final String hintText;
  final bool enabled;
  final ValueChanged<String>? onSuggestionTap;

  @override
  State<FilterDataSearchWithSuggestions> createState() =>
      _FilterDataSearchWithSuggestionsState();
}

class _FilterDataSearchWithSuggestionsState
    extends State<FilterDataSearchWithSuggestions> {
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    setState(() {
      _showSuggestions =
          widget.focusNode.hasFocus &&
          widget.suggestions.isNotEmpty &&
          widget.controller.text.isNotEmpty;
    });
  }

  void _onChanged(String value) {
    widget.onChanged(value);
    setState(() {
      _showSuggestions =
          widget.focusNode.hasFocus &&
          widget.suggestions.isNotEmpty &&
          value.isNotEmpty;
    });
  }

  void _onSuggestionTap(String suggestion) {
    widget.controller.text = suggestion;
    widget.onChanged(suggestion);
    widget.onSuggestionTap?.call(suggestion);
    setState(() {
      _showSuggestions = false;
    });
    widget.focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FilterDataSearchWidget(
          controller: widget.controller,
          focusNode: widget.focusNode,
          onChanged: _onChanged,
          hintText: widget.hintText,
          enabled: widget.enabled,
        ),
        if (_showSuggestions) ...[
          const SizedBox(height: 8),
          _buildSuggestions(),
        ],
      ],
    );
  }

  Widget _buildSuggestions() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: widget.suggestions.length,
        itemBuilder: (context, index) {
          final suggestion = widget.suggestions[index];
          return ListTile(
            dense: true,
            leading: Icon(
              Icons.search,
              size: 20,
              color: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: 0.7),
            ),
            title: Text(
              suggestion,
              style: TextStyleConst.bodyMedium.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            onTap: () => _onSuggestionTap(suggestion),
          );
        },
      ),
    );
  }
}
