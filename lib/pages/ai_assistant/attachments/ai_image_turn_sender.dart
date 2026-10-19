import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:uuid/uuid.dart';
import '../../chat/media/upload/chat_media_upload.dart';
import '../models/ai_assistant_models.dart';
import '../protocol/ai_image_turn.dart';

class AiImageTurnUnsupported implements Exception {
  AiImageTurnUnsupported({this.generateImage = false});
  final bool generateImage;
}

/// Uploads are not messages. Any failed part leaves the entire draft unsent.
class AiImageTurnSender {
  AiImageTurnSender({
    required this.isCurrent,
    required this.preparePicture,
    Future<void> Function(Message)? upload,
    Future<List<PublicUserInfo>> Function()? profiles,
    Future<Message> Function(String)? create,
  })  : _upload = upload,
        _profiles = profiles ??
            (() => OpenIM.iMManager.userManager
                .getUsersInfo(userIDList: ['assistant'])),
        _create = create ??
            ((data) => OpenIM.iMManager.messageManager.createCustomMessage(
                data: data,
                extension: '',
                description: AiImageTurn.description));
  final bool Function() isCurrent;
  final Future<Message?> Function(String) preparePicture;
  final Future<void> Function(Message)? _upload;
  final Future<List<PublicUserInfo>> Function() _profiles;
  final Future<Message> Function(String) _create;

  void _check() {
    if (!isCurrent()) throw StateError('Assistant session changed');
  }

  Future<Message> prepare(String text, List<AiAssistantFileRef> files,
      {bool generateImage = false}) async {
    _check();
    if (text.trim().isEmpty ||
        text.runes.length > 8000 ||
        files.isEmpty ||
        files.length > 3 ||
        files.any((f) =>
            f.kind != AiAssistantFileKind.image ||
            f.localPath?.isNotEmpty != true)) {
      throw ArgumentError('Invalid image question');
    }
    final profiles = await _profiles().timeout(const Duration(seconds: 10));
    _check();
    if (!profiles.any((p) =>
        p.userID == 'assistant' &&
        AiImageTurn.supported(p.ex, generateImage: generateImage))) {
      throw AiImageTurnUnsupported(generateImage: generateImage);
    }
    final uploader =
        ChatMediaUpload(isClosed: () => !isCurrent(), onTransfer: (_, __) {});
    final images = <({String url, String name})>[];
    for (final file in files) {
      final image = await preparePicture(file.localPath!);
      _check();
      if (image == null) throw StateError('Image preparation failed');
      await (_upload ?? uploader.prepare)(image);
      _check();
      final url = image.pictureElem?.sourcePicture?.url;
      final uri = Uri.tryParse(url ?? '');
      if (uri == null ||
          !{'https', 'http'}.contains(uri.scheme) ||
          uri.host.isEmpty) {
        throw StateError('Image upload incomplete');
      }
      images.add((url: url!, name: file.name));
    }
    final message = await _create(AiImageTurn(
            turnID: const Uuid().v4(),
            text: text,
            images: images,
            generateImage: generateImage)
        .encode());
    _check();
    return message;
  }
}
