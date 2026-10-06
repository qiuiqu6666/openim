import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../contacts/contacts_logic.dart';
import '../../conversation/conversation_logic.dart';
import '../models/ai_assistant_models.dart';
import 'ai_assistant_picker_tokens.dart';

enum AiCardPickerKind { friend, group, conversation }

/// Returns reference metadata only. Picking never sends a card or a message.
Future<AiAssistantCardRef?> pickAiCard(
  BuildContext context, {
  required AiCardPickerKind kind,
}) async {
  final owner = OpenIM.iMManager.userID;
  final token = DataSp.imToken;
  if (owner.isEmpty || token == null || token.isEmpty) return null;
  final result = await Navigator.of(context).push<AiAssistantCardRef>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _AiCardPicker(kind: kind, owner: owner, token: token),
    ),
  );
  return OpenIM.iMManager.userID == owner && DataSp.imToken == token
      ? result
      : null;
}

class _AiCardPicker extends StatefulWidget {
  const _AiCardPicker({
    required this.kind,
    required this.owner,
    required this.token,
  });

  final AiCardPickerKind kind;
  final String owner;
  final String token;

  @override
  State<_AiCardPicker> createState() => _AiCardPickerState();
}

class _AiCardPickerState extends State<_AiCardPicker>
    with WidgetsBindingObserver {
  final _search = TextEditingController();
  final _workers = <Worker>[];
  ContactsLogic? _contacts;
  ConversationLogic? _conversations;
  List<AiAssistantCardRef> _items = const [];
  String _query = '';
  bool _loading = false;
  bool _failed = false;
  bool _finished = false;
  bool _opening = false;
  int _generation = 0;

  bool get _current =>
      mounted &&
      OpenIM.iMManager.userID == widget.owner &&
      DataSp.imToken == widget.token;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.kind == AiCardPickerKind.group) {
      unawaited(_loadGroups());
      return;
    }
    if (widget.kind == AiCardPickerKind.friend &&
        Get.isRegistered<ContactsLogic>()) {
      _contacts = Get.find<ContactsLogic>();
      _workers.add(ever(_contacts!.friends, (_) => _cacheChanged()));
      _workers.add(ever(_contacts!.friendsLoading, (_) => _cacheChanged()));
    } else if (widget.kind == AiCardPickerKind.conversation &&
        Get.isRegistered<ConversationLogic>()) {
      _conversations = Get.find<ConversationLogic>();
      _workers.add(ever(_conversations!.list, (_) => _cacheChanged()));
    }
    _readCache();
  }

  void _readCache() {
    if (!_current) {
      _items = const [];
      _loading = false;
      return;
    }
    final contacts = _contacts;
    final conversations = _conversations;
    if (widget.kind == AiCardPickerKind.friend) {
      _failed = contacts == null || !contacts.isCurrentSession;
      _loading = !_failed && contacts!.friendsLoading.value;
      _items = _failed
          ? const []
          : contacts!.friends
              .where((friend) => (friend.userID ?? '').trim().isNotEmpty)
              .map((friend) => AiAssistantCardRef(
                    kind: AiAssistantCardKind.friend,
                    id: friend.userID!.trim(),
                    name: friend.showName.trim().isEmpty
                        ? friend.userID!.trim()
                        : friend.showName.trim(),
                    faceUrl: friend.faceURL?.trim() ?? '',
                  ))
              .toList(growable: false);
    } else {
      _failed = conversations == null || !conversations.isSessionActive;
      _items = _failed
          ? const []
          : conversations!.list
              .where((item) => item.isSingleChat || item.isGroupChat)
              .map(_conversationCard)
              .whereType<AiAssistantCardRef>()
              .toList(growable: false);
    }
  }

  AiAssistantCardRef? _conversationCard(ConversationInfo item) {
    final id = (item.isSingleChat ? item.userID : item.groupID)?.trim() ?? '';
    if (id.isEmpty) return null;
    final name = item.showName?.trim() ?? '';
    return AiAssistantCardRef(
      kind: item.isSingleChat
          ? AiAssistantCardKind.friend
          : AiAssistantCardKind.group,
      id: id,
      name: name.isEmpty ? id : name,
      faceUrl: item.faceURL?.trim() ?? '',
    );
  }

  void _cacheChanged() {
    if (!mounted) return;
    setState(_readCache);
  }

  Future<void> _loadGroups() async {
    if (!_current || _loading) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final groups = await OpenIM.iMManager.groupManager.getJoinedGroupList();
      if (!_current || generation != _generation) return;
      final byId = <String, AiAssistantCardRef>{};
      for (final group in groups) {
        final id = group.groupID.trim();
        if (id.isEmpty) continue;
        final name = group.groupName?.trim() ?? '';
        byId[id] = AiAssistantCardRef(
          kind: AiAssistantCardKind.group,
          id: id,
          name: name.isEmpty ? id : name,
          faceUrl: group.faceURL?.trim() ?? '',
        );
      }
      setState(() => _items = byId.values.toList(growable: false));
    } catch (_) {
      if (_current && generation == _generation) {
        setState(() => _failed = true);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          if (!_current) _items = const [];
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    setState(() {
      if (!_current) {
        _items = const [];
      } else if (widget.kind != AiCardPickerKind.group) {
        _readCache();
      }
    });
  }

  void _complete(AiAssistantCardRef card) {
    if (!_current || _finished) return;
    _finished = true;
    Navigator.of(context).pop(card);
  }

  Future<void> _openCategory(AiCardPickerKind kind) async {
    if (!_current || _opening || _finished) return;
    _opening = true;
    try {
      final card = await pickAiCard(context, kind: kind);
      if (_current && card != null) _complete(card);
    } finally {
      _opening = false;
    }
  }

  String _text(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  String get _title => switch (widget.kind) {
        AiCardPickerKind.friend => _text('选择朋友', 'Select Friend'),
        AiCardPickerKind.group => _text('选择群聊', 'Select Group'),
        AiCardPickerKind.conversation => _text('选择会话', 'Select Chat'),
      };

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    for (final worker in _workers) {
      worker.dispose();
    }
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = AppTokens.surface(dark: dark);
    final text = AppTokens.textPrimary(dark: dark);
    final subText = AppTokens.textSecondary(dark: dark);
    final query = _query.trim().toLowerCase();
    final items = !_current
        ? const <AiAssistantCardRef>[]
        : _items
            .where((card) =>
                query.isEmpty ||
                card.name.toLowerCase().contains(query) ||
                card.id.toLowerCase().contains(query))
            .toList(growable: false);
    return Scaffold(
      backgroundColor: surface,
      appBar: GlassAppBar(
        toolbarHeight: kToolbarHeight,
        backgroundColor: surface,
        centerTitle: true,
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          icon: Icon(Icons.close_rounded, color: text),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_title,
            style: TextStyle(
                color: text,
                fontSize: AiAssistantPickerTokens.titleSize,
                fontWeight: FontWeight.w600)),
      ),
      body: SafeArea(
        top: false,
        child: Column(children: [
          SearchBox(
            controller: _search,
            enabled: _current,
            height: (MediaQuery.textScalerOf(context)
                        .scale(AiAssistantPickerTokens.rowTextSize) +
                    AppTokens.s7)
                .clamp(AiAssistantPickerTokens.searchHeight, double.infinity),
            margin: const EdgeInsets.fromLTRB(
                AppTokens.s5, AppTokens.s3, AppTokens.s5, AppTokens.s4),
            borderRadius:
                BorderRadius.circular(AiAssistantPickerTokens.searchRadius),
            backgroundColor: AppTokens.surfaceAlt(dark: dark),
            searchIconColor: subText,
            textStyle: TextStyle(
                color: text, fontSize: AiAssistantPickerTokens.rowTextSize),
            hintStyle: TextStyle(
                color: subText, fontSize: AiAssistantPickerTokens.rowTextSize),
            hintText: _text('搜索', 'Search'),
            onChanged: (value) => setState(() => _query = value),
            onCleared: () => setState(() => _query = ''),
          ),
          if (widget.kind == AiCardPickerKind.conversation && _current) ...[
            _category(Icons.person_outline_rounded,
                _text('选择朋友', 'Select Friend'), AiCardPickerKind.friend),
            _category(Icons.group_outlined, _text('选择群聊', 'Select Group'),
                AiCardPickerKind.group),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppTokens.s5, AppTokens.s4, AppTokens.s5, AppTokens.s3),
                child: Text(_text('最近', 'Recent'),
                    style: TextStyle(
                        color: subText,
                        fontSize: AiAssistantPickerTokens.headerTextSize)),
              ),
            ),
          ],
          Expanded(
            child: !_current
                ? _status(
                    _text('账户已切换，请重新打开', 'Account changed. Please reopen.'),
                    subText)
                : _loading && items.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : _failed
                        ? Center(
                            child: TextButton(
                              onPressed: widget.kind == AiCardPickerKind.group
                                  ? _loadGroups
                                  : _cacheChanged,
                              child: Text(_text('列表加载失败，点击重试',
                                  'Could not load the list. Retry')),
                            ),
                          )
                        : items.isEmpty
                            ? _status(
                                query.isEmpty
                                    ? _text('暂无可选择的记录', 'Nothing to select')
                                    : _text('未找到相关结果', 'No matching results'),
                                subText)
                            : ListView.separated(
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                itemCount: items.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: AiAssistantPickerTokens.dividerWidth,
                                  thickness:
                                      AiAssistantPickerTokens.dividerWidth,
                                  indent: AppTokens.s5 +
                                      AiAssistantPickerTokens.avatarSize +
                                      AppTokens.s4,
                                  color: AppTokens.border(dark: dark),
                                ),
                                itemBuilder: (_, index) {
                                  final card = items[index];
                                  return ListTile(
                                    key: ValueKey(
                                        '${card.kind.name}:${card.id}'),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: AppTokens.s5,
                                        vertical: AppTokens.s2),
                                    leading: AvatarView(
                                      url: card.faceUrl,
                                      text: card.name,
                                      isGroup: card.kind ==
                                          AiAssistantCardKind.group,
                                      width: AiAssistantPickerTokens.avatarSize,
                                      height:
                                          AiAssistantPickerTokens.avatarSize,
                                    ),
                                    title: Text(card.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: text,
                                            fontSize: AiAssistantPickerTokens
                                                .rowTextSize)),
                                    onTap: () => _complete(card),
                                  );
                                },
                              ),
          ),
        ]),
      ),
    );
  }

  Widget _status(String message, Color color) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.s7),
          child: Text(message,
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: color, fontSize: AppTokens.captionFontSize)),
        ),
      );

  Widget _category(IconData icon, String label, AiCardPickerKind kind) =>
      ListTile(
        leading: Icon(icon, color: AppTokens.accent),
        title: Text(label,
            style: TextStyle(
                color: AppTokens.textPrimary(
                    dark: Theme.of(context).brightness == Brightness.dark),
                fontSize: AppTokens.listTitleFontSize)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => unawaited(_openCategory(kind)),
      );
}
