import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/presentation/cubits/reader/reader_prefetch_cubit.dart';

// Prefetch Cubit policy tests. Local file:// URLs take the fast path (nothing
// to download → marked prefetched immediately), so these never hit a real
// Dio / network call.
void main() {
  ReaderPrefetchCubit makeCubit() => ReaderPrefetchCubit(
        logger: Logger(level: Level.off),
      );

  List<String> urls(int n) =>
      [for (var i = 1; i <= n; i++) 'file:///page_$i.jpg'];

  // NOTE: `file://` URLs take the back-marking fast path (non-http → marked
  // prefetched immediately, no Dio) but the forward loop SKIPS non-http URLs
  // (they're local/cached, nothing to prefetch). So with all-file URLs we can
  // assert the back bookkeeping + clamping without hitting network.

  test('back pages marked prefetched (non-http fast path)', () async {
    final cubit = makeCubit();
    addTearDown(cubit.close);
    // Page 5 of 10 → back 4 (non-http → marked); forward 6,7,8 → skipped.
    await cubit.prefetchImages(
      currentPage: 5,
      imageUrls: urls(10),
      contentId: 'c1',
    );
    final s = cubit.state;
    expect(s.prefetchedPages.contains(4), true);
    expect(s.prefetchedPages.contains(6), false);
    expect(s.prefetchedPages.contains(7), false);
    expect(s.prefetchedPages.contains(8), false);
  });

  test('clamps back window at page 1', () async {
    final cubit = makeCubit();
    addTearDown(cubit.close);
    await cubit.prefetchImages(
        currentPage: 1, imageUrls: urls(3), contentId: 'c1');
    expect(cubit.state.prefetchedPages.contains(0), false);
  });

  test('squares cancelAll resets bookkeeping', () async {
    final cubit = makeCubit();
    addTearDown(cubit.close);
    await cubit.prefetchImages(
        currentPage: 5, imageUrls: urls(10), contentId: 'c1');
    expect(cubit.state.prefetchedPages, isNotEmpty);
    cubit.cancelAll();
    expect(cubit.state.prefetchedPages, isEmpty);
    expect(cubit.state.inflightPages, isEmpty);
  });

  test('non-http local path marked prefetched (fast path)', () async {
    final cubit = makeCubit();
    addTearDown(cubit.close);
    await cubit.prefetchImages(
      currentPage: 2,
      imageUrls: urls(2),
      contentId: 'c1',
    );
    // Back page 1 (non-http) → marked prefetched; forward page 3 beyond last → none.
    expect(cubit.state.prefetchedPages, {1});
  });
}
