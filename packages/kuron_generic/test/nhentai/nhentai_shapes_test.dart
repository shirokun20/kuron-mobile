import 'package:kuron_generic/src/nhentai/nhentai_shapes.dart';
import 'package:test/test.dart';

// Golden nhentai v2 payload shape (mirrors production `media_id` payloads).
Map<String, dynamic> _v2({
  Object? title = const {
    'english': '[Artist] Title EN',
    'japanese': 'タイトル',
    'pretty': 'Title Pretty',
  },
  Object? thumbnail = '/thumb/abc.jpg',
  Object? cover,
  Object? pages = const [
    {'path': '/galleries/1/1.jpg'},
    {'path': '/galleries/1/2.png'},
    {'path': ''},
  ],
  Object? englishTitle = 'List EN',
}) {
  return {
    'media_id': '123',
    'title': title,
    'thumbnail': thumbnail,
    if (cover != null) 'cover': cover,
    'pages': pages,
    'english_title': englishTitle,
  };
}

void main() {
  group('nhentai v2 shapes (adapter parity)', () {
    test('shape gate requires nhentai sourceId + v2 keys', () {
      expect(isNhentaiV2Shape('nhentai', _v2()), isTrue);
      expect(isNhentaiV2Shape('other', _v2()), isFalse);
      expect(isNhentaiV2Shape('nhentai', {'id': 1}), isFalse);
      expect(isNhentaiV2Shape('nhentai', []), isFalse);
    });

    test('list title prefers english, falls back, Unknown otherwise', () {
      expect(
        extractNhentaiV2ListTitle(_v2(), sourceId: 'nhentai'),
        'List EN',
      );
      expect(
        extractNhentaiV2ListTitle(
          _v2(englishTitle: ''),
          sourceId: 'nhentai',
        ),
        'Unknown',
      );
      expect(
        extractNhentaiV2ListTitle(_v2(), sourceId: 'other'),
        'Unknown',
      );
    });

    test('detail title prefers pretty, then english, then japanese', () {
      expect(
        extractNhentaiV2DetailTitle(_v2(), sourceId: 'nhentai'),
        'Title Pretty',
      );
      expect(
        extractNhentaiV2DetailTitle(
          _v2(
            title: const {'english': 'EN', 'japanese': 'JA'},
          ),
          sourceId: 'nhentai',
        ),
        'EN',
      );
      expect(
        extractNhentaiV2DetailTitle(
          _v2(
            title: const {'japanese': 'JA'},
          ),
          sourceId: 'nhentai',
        ),
        'JA',
      );
    });

    test('field reads title map, null when gated or absent', () {
      expect(
        extractNhentaiV2Field(_v2(), 'pretty', sourceId: 'nhentai'),
        'Title Pretty',
      );
      expect(
        extractNhentaiV2Field(_v2(), 'missing', sourceId: 'nhentai'),
        isNull,
      );
      expect(
        extractNhentaiV2Field(_v2(), 'pretty', sourceId: 'other'),
        isNull,
      );
    });

    test('cover prefers string thumbnail, then cover/thumbnail maps', () {
      expect(
        resolveNhentaiV2CoverUrl(_v2(), sourceId: 'nhentai'),
        'https://t.nhentai.net/thumb/abc.jpg',
      );
      expect(
        resolveNhentaiV2CoverUrl(
          _v2(thumbnail: null, cover: {'path': '/c/1.jpg'}),
          sourceId: 'nhentai',
        ),
        'https://t.nhentai.net/c/1.jpg',
      );
      expect(
        resolveNhentaiV2CoverUrl(
          _v2(thumbnail: null),
          sourceId: 'nhentai',
        ),
        isNull,
      );
    });

    test('page urls skip empties, use image host', () {
      expect(
        resolveNhentaiV2ImageUrls(_v2(), sourceId: 'nhentai'),
        [
          'https://i.nhentai.net/galleries/1/1.jpg',
          'https://i.nhentai.net/galleries/1/2.png',
        ],
      );
      expect(
        resolveNhentaiV2ImageUrls(
          _v2(pages: 'nope'),
          sourceId: 'nhentai',
        ),
        isEmpty,
      );
      expect(
        resolveNhentaiV2ImageUrls(_v2(), sourceId: 'other'),
        isEmpty,
      );
    });

    test('asset url passes absolute through, picks host by kind', () {
      expect(
        resolveNhentaiV2AssetUrl('https://x/y.jpg', thumbnail: false),
        'https://x/y.jpg',
      );
      expect(
        resolveNhentaiV2AssetUrl('/g/1.jpg', thumbnail: false),
        'https://i.nhentai.net/g/1.jpg',
      );
      expect(
        resolveNhentaiV2AssetUrl('g/1.jpg', thumbnail: true),
        'https://t.nhentai.net/g/1.jpg',
      );
    });
  });
}
