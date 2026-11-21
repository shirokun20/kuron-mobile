import 'dart:ui';

import 'package:material_ui/material_ui.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/services/app_privacy_overlay_service.dart';

// Renders a privacy blur above the current routed content when the app moves
// into background-facing lifecycle states, so recent-apps previews capture an
// obscured frame instead of the real content.
class AppPrivacyOverlayGate extends StatelessWidget {
  const AppPrivacyOverlayGate({required this.child, this.service, super.key});

  final Widget child;
  final AppPrivacyOverlayService? service;

  @override
  Widget build(BuildContext context) {
    final resolvedService = service ?? getIt<AppPrivacyOverlayService>();

    return AnimatedBuilder(
      animation: resolvedService,
      child: child,
      builder: (context, builtChild) {
        final baseChild = builtChild ?? const SizedBox.shrink();
        if (!resolvedService.isObscured) {
          return baseChild;
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            baseChild,
            Positioned.fill(
              child: AbsorbPointer(
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.32),
                            Colors.black.withValues(alpha: 0.56),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
