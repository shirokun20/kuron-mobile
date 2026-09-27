import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart' hide CustomTransitionPage;
import 'package:nhasixapp/core/utils/app_animations.dart';

void main() {
  group('typeForKind', () {
    test('forward drills in horizontally with fade', () {
      expect(AppAnimations.typeForKind(RouteKind.forward),
          RouteTransitionType.fadeSlide);
    });

    test('upward rises as a layer above', () {
      expect(AppAnimations.typeForKind(RouteKind.upward),
          RouteTransitionType.slideUp);
    });

    test('tab cross-fades without sliding', () {
      expect(
          AppAnimations.typeForKind(RouteKind.tab), RouteTransitionType.fade);
    });
  });

  group('durations', () {
    test('pop is faster than push', () {
      expect(AppAnimations.popDuration < AppAnimations.pushDuration, isTrue);
      expect(AppAnimations.pushDuration, const Duration(milliseconds: 300));
      expect(AppAnimations.popDuration, const Duration(milliseconds: 220));
    });
  });

  group('createPage', () {
    test('kind overrides default type', () {
      final page = AppAnimations.createPage(
        child: const SizedBox(),
        name: 'up',
        kind: RouteKind.upward,
      ) as CustomTransitionPage;
      expect(page.transitionType, RouteTransitionType.slideUp);
      expect(page.transitionDuration, AppAnimations.pushDuration);
      expect(page.reverseTransitionDuration, AppAnimations.popDuration);
    });

    test('explicit type wins when kind is absent', () {
      final page = AppAnimations.createPage(
        child: const SizedBox(),
        name: 's',
        type: RouteTransitionType.slideLeft,
      ) as CustomTransitionPage;
      expect(page.transitionType, RouteTransitionType.slideLeft);
    });

    test('reduced motion collapses to instant fade', () {
      final page = AppAnimations.createPage(
        child: const SizedBox(),
        name: 'rm',
        kind: RouteKind.forward,
        disableAnimations: true,
      ) as CustomTransitionPage;
      expect(page.transitionType, RouteTransitionType.fade);
      expect(page.transitionDuration, Duration.zero);
      expect(page.reverseTransitionDuration, Duration.zero);
    });
  });

  group('routes render per kind', () {
    for (final kind in RouteKind.values) {
      testWidgets('createRoute renders ${kind.name}', (tester) async {
        final route = AppAnimations.createRoute(
          page: Text('page-${kind.name}', textDirection: TextDirection.ltr),
          type: AppAnimations.typeForKind(kind),
        );
        await tester.pumpWidget(MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(route),
              child: const Text('go'),
            ),
          ),
        ));
        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();
        expect(find.text('page-${kind.name}'), findsOneWidget);
      });
    }

    testWidgets('animatedPageBuilder honors reduced motion', (tester) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) => AppAnimations.animatedPageBuilder(
              context,
              state,
              const Text('reduced-hi'),
              kind: RouteKind.forward,
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      expect(find.text('reduced-hi'), findsOneWidget);
    });
  });
}
