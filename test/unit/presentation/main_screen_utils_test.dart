import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/presentation/pages/main/services/main_screen_utils.dart';

void main() {
  group('MainScreenUtils.formatDisplayQuery', () {
    test('returns plain query unchanged', () {
      expect(MainScreenUtils.formatDisplayQuery('naruto'), 'naruto');
      expect(MainScreenUtils.formatDisplayQuery('the honor student'),
          'the honor student');
    });

    test('decodes single raw keyword query cleanly', () {
      expect(
        MainScreenUtils.formatDisplayQuery('raw:keyword=the%20honor%20student'),
        'the honor student',
      );
      expect(
        MainScreenUtils.formatDisplayQuery('raw:query=one%20piece'),
        'one piece',
      );
      expect(
        MainScreenUtils.formatDisplayQuery('raw:q=bleach'),
        'bleach',
      );
    });

    test('decodes multi-param raw queries cleanly', () {
      expect(
        MainScreenUtils.formatDisplayQuery(
            'raw:keyword=the%20honor&genres_in[]=23'),
        'the honor, genres_in: 23',
      );
      expect(
        MainScreenUtils.formatDisplayQuery('raw:sort=relevance:desc&keyword=test'),
        'sort: relevance:desc, test',
      );
    });
  });

  group('MainScreenUtils.removeRawSearchQueryParam', () {
    test('removes specific parameter from raw query', () {
      expect(
        MainScreenUtils.removeRawSearchQueryParam(
            'raw:keyword=the&sort=relevance', 'sort'),
        'raw:keyword=the',
      );
    });
  });
}
