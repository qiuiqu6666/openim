import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'channel_tokens.dart';
import 'channel_ui.dart';

class ChannelAvatar extends StatelessWidget {
  const ChannelAvatar(
      {super.key,
      this.bytes,
      this.onChanged,
      this.size = ChannelTokens.avatar});
  final double size;
  final Uint8List? bytes;
  final ValueChanged<Uint8List>? onChanged;
  Future<void> _choose(BuildContext context) async {
    try {
      final file = await ImagePicker().pickImage(
          source: ImageSource.gallery, maxWidth: 1200, maxHeight: 1200);
      if (file == null) return;
      final data = await file.readAsBytes();
      if (context.mounted) onChanged?.call(data);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(channelText(context, '无法读取照片，请检查相册权限后重试',
                'Could not read the photo. Check photo permissions and try again.'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final face = CircleAvatar(
        radius: size / 2,
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).colorScheme.primaryContainer
            : ChannelTokens.avatarFill,
        backgroundImage: bytes == null ? null : MemoryImage(bytes!),
        child: bytes == null
            ? Icon(Icons.camera_alt_rounded,
                color: ChannelTokens.action(context), size: 34)
            : null);
    return onChanged == null
        ? face
        : IconButton(
            tooltip: channelText(context, '选择频道头像', 'Choose channel photo'),
            onPressed: () => _choose(context),
            padding: EdgeInsets.zero,
            icon: face);
  }
}
