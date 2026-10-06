import 'package:azlistview/azlistview.dart';
import 'package:flutter/foundation.dart';
import 'package:lpinyin/lpinyin.dart';

/// Only names and cached index fields cross the worker-isolate boundary.
/// SDK models and observable lists stay with ContactsLogic.
class ContactNameIndex {
  const ContactNameIndex({
    required this.userID,
    required this.displayName,
    this.namePinyin,
    this.tagIndex,
    this.showHeader = false,
  });

  final String userID;
  final String displayName;
  final String? namePinyin;
  final String? tagIndex;
  final bool showHeader;

  ContactNameIndex withHeader(bool show) => ContactNameIndex(
        userID: userID,
        displayName: displayName,
        namePinyin: namePinyin,
        tagIndex: tagIndex,
        showHeader: show,
      );
}

typedef ContactIndexWorker = Future<List<ContactNameIndex>> Function(
    List<ContactNameIndex> names);

/// Reuses pinyin for unchanged display names; sorts and indexes off the UI
/// isolate. The owner coalesces directory changes and closes this cache.
class ContactDirectoryIndexer {
  ContactDirectoryIndexer({ContactIndexWorker? worker})
      : _worker = worker ?? _computeIndex;

  final ContactIndexWorker _worker;
  final _cachedNames = <String, ContactNameIndex>{};
  int _generation = 0;
  bool _closed = false;

  Future<List<ContactNameIndex>?> build(List<ContactNameIndex> names) async {
    if (_closed) return null;
    final generation = ++_generation;
    final request = [
      for (final name in names)
        if (_cachedNames[name.userID]?.displayName == name.displayName)
          _cachedNames[name.userID]!
        else
          name,
    ];
    final indexed = await _worker(request);
    if (_closed || generation != _generation) return null;
    // Retain only the current directory, so deletions release cached names.
    _cachedNames
      ..clear()
      ..addEntries(indexed.map((entry) => MapEntry(entry.userID, entry)));
    return indexed;
  }

  void close() {
    _closed = true;
    _generation++;
    _cachedNames.clear();
  }

  static Future<List<ContactNameIndex>> _computeIndex(
          List<ContactNameIndex> names) =>
      compute(buildContactNameIndex, names, debugLabel: 'contacts-name-index');
}

class _IndexedContact extends ISuspensionBean {
  _IndexedContact(this.name);

  final ContactNameIndex name;

  @override
  String getSuspensionTag() => name.tagIndex!;
}

/// Pure worker entry point. Reuse the list's existing A–Z/# comparator and
/// header calculation, including its ordering within the same letter.
List<ContactNameIndex> buildContactNameIndex(List<ContactNameIndex> names) {
  final indexed = <_IndexedContact>[];
  final alphabet = RegExp(r'^[A-Z]$');
  for (var i = 0; i < names.length; i++) {
    final name = names[i];
    if (name.tagIndex != null) {
      indexed.add(_IndexedContact(name));
      continue;
    }
    final pinyin = PinyinHelper.getPinyinE(name.displayName).toUpperCase();
    final first = pinyin.trim().isEmpty ? '#' : pinyin.substring(0, 1);
    indexed.add(_IndexedContact(ContactNameIndex(
      userID: name.userID,
      displayName: name.displayName,
      namePinyin: pinyin.trim().isEmpty ? null : pinyin,
      tagIndex: alphabet.hasMatch(first) ? first : '#',
    )));
  }
  SuspensionUtil.sortListBySuspensionTag(indexed);
  SuspensionUtil.setShowSuspensionStatus(indexed);
  return [
    for (final entry in indexed) entry.name.withHeader(entry.isShowSuspension),
  ];
}
