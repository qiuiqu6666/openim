import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../chat/chat_logic.dart';
import '../../../chat/stickers/personal_sticker_panel.dart';
import '../../../chat/stickers/personal_sticker_store.dart';
import '../../../mine/settings/widgets/settings_widgets.dart';
import '../../attachments/ai_assistant_attachments.dart';
import '../../localization/ai_assistant_composer_hint.dart';
import '../../localization/ai_assistant_i18n.dart';
import '../../models/ai_assistant_models.dart';
import '../../picking/ai_assistant_picker.dart';
import '../../protocol/ai_openim_payload.dart';
import '../../theme/ai_palette.dart';
import 'ai_composer.dart';

/// Uses the chat's owned input, draft and SDK delivery lifecycle.
class AiOpenIMComposer extends StatefulWidget {
  const AiOpenIMComposer({super.key, required this.logic});

  final ChatLogic logic;

  @override
  State<AiOpenIMComposer> createState() => _AiOpenIMComposerState();
}

class _AiOpenIMComposerState extends State<AiOpenIMComposer> {
  late final String _owner;
  late final String? _imToken;
  late final String? _recipient;
  final _cards = <AiAssistantCardRef>[];
  final _files = <AiAssistantFileRef>[];
  String? _tool;
  bool _busy = false;

  ChatLogic get _logic => widget.logic;
  bool get _assistant => _recipient == 'assistant';
  bool get _current =>
      mounted &&
      !_logic.isClosed &&
      _owner.isNotEmpty &&
      _imToken?.isNotEmpty == true &&
      OpenIM.iMManager.userID == _owner &&
      DataSp.imToken == _imToken &&
      _logic.isSingleChat &&
      _recipient?.isNotEmpty == true &&
      _logic.userID == _recipient;
  bool get _canAct => _current && !_busy;

  @override
  void initState() {
    super.initState();
    _owner = OpenIM.iMManager.userID;
    _imToken = DataSp.imToken;
    _recipient = _logic.userID;
  }

  String _text(String zh, String en, [String? traditional]) =>
      AiAssistantI18n.of(context).t(zhHans: zh, zhHant: traditional, en: en);

  void _restoreInput(TextEditingValue value) {
    if (_current && _logic.inputCtrl.value != value) {
      _logic.inputCtrl.value = value;
    }
  }

  Future<void> _perform(Future<void> Function() action,
      {bool preserveInput = false}) async {
    if (!_canAct) return;
    final input = _logic.inputCtrl.value;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (_current) {
        _restoreInput(input);
        IMViews.showToast(
            _text('操作失败，请重试', 'Could not complete. Try again.', '操作失敗，請重試'));
      }
    } finally {
      if (preserveInput) _restoreInput(input);
      if (mounted) setState(() => _busy = false);
    }
  }

  void _selectTool(String tool) {
    if (!_canAct) return;
    final deselect = _tool == tool;
    setState(() => _tool = deselect ? null : tool);
    if (deselect) return;
    if (tool == 'summarize') {
      unawaited(_pickCard(AiCardPickerKind.conversation));
    } else if (tool == 'analyze') {
      unawaited(_pickFiles());
    } else {
      _logic.focusNode.requestFocus();
    }
  }

  Future<void> _pickCard(AiCardPickerKind kind) => _perform(() async {
        _logic.focusNode.unfocus();
        final card = await pickAiCard(context, kind: kind);
        if (!_current || card == null) return;
        setState(() {
          _cards
            ..clear()
            ..add(card);
        });
      }, preserveInput: true);

  Future<void> _pickImages() => _perform(() async {
        _logic.focusNode.unfocus();
        final files = await AiAssistantAttachments.images();
        if (!_current || files.isEmpty) return;
        _stageFiles(files);
      }, preserveInput: true);

  Future<void> _pickFiles() => _perform(() async {
        _logic.focusNode.unfocus();
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: AiOpenimPayload.documentExtensions,
          allowMultiple: true,
        );
        if (!_current || picked == null) return;
        final files = <AiAssistantFileRef>[];
        for (final file in picked.files) {
          if (!AiOpenimPayload.acceptsDocument(file.name, file.size)) {
            IMViews.showToast(_text(
                '仅支持不超过 20 MiB 的 PDF、DOCX、TXT 文件',
                'Choose a PDF, DOCX or TXT file up to 20 MiB.',
                '僅支援不超過 20 MiB 的 PDF、DOCX、TXT 檔案'));
            return;
          }
          if (file.path?.isNotEmpty != true) {
            IMViews.showToast(
                _text('无法读取所选文件', 'Cannot access this file.', '無法讀取所選檔案'));
            return;
          }
          files.add(AiAssistantFileRef(
            name: file.name,
            sizeLabel: '',
            kind: AiAssistantFileKind.text,
            localPath: file.path,
            sizeBytes: file.size,
          ));
        }
        _stageFiles(files);
      }, preserveInput: true);

  void _stageFiles(List<AiAssistantFileRef> files) {
    if (!_current) return;
    if (_files.length + files.length > 3) {
      IMViews.showToast(_text('一次最多添加 3 个附件',
          'Add up to 3 attachments at a time.', '一次最多添加 3 個附件'));
      return;
    }
    setState(() => _files.addAll(files));
  }

  /// Chat delivery records SDK failures on the message instead of throwing.
  Future<void> _checkedSend(int? type, Future Function() send,
      {VoidCallback? onRecorded}) async {
    final existing = Set<Message>.identity()..addAll(_logic.messageList);
    await send();
    if (!_current) return;
    final delivered = _logic.messageList.where((message) =>
        !existing.contains(message) &&
        message.sendID == _owner &&
        (type == null || message.contentType == type));
    // Once delivery has a timeline row, that row owns retry, even on failure.
    // Keeping a second staged draft would send it again with the next prompt.
    if (delivered.isNotEmpty) onRecorded?.call();
    if (delivered.isEmpty || delivered.last.status != MessageStatus.succeeded) {
      throw StateError('Message delivery failed');
    }
  }

  Future<void> _sendPrepared(Message message,
      {VoidCallback? onRecorded}) async {
    await _logic.sendPreparedMessage(message);
    if (!_current) return;
    if (_logic.messageList.any((record) =>
        record.clientMsgID == message.clientMsgID && record.sendID == _owner)) {
      onRecorded?.call();
    }
    if (message.status != MessageStatus.succeeded) {
      throw StateError('Message delivery failed');
    }
  }

  Future<void> _send() async {
    if (!_canAct) return;
    final input = _logic.inputCtrl.value;
    if (_tool != 'image' &&
        input.text.trim().isEmpty &&
        _cards.isEmpty &&
        _files.isEmpty) {
      return;
    }
    await _perform(() async {
      for (final card in List<AiAssistantCardRef>.of(_cards)) {
        if (!_current) return;
        void recorded() => setState(() => _cards.remove(card));
        if (card.kind == AiAssistantCardKind.friend) {
          if (_assistant) {
            // Assistant references need only SDK profile metadata. Do not
            // create a business friend invitation or authenticate with chatToken.
            final message = await OpenIM.iMManager.messageManager
                .createCardMessage(
                    userID: card.id,
                    nickname: card.name,
                    faceURL: card.faceUrl,
                    ex: '');
            if (!_current) return;
            await _sendPrepared(message, onRecorded: recorded);
          } else {
            await _checkedSend(
                MessageType.card,
                () => _logic.sendCarte(
                    userID: card.id,
                    nickname: card.name,
                    faceURL: card.faceUrl),
                onRecorded: recorded);
          }
        } else {
          await _checkedSend(
              MessageType.custom,
              () => _logic.sendCustomMsg(
                    data: AiOpenimPayload.groupCard(
                        groupID: card.id,
                        groupName: card.name,
                        faceURL: card.faceUrl),
                    extension: '',
                    description: 'groupCard',
                  ),
              onRecorded: recorded);
        }
      }
      for (final file in List<AiAssistantFileRef>.of(_files)) {
        if (!_current) return;
        void recorded() => setState(() => _files.remove(file));
        final path = file.localPath;
        if (path == null || path.isEmpty) throw StateError('File unavailable');
        if (file.kind == AiAssistantFileKind.image) {
          await _checkedSend(
              MessageType.picture, () => _logic.sendPicture(path: path),
              onRecorded: recorded);
        } else {
          final message = await OpenIM.iMManager.messageManager
              .createFileMessageFromFullPath(
                  filePath: path, fileName: file.name);
          if (!_current) return;
          await _sendPrepared(message, onRecorded: recorded);
        }
      }
      if (!_current) return;
      _restoreInput(input);
      if (_tool == 'image') {
        await _checkedSend(
            MessageType.custom,
            () => _logic.sendCustomMsg(
                  data: AiOpenimPayload.image(input.text),
                  extension: '',
                  description: 'image',
                ));
        if (_current) _logic.inputCtrl.clear();
      } else if (input.text.trim().isNotEmpty) {
        await _checkedSend(null, _logic.sendTextMsg);
      }
    });
  }

  Future<void> _more() async {
    if (!_canAct) return;
    _logic.focusNode.unfocus();
    final action = await showSettingsActionSheet<String>(
      context,
      title: '',
      actions: [
        SettingsAction(_text('好友名片', 'Friend card'), 'friend'),
        if (_assistant) SettingsAction(_text('群聊名片', 'Group card'), 'group'),
        SettingsAction(_text('收藏', 'Favorites', '收藏'), 'favorite'),
        SettingsAction(_text('表情', 'Stickers'), 'sticker'),
      ],
    );
    if (!_canAct) return;
    switch (action) {
      case 'friend':
        await _pickCard(AiCardPickerKind.friend);
      case 'group':
        await _pickCard(AiCardPickerKind.group);
      case 'favorite':
        await _perform(_logic.onTapFavorites, preserveInput: true);
      case 'sticker':
        await _showStickers();
    }
  }

  Future<void> _sendSticker(PersonalSticker sticker) async {
    if (!_canAct) return;
    if (sticker.isVideo) {
      IMViews.showToast(_text('助理暂不支持视频表情',
          'The assistant cannot read video stickers.', '助理暫不支援影片表情'));
      return;
    }
    await _perform(() async {
      final message = await OpenIM.iMManager.messageManager
          .createFaceMessage(index: -1, data: sticker.mediaURL);
      if (!_current) return;
      await _logic.sendPreparedMessage(message);
      if (_current && message.status != MessageStatus.succeeded) {
        throw StateError('Message delivery failed');
      }
    }, preserveInput: true);
  }

  Future<void> _showStickers() async {
    if (!_canAct) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor:
          AiPalette.cardBg(Theme.of(context).brightness == Brightness.dark),
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height / 2,
        child: PersonalStickerPanel(
          store: _logic.personalStickers,
          onAdd: () => _perform(_logic.addPersonalSticker, preserveInput: true),
          onSend: _sendSticker,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final i18n = AiAssistantI18n.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Obx(() {
          final quote = _logic.quotedMessage.value;
          if (quote == null) return const SizedBox.shrink();
          final excerpt = quote.textElem?.content ??
              quote.atTextElem?.text ??
              quote.quoteElem?.text ??
              _text('[消息]', '[Message]', '[訊息]');
          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: AiMetrics.space16),
            leading: Icon(Icons.reply_rounded,
                size: AiMetrics.dimension20, color: AiPalette.brand(dark)),
            title: Text(
              '${quote.senderNickname ?? _logic.nickname.value}: $excerpt',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: AiPalette.secondary(dark), fontSize: AiMetrics.font13),
            ),
            trailing: IconButton(
              tooltip: _text('取消引用', 'Cancel reply'),
              onPressed: _canAct ? _logic.clearReply : null,
              icon: Icon(Icons.close_rounded, color: AiPalette.secondary(dark)),
            ),
          );
        }),
        if (_cards.isNotEmpty || _files.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AiMetrics.space16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: AiMetrics.space8,
                runSpacing: AiMetrics.space4,
                children: [
                  for (final card in _cards)
                    _draftChip(
                        card.name,
                        card.kind == AiAssistantCardKind.friend
                            ? Icons.person_outline
                            : Icons.group_outlined,
                        () => setState(() => _cards.remove(card))),
                  for (final file in _files)
                    _draftChip(
                        file.name,
                        file.kind == AiAssistantFileKind.image
                            ? Icons.image_outlined
                            : Icons.description_outlined,
                        () => setState(() => _files.remove(file))),
                ],
              ),
            ),
          ),
        if (_assistant)
          AiQuickChipBar(
            dark: dark,
            i18n: i18n,
            selectedId: _tool,
            enabled: _canAct,
            onSelected: _selectTool,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AiMetrics.space12,
              AiMetrics.space0, AiMetrics.space12, AiMetrics.space12),
          child: AiInputBar(
            dark: dark,
            hint: _tool == null
                ? _assistant
                    ? _text('问 AI助理…', 'Ask the AI assistant…', '問 AI助理…')
                    : _text('输入消息…', 'Write a message…', '輸入訊息…')
                : aiAssistantComposerHint(i18n, _tool),
            controller: _logic.inputCtrl,
            focusNode: _logic.focusNode,
            enabled: _canAct,
            loading: _busy,
            maxLines: 4,
            replying: false,
            addLabel: _text('更多附件', 'More attachments'),
            imageLabel: _text('选择图片', 'Select images', '選擇圖片'),
            attachLabel: _text('选择文件', 'Select documents', '選擇檔案'),
            submitLabel: _text('发送', 'Send', '傳送'),
            onAdd: () => unawaited(_more()),
            onImage: () => unawaited(_pickImages()),
            onAttach: () => unawaited(_pickFiles()),
            onSubmit: () => unawaited(_send()),
            onStop: () {},
          ),
        ),
      ],
    );
  }

  Widget _draftChip(String label, IconData icon, VoidCallback remove) =>
      ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width - AiMetrics.space32),
        child: InputChip(
          avatar: Icon(icon, size: AiMetrics.dimension18),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          deleteButtonTooltipMessage: _text('移除附件', 'Remove attachment'),
          onDeleted: _canAct ? remove : null,
        ),
      );
}
