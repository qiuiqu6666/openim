import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'formatted_message_page.dart';

enum ComposerMemberSelection { mention, directional }

typedef FormattedTextResult = ({String text, List<RichMessageInfo> entities});
typedef ComposerMemberPicker = Future<List<GroupMembersInfo>?> Function(
    GroupInfo group, ComposerMemberSelection operation);

class ChatTextComposition {
  const ChatTextComposition({
    required this.text,
    required this.mentions,
    this.quote,
  });

  final String text;
  final List<AtUserInfo> mentions;
  final Message? quote;
}

/// Owns one conversation's input resources, draft queue and composition state.
/// Transport, member navigation and page lifecycle remain injected boundaries.
class ChatComposerController {
  ChatComposerController({
    required this.conversationID,
    required this.currentUserID,
    required this.isGroupChat,
    required this.groupInfo,
    required this.sendingMuted,
    required this.sendMessage,
    required this.persistDraft,
    required this.selectMembers,
    required this.closeToolbox,
    required this.scrollBottom,
    required this.onTypingChanged,
    required this.showError,
    Future<Message> Function(ChatTextComposition)? createTextMessage,
    Future<FormattedTextResult?> Function(String)? editFormattedText,
    Future<Message> Function(FormattedTextResult, Message?)?
        createFormattedMessage,
    this.reportDraftError,
    bool Function()? isSessionInactive,
  })  : _createTextMessage = createTextMessage ?? _createSdkText,
        _editFormattedText = editFormattedText ?? _openFormattedEditor,
        _createFormattedMessage = createFormattedMessage ?? _createSdkFormatted,
        _isSessionInactive = isSessionInactive ?? (() => false);

  final String Function() conversationID;
  final String Function() currentUserID;
  final bool Function() isGroupChat;
  final GroupInfo? Function() groupInfo;
  final bool Function() sendingMuted;
  final Future<void> Function(Message) sendMessage;
  final Future<void> Function(String conversationID, String draft) persistDraft;
  final ComposerMemberPicker selectMembers;
  final VoidCallback closeToolbox;
  final VoidCallback scrollBottom;
  final ValueChanged<bool> onTypingChanged;
  final ValueChanged<String> showError;
  final ValueChanged<Object>? reportDraftError;
  final Future<Message> Function(ChatTextComposition) _createTextMessage;
  final Future<FormattedTextResult?> Function(String) _editFormattedText;
  final Future<Message> Function(FormattedTextResult, Message?)
      _createFormattedMessage;
  final bool Function() _isSessionInactive;

  final inputCtrl = TextEditingController();
  final focusNode = FocusNode();
  final quotedMessage = Rxn<Message>();
  final directionalUsers = <GroupMembersInfo>[].obs;
  final Map<String, String> _mentions = {};
  Timer? _draftTimer;
  Timer? _typingTimer;
  Future<void> _draftWrites = Future<void>.value();
  String _previousInput = '';
  bool _choosingMention = false;
  bool _restoringDraft = false;
  bool _initialized = false;
  bool _closed = false;
  bool _creatingText = false;
  bool _editingFormatted = false;
  int _inputRevision = 0;
  int _quoteRevision = 0;
  final _submittedInputs = Map<Message, ({int input, int quote})>.identity();

  bool get isClosed => _closed || _isSessionInactive();
  Map<String, String> get mentions => Map.unmodifiable(_mentions);
  Future<void> get pendingDraftWrites => _draftWrites;

  void initialize(String? draft) {
    if (_closed || _initialized) return;
    restoreDraft(draft);
    inputCtrl.addListener(_onInputChanged);
    focusNode.addListener(_onFocusChanged);
    _initialized = true;
  }

  void restoreDraft(String? draft) {
    if (_closed || draft == null || draft.isEmpty) return;
    var text = draft;
    _mentions.clear();
    try {
      final data = jsonDecode(draft);
      if (data is Map && data['text'] is String) {
        text = data['text'];
        final storedMentions = data['mentions'];
        if (storedMentions is Map) {
          for (final entry in storedMentions.entries) {
            if (entry.key is String && entry.value is String) {
              _mentions[entry.key] = entry.value;
            }
          }
        }
      }
    } catch (_) {/* Legacy drafts contain plain text. */}
    _restoringDraft = true;
    try {
      inputCtrl.value = TextEditingValue(
          text: text, selection: TextSelection.collapsed(offset: text.length));
      _previousInput = text;
    } finally {
      _restoringDraft = false;
    }
  }

  Future<void> saveDraft() {
    if (_closed) return _draftWrites;
    final text = inputCtrl.text;
    final draft =
        text.isEmpty ? '' : jsonEncode({'text': text, 'mentions': _mentions});
    final id = conversationID();
    _draftWrites = _draftWrites.then((_) => persistDraft(id, draft)).catchError(
      (Object error) {
        if (reportDraftError != null) {
          reportDraftError!(error);
        } else {
          Logger.print('Save conversation draft failed: $error');
        }
      },
    );
    return _draftWrites;
  }

  void _onInputChanged() {
    if (_closed || _restoringDraft) return;
    inputChanged();
    onTypingChanged(true);
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 1), () {
      if (!_closed) onTypingChanged(false);
    });
  }

  void inputChanged() {
    if (_closed || _restoringDraft) return;
    final text = inputCtrl.text;
    if (text == _previousInput) return;
    final old = _previousInput;
    _previousInput = text;
    _inputRevision++;
    _mentions.removeWhere((id, name) => !text.contains('@$name '));
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(saveDraft());
    });
    final cursor = inputCtrl.selection.baseOffset;
    if (isGroupChat() &&
        !_choosingMention &&
        text.length == old.length + 1 &&
        cursor > 0 &&
        cursor <= text.length &&
        text[cursor - 1] == '@') {
      unawaited(selectMentions(cursor - 1));
    }
  }

  Future<void> selectMentions(int start) async {
    final group = groupInfo();
    if (_closed || _choosingMention || group == null) return;
    _choosingMention = true;
    focusNode.unfocus();
    try {
      final selected =
          await selectMembers(group, ComposerMemberSelection.mention);
      if (_closed || selected == null || selected.isEmpty) return;
      final text = inputCtrl.text;
      if (start < 0 || start >= text.length || text[start] != '@') return;
      final inserted = selected
          .where((member) => member.userID != null)
          .map((member) => '@${member.nickname ?? member.userID} ')
          .join();
      inputCtrl.value = TextEditingValue(
        text: text.replaceRange(start, start + 1, inserted),
        selection: TextSelection.collapsed(offset: start + inserted.length),
      );
      for (final member in selected) {
        if (member.userID != null) {
          _mentions[member.userID!] = member.nickname ?? member.userID!;
        }
      }
      unawaited(saveDraft());
    } catch (error) {
      if (!_closed) showError(error.toString());
    } finally {
      _choosingMention = false;
      if (!_closed) focusNode.requestFocus();
    }
  }

  void mentionMessageSender(Message message) {
    final userID = message.sendID;
    if (_closed ||
        !isGroupChat() ||
        _choosingMention ||
        userID == null ||
        userID.isEmpty ||
        userID == currentUserID()) {
      return;
    }
    if (sendingMuted()) {
      showError(StrRes.youMuted);
      return;
    }
    final name = message.senderNickname?.trim().isNotEmpty == true
        ? message.senderNickname!.trim()
        : userID;
    final text = inputCtrl.text;
    final selection = inputCtrl.selection;
    final valid = selection.isValid && selection.end <= text.length;
    final start = valid ? selection.start : text.length;
    final end = valid ? selection.end : text.length;
    final inserted = '@$name ';
    _choosingMention = true;
    try {
      inputCtrl.value = TextEditingValue(
          text: text.replaceRange(start, end, inserted),
          selection: TextSelection.collapsed(offset: start + inserted.length));
      _mentions[userID] = name;
      unawaited(saveDraft());
    } finally {
      _choosingMention = false;
    }
    closeToolbox();
    focusNode.requestFocus();
  }

  Future<void> sendTextMsg() async {
    if (isClosed || _creatingText) return;
    if (sendingMuted()) {
      showError(StrRes.youMuted);
      return;
    }
    final content = IMUtils.safeTrim(inputCtrl.text);
    if (content.isEmpty) return;
    final quote = quotedMessage.value;
    final snapshot = (input: _inputRevision, quote: _quoteRevision);
    final mentions = isGroupChat()
        ? _mentions.entries
            .where((entry) => inputCtrl.text.contains('@${entry.value} '))
            .map((entry) =>
                AtUserInfo(atUserID: entry.key, groupNickname: entry.value))
            .toList()
        : <AtUserInfo>[];
    _creatingText = true;
    Message? message;
    try {
      try {
        message = await _createTextMessage(ChatTextComposition(
            text: content, mentions: mentions, quote: quote));
      } finally {
        // Native composition is serialized; network delivery does not block
        // composing the next message.
        _creatingText = false;
      }
      if (isClosed) return;
      if (sendingMuted()) {
        showError(StrRes.youMuted);
        return;
      }
      _submittedInputs[message] = snapshot;
      await sendMessage(message);
    } catch (error) {
      if (!isClosed) showError(error.toString());
    } finally {
      if (message != null) _submittedInputs.remove(message);
    }
  }

  void replyToMessage(Message message) {
    if (_closed) return;
    _quoteRevision++;
    quotedMessage.value = message;
    focusNode.requestFocus();
  }

  void clearReply() {
    if (!_closed) {
      _quoteRevision++;
      quotedMessage.value = null;
    }
  }

  void resetAfterSend(Message message) {
    final snapshot = _submittedInputs.remove(message);
    if (isClosed || snapshot == null) return;
    // A send only consumes the input and quote that created this message.
    // Forwarding and retries never own the current draft.
    if (snapshot.input == _inputRevision) {
      inputCtrl.clear();
      _mentions.clear();
      _draftTimer?.cancel();
      unawaited(saveDraft());
    }
    if (snapshot.quote == _quoteRevision) clearReply();
  }

  Future<void> onTapFormattedText() async {
    if (isClosed || _editingFormatted || _creatingText) return;
    closeToolbox();
    final quote = quotedMessage.value;
    final snapshot = (input: _inputRevision, quote: _quoteRevision);
    _editingFormatted = true;
    bool editorReleased = false;
    Message? message;
    try {
      final result = await _editFormattedText(inputCtrl.text);
      if (isClosed || result == null) return;
      if (sendingMuted()) {
        showError(StrRes.youMuted);
        return;
      }
      message = await _createFormattedMessage(result, quote);
      if (isClosed) return;
      if (sendingMuted()) {
        showError(StrRes.youMuted);
        return;
      }
      _submittedInputs[message] = snapshot;
      _editingFormatted = false;
      editorReleased = true;
      await sendMessage(message);
    } catch (error) {
      if (!isClosed) showError(error.toString());
    } finally {
      if (!editorReleased) _editingFormatted = false;
      if (message != null) _submittedInputs.remove(message);
    }
  }

  Future<void> onTapDirectionalMessage() async {
    final group = groupInfo();
    if (_closed || group == null) return;
    final members =
        await selectMembers(group, ComposerMemberSelection.directional);
    if (!_closed && members != null) directionalUsers.assignAll(members);
  }

  TextSpan? directionalText() {
    if (directionalUsers.isEmpty) return null;
    return TextSpan(
      text: '${StrRes.directedTo}:',
      style: Styles.ts_8E9AB0_14sp,
      children: [
        for (final member in directionalUsers)
          TextSpan(
            text:
                '${member.nickname ?? ''} ${directionalUsers.last == member ? '' : ','} ',
            style: Styles.ts_0089FF_14sp,
          ),
      ],
    );
  }

  void onClearDirectional() {
    if (!_closed) directionalUsers.clear();
  }

  void _onFocusChanged() {
    if (!_closed && focusNode.hasFocus) scrollBottom();
  }

  void dispose() {
    if (_closed) return;
    _draftTimer?.cancel();
    _typingTimer?.cancel();
    unawaited(saveDraft());
    _closed = true;
    _submittedInputs.clear();
    onTypingChanged(false);
    inputCtrl.removeListener(_onInputChanged);
    focusNode.removeListener(_onFocusChanged);
    inputCtrl.dispose();
    focusNode.dispose();
  }

  static Future<Message> _createSdkText(ChatTextComposition composition) {
    final manager = OpenIM.iMManager.messageManager;
    if (composition.mentions.isNotEmpty) {
      return manager.createTextAtMessage(
        text: composition.text,
        atUserIDList:
            composition.mentions.map((user) => user.atUserID!).toList(),
        atUserInfoList: composition.mentions,
        quoteMessage: composition.quote,
      );
    }
    return composition.quote == null
        ? manager.createTextMessage(text: composition.text)
        : manager.createQuoteMessage(
            text: composition.text, quoteMsg: composition.quote!);
  }

  static Future<FormattedTextResult?> _openFormattedEditor(String text) async =>
      Get.to<FormattedTextResult>(
          () => FormattedMessagePage(initialText: text));

  static Future<Message> _createSdkFormatted(
      FormattedTextResult result, Message? quote) {
    final manager = OpenIM.iMManager.messageManager;
    return quote == null
        ? manager.createAdvancedTextMessage(
            text: result.text, list: result.entities)
        : manager.createAdvancedQuoteMessage(
            text: result.text, list: result.entities, quoteMsg: quote);
  }
}
