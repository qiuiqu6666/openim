import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../composer/ai_assistant_draft.dart';
import '../data/ai_assistant_api.dart';
import '../data/ai_assistant_upload_mime.dart';
import '../models/ai_assistant_models.dart';
import '../presentation/composer/ai_assistant_file_kind.dart';

/// Native selection returns local references; upload belongs to an enabled API.
class AiAssistantAttachments {
  static Future<List<AiAssistantFileRef>> images() async {
    final images = await ImagePicker().pickMultiImage();
    if (images.length > AiAssistantUploadMime.maxFileCount) {
      throw const AiAssistantException('INVALID_INPUT', '一次最多添加3个附件');
    }
    final result = <AiAssistantFileRef>[];
    for (final image in images) {
      final size = await image.length();
      _checkSize(size);
      result.add(_file(image.name, size,
          path: image.path, bytes: kIsWeb ? await image.readAsBytes() : null));
    }
    return result;
  }

  static Future<List<AiAssistantFileRef>> files() async {
    final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: kIsWeb,
        type: FileType.custom,
        allowedExtensions: const [
          'pdf',
          'xls',
          'xlsx',
          'csv',
          'mp4',
          'mov',
          'webm',
          'jpg',
          'jpeg',
          'png',
          'gif',
          'webp'
        ]);
    if (result == null) return const [];
    if (result.files.length > AiAssistantUploadMime.maxFileCount) {
      throw const AiAssistantException('INVALID_INPUT', '一次最多添加3个附件');
    }
    return result.files.map((file) {
      _checkSize(file.size);
      return _file(file.name, file.size, path: file.path, bytes: file.bytes);
    }).toList(growable: false);
  }

  static void _checkSize(int size) {
    if (size <= 0 || size > AiAssistantUploadMime.maxBytes) {
      throw const AiAssistantException('INVALID_INPUT', '附件应大于0字节且不超过20MB');
    }
  }

  static AiAssistantFileRef _file(String name, int size,
          {String? path, Uint8List? bytes}) =>
      AiAssistantFileRef(
          name: name,
          sizeLabel: AiAssistantDraftFormats.bytes(size),
          kind: AiAssistantFileKinds.fromName(name),
          localPath: path,
          bytes: bytes,
          mimeType: AiAssistantUploadMime.fromName(name),
          sizeBytes: size);
}
