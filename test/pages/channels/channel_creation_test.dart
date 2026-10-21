import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim/pages/channels/data/channel_creation.dart';
import 'package:openim/pages/channels/models/channel_kind.dart';
import 'package:openim/pages/channels/models/channel_id.dart';
import 'package:openim/pages/channels/models/channel_preview.dart';

ChannelPreview draft() => ChannelPreview(name: '频道', description: '简介')
  ..avatar = Uint8List.fromList([1, 2])
  ..selectedContacts['friend'] = ISUserInfo.fromJson({'userID': 'friend'})
  ..selectedContacts['self'] = ISUserInfo.fromJson({'userID': 'self'});

void main() {
  test('channel IDs are twelve mixed-case alphanumeric characters', () {
    for (var i = 0; i < 200; i++) {
      final id = generateChannelID();
      expect(id, matches(r'^[A-Za-z0-9]{12}$'));
      expect(id, matches('[A-Z]'));
      expect(id, matches('[a-z]'));
      expect(id, matches('[0-9]'));
    }
  });
  test('creates without avatar and skips upload', () async {
    final value = ChannelPreview(name: '频道', description: '');
    final creation = ChannelCreation(owner: 'self', current: () => true,
      upload: (_) async => throw StateError('Must not upload'),
      lookup: (_) async => [], mute: (_) async {},
      create: (info, members) async {
        expect(info.faceURL, '');
        expect(info.groupID, matches(r'^[A-Za-z0-9]{12}$'));
        expect(info.groupName, '频道');
        return info;
      });
    await creation.submit(value);
    expect(value.createdGroup, isNotNull);
    value.dispose();
  });
  test('marker preserves other metadata and treats legacy groups normally', () {
    final ex = channelEx(existing: '{"groupFeatures":{"revision":3}}');
    expect(isChannelEx(ex), isTrue);
    expect(jsonDecode(ex)['groupFeatures']['revision'], 3);
    for (final value in [
      null,
      '',
      'broken',
      '[]',
      '{}',
      '{"conversationKind":"group"}'
    ]) {
      expect(isChannelEx(value), isFalse);
    }
  });
  test('creates a muted work group with channel marker and selected members',
      () async {
    final value = draft();
    final creation = ChannelCreation(
        owner: 'self',
        id: 'stable',
        current: () => true,
        upload: (_) async => 'https://avatar',
        lookup: (_) async => [],
        mute: (_) async => fail('Already muted'),
        create: (info, members) async {
          expect(info.groupType, GroupType.work);
          expect(info.status, 3);
          expect(info.groupID, 'stable');
          expect(isChannelEx(info.ex), isTrue);
          expect(info.introduction, '简介');
          expect(members, ['friend']);
          return info;
        });
    await creation.submit(value);
    expect(value.createdGroup?.groupID, 'stable');
    value.dispose();
  });
  test('lost create response recovers same group without another create',
      () async {
    var calls = 0;
    final value = draft();
    final creation = ChannelCreation(
        owner: 'self',
        id: 'stable',
        current: () => true,
        upload: (_) async => 'https://avatar',
        lookup: (_) async => [
              GroupInfo(
                  groupID: 'stable',
                  ownerUserID: 'self',
                  ex: channelEx(),
                  status: 3)
            ],
        mute: (_) async {},
        create: (_, __) async {
          calls++;
          throw StateError('network');
        });
    await expectLater(creation.submit(value), throwsStateError);
    await creation.submit(value);
    expect(calls, 1);
    expect(value.createdGroup?.groupID, 'stable');
    value.dispose();
  });
  test('mute retry does not recreate group', () async {
    var calls = 0, muteCalls = 0;
    final value = draft();
    final creation = ChannelCreation(
        owner: 'self',
        current: () => true,
        upload: (_) async => 'https://avatar',
        lookup: (_) async => [],
        create: (info, _) async {
          calls++;
          info.status = 0;
          return info;
        },
        mute: (_) async {
          if (++muteCalls == 1) throw StateError('network');
        });
    await expectLater(creation.submit(value), throwsStateError);
    await creation.submit(value);
    expect(calls, 1);
    expect(muteCalls, 2);
    value.dispose();
  });
  test('blocks duplicate submission and account switch during upload',
      () async {
    var active = true;
    final upload = Completer<String>();
    final value = draft();
    final creation = ChannelCreation(
        owner: 'self',
        current: () => active,
        upload: (_) => upload.future,
        lookup: (_) async => [],
        mute: (_) async {},
        create: (_, __) async => throw StateError('Must not create'));
    final pending = creation.submit(value);
    await expectLater(creation.submit(value), throwsStateError);
    active = false;
    upload.complete('https://avatar');
    await expectLater(pending, throwsStateError);
    expect(value.createdGroup, isNull);
    value.dispose();
  });
}
