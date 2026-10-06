import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/favorite_models.dart';

Map<String, dynamic> itemJson({String kind = 'note', int schema = 1}) => {
      'id': 'fav1',
      'kind': kind,
      'title': '标题',
      'status': 'ready',
      'version': 2,
      'schemaVersion': schema,
      'contentRevision': 'r2',
      'createdAt': 1700000000000,
      'content': {
        'blocks': [
          {'id': 'b1', 'type': 'text', 'text': '正文'}
        ]
      }
    };

void main() {
  test('unknown kind and future schema stay visible and cannot send', () {
    final unknown = FavoriteItem.fromJson(itemJson(kind: 'future_kind'));
    expect(unknown.kind, FavoriteKind.unknown);
    expect(unknown.rawKind, 'future_kind');
    expect(unknown.canSend, isFalse);
    expect(FavoriteItem.fromJson(itemJson(schema: 2)).canSend, isFalse);
    expect(FavoriteItem.fromJson(itemJson()).text, '正文');
    expect(FavoriteItem.fromJson(itemJson(kind: 'message_bundle')).canSend,
        isFalse);
  });
  test('strict fields reject malformed values and duplicate blocks', () {
    expect(() => FavoriteItem.fromJson({...itemJson(), 'version': '2'}),
        throwsFormatException);
    expect(
        () => FavoriteItem.fromJson({...itemJson(), 'createdAt': 'yesterday'}),
        throwsFormatException);
    expect(
        () => FavoriteContent.fromJson({
              'kind': 'note',
              'blocks': [
                {'id': 'a', 'type': 'text'},
                {'id': 'a', 'type': 'text'}
              ]
            }),
        throwsFormatException);
  });
  test('metadata cache omits private body, assets and download URLs', () {
    final item = FavoriteItem.fromJson(itemJson());
    final cached = item.toCacheJson();
    expect(cached.containsKey('content'), isFalse);
    expect(cached.containsKey('assets'), isFalse);
    expect(FavoriteItem.fromJson(cached).content, isNull);
  });
  test('prepared media requires matching assets and valid signed authorization',
      () {
    final json = {
      'prepareID': 'p1',
      'contentRevision': 'r1',
      'expiresAt': 1700000000000,
      'sendContent': {
        'kind': 'image',
        'blocks': [
          {'id': 'b1', 'type': 'image', 'assetID': 'a1'}
        ]
      },
      'downloads': <Object>[]
    };
    expect(() => FavoritePreparedSend.fromJson(json), throwsFormatException);
    json['downloads'] = [
      {
        'assetID': 'a1',
        'url': 'https://storage.test/a?sig=private',
        'sizeBytes': 2,
        'sha256': 'a' * 64
      }
    ];
    expect(FavoritePreparedSend.fromJson(json).downloads.single.assetID, 'a1');
    json['downloads'] = [
      {
        'assetID': 'a1',
        'url': 'file:///private',
        'sizeBytes': 2,
        'sha256': 'a' * 64
      }
    ];
    expect(() => FavoritePreparedSend.fromJson(json), throwsFormatException);
  });
}
