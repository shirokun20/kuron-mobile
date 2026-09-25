import 'package:flutter/material.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';

class DetailStateHeader extends StatelessWidget {
  const DetailStateHeader({
    super.key,
    required this.title,
    required this.onBack,
  });

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHighest,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                  Icons.arrow_back,
                  color: colorScheme.onSurfaceVariant,
                ),
                onPressed: onBack,
              ),
              Expanded(
                child: Text(
                  title,
                  style: TextStyleConst.headingMedium.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DetailErrorView extends StatelessWidget {
  const DetailErrorView({
    super.key,
    required this.headerTitle,
    required this.errorTitle,
    required this.errorMessage,
    required this.onBack,
    required this.backLabel,
    this.onLogin,
    this.onRetry,
    this.loginLabel,
    this.retryLabel,
    this.isLoginError = false,
  });

  final String headerTitle;
  final String errorTitle;
  final String errorMessage;
  final VoidCallback onBack;
  final String backLabel;
  final VoidCallback? onLogin;
  final VoidCallback? onRetry;
  final String? loginLabel;
  final String? retryLabel;
  final bool isLoginError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        DetailStateHeader(title: headerTitle, onBack: onBack),
        Expanded(
          child: Container(
            color: colorScheme.surface,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: isLoginError
                            ? colorScheme.primaryContainer
                            : colorScheme.errorContainer,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isLoginError
                              ? colorScheme.primary.withValues(alpha: 0.5)
                              : colorScheme.error.withValues(alpha: 0.5),
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        isLoginError ? Icons.lock_person : Icons.error_outline,
                        size: 64,
                        color: isLoginError
                            ? colorScheme.primary
                            : colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      errorTitle,
                      style: TextStyleConst.headingLarge.copyWith(
                        color: isLoginError
                            ? colorScheme.primary
                            : colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainer,
                        borderRadius:
                            BorderRadius.circular(DesignTokens.radiusLg),
                        border: Border.all(
                          color: colorScheme.outline,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        errorMessage,
                        style: TextStyleConst.bodyMedium.copyWith(
                          color: colorScheme.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (onLogin != null) ...[
                          ElevatedButton.icon(
                            onPressed: onLogin,
                            icon: const Icon(Icons.login),
                            label: Text(loginLabel ?? 'Login'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colorScheme.primary,
                              foregroundColor: colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    DesignTokens.radiusMd),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                        ] else if (onRetry != null) ...[
                          ElevatedButton.icon(
                            onPressed: onRetry,
                            icon: const Icon(Icons.refresh),
                            label: Text(retryLabel ?? 'Retry'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colorScheme.primary,
                              foregroundColor: colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    DesignTokens.radiusMd),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                        ],
                        OutlinedButton.icon(
                          onPressed: onBack,
                          icon: const Icon(Icons.arrow_back),
                          label: Text(backLabel),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colorScheme.onSurfaceVariant,
                            side: BorderSide(color: colorScheme.outline),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(DesignTokens.radiusMd),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
