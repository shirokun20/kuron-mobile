import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/domain/entities/reader_badge.dart';
import 'package:nhasixapp/domain/repositories/user_data_repository.dart';
import 'package:nhasixapp/domain/usecases/reader_identity/get_reader_badge_usecase.dart';

class _MockUserData extends Mock implements UserDataRepository {}

class _MockRegistry extends Mock implements ContentSourceRegistry {}

class _FakeSource extends Fake implements ContentSource {
  _FakeSource(this._displayName);

  final String _displayName;

  @override
  String get displayName => _displayName;
}

void main() {
  late _MockUserData userData;
  late _MockRegistry registry;

  setUp(() {
    userData = _MockUserData();
    registry = _MockRegistry();
    when(() => userData.getCompletedHistoryCount())
        .thenAnswer((_) async => 0);
    when(() => userData.getTopDownloadSource())
        .thenAnswer((_) async => null);
  });

  GetReaderBadgeUseCase usecase() => GetReaderBadgeUseCase(
        userDataRepository: userData,
        sourceRegistry: registry,
      );

  test('no data yields base santai badge', () async {
    final badge = await usecase()();

    expect(badge.tier, ReaderTier.santai);
    expect(badge.completedCount, 0);
    expect(badge.topSourceId, isNull);
    expect(badge.topSourceDisplayName, '');
    expect(badge.topSourceDownloads, 0);
  });

  test('completed count drives tier', () async {
    when(() => userData.getCompletedHistoryCount())
        .thenAnswer((_) async => 60);

    final badge = await usecase()();

    expect(badge.tier, ReaderTier.otaku);
    expect(badge.completedCount, 60);
  });

  test('top source resolves display name and count', () async {
    when(() => userData.getCompletedHistoryCount())
        .thenAnswer((_) async => 12);
    when(() => userData.getTopDownloadSource()).thenAnswer(
        (_) async => (sourceId: 'komikcast', count: 7));
    when(() => registry.getSource('komikcast'))
        .thenReturn(_FakeSource('Komikcast'));

    final badge = await usecase()();

    expect(badge.tier, ReaderTier.kutubuku);
    expect(badge.topSourceId, 'komikcast');
    expect(badge.topSourceDisplayName, 'Komikcast');
    expect(badge.topSourceDownloads, 7);
  });

  test('unknown source falls back to raw id', () async {
    when(() => userData.getTopDownloadSource()).thenAnswer(
        (_) async => (sourceId: 'obscure', count: 3));
    when(() => registry.getSource('obscure')).thenReturn(null);

    final badge = await usecase()();

    expect(badge.topSourceDisplayName, 'obscure');
  });

  test('hentai top source overrides to shaker', () async {
    when(() => userData.getCompletedHistoryCount())
        .thenAnswer((_) async => 150);
    when(() => userData.getTopDownloadSource()).thenAnswer(
        (_) async => (sourceId: 'nhentai', count: 40));
    when(() => registry.getSource('nhentai'))
        .thenReturn(_FakeSource('nhentai'));

    final badge = await usecase()();

    expect(badge.tier, ReaderTier.shaker);
  });
}
