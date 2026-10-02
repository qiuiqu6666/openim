import 'package:openim/pages/mine/settings/chat_background_local_service.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/settings_draft_store.dart';

void main() {
  test('moments privacy keeps selected contact identity and display data', () {
    final store = SettingsDraftStore();
    addTearDown(store.dispose);

    store.replaceMomentsHiddenFrom(const [
      SettingsContactDraft(
        userId: 'u-1',
        displayName: 'Alice',
        avatarUrl: 'https://example.com/a.png',
      ),
    ]);

    expect(store.momentsHiddenFrom, hasLength(1));
    expect(store.momentsHiddenFrom['u-1']?.displayName, 'Alice');
    expect(store.momentsHiddenFrom['u-1']?.avatarUrl, 'https://example.com/a.png');
  });

  test('gallery chat background survives navigation draft and reset clears bytes', () {
    final store = SettingsDraftStore();
    addTearDown(store.dispose);
    final bytes = Uint8List.fromList(const [1, 2, 3]);

    store.setChatBackgroundGallery(bytes);

    expect(store.chatBackgroundId, 'gallery');
    expect(store.chatBackgroundImageBytes, same(bytes));

    store.resetChatBackground();

    expect(store.chatBackgroundId, 'default');
    expect(store.chatBackgroundImageBytes, isNull);
  });

  test('profile draft keeps nickname signature and avatar preview state', () {
    final store = SettingsDraftStore();
    addTearDown(store.dispose);

    store.seedProfile(nickname: 'OpenIM User', signature: 'Hello');
    expect(store.profileNickname, 'OpenIM User');
    expect(store.profileSignature, 'Hello');

    store.setProfileNickname('Alice');
    store.setProfileSignature('Keep moving');

    expect(store.profileNickname, 'Alice');
    expect(store.profileSignature, 'Keep moving');

    // Server seeding follows the loaded profile until the user edits locally;
    // after an edit, rebuilding MinePage must not overwrite the draft.
    store.seedProfile(nickname: 'Server Name', signature: 'Server Bio');
    expect(store.profileNickname, 'Alice');
    expect(store.profileSignature, 'Keep moving');
  });

  test('profile server fields keep seeding independently after one local edit', () {
    final store = SettingsDraftStore();
    addTearDown(store.dispose);

    store.setProfileSignature('Local bio');
    store.seedProfile(nickname: 'Loaded later', signature: 'Server bio');

    expect(store.profileNickname, 'Loaded later');
    expect(store.profileSignature, 'Local bio');

    store.setProfileNickname('Local name');
    store.seedProfile(nickname: 'New server name', signature: 'New server bio');

    expect(store.profileNickname, 'Local name');
    expect(store.profileSignature, 'Local bio');
  });

  test('chat background values keep legacy path compatibility and typed schemes', () {
    expect(
      ChatBackgroundLocalService.normalize('/tmp/a.jpg'),
      'file:/tmp/a.jpg',
    );
    expect(
      ChatBackgroundLocalService.assetOf(
        'asset:assets/images/chat_backgrounds/beauty.png',
      ),
      'assets/images/chat_backgrounds/beauty.png',
    );
    expect(
      ChatBackgroundLocalService.colorOf('color:fff1f1f1'),
      const Color(0xFFF1F1F1),
    );
  });

}
