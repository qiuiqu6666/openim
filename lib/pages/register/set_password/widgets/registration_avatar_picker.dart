import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../widgets/auth/auth_copy.dart';
import '../../../../widgets/auth/auth_reference.dart';
import '../../widgets/register_reference_widgets.dart';

/// Presents the profile selection while the controller owns picking and upload.
class RegistrationAvatarPicker extends StatelessWidget {
  const RegistrationAvatarPicker({
    super.key,
    required this.bytes,
    required this.enabled,
    required this.picking,
    required this.onPick,
  });

  final Uint8List? bytes;
  final bool enabled;
  final bool picking;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final label = bytes == null
        ? authText('选择头像', 'Choose avatar')
        : authText('更换头像', 'Change avatar');
    final callback = enabled ? onPick : null;
    return Center(
      child: Column(
        children: [
          Tooltip(
            message: label,
            child: InkWell(
              key: const ValueKey('registration-avatar-pick'),
              onTap: callback,
              borderRadius: BorderRadius.circular(
                  RegistrationReferenceTokens.avatarRadius),
              child: CircleAvatar(
                key: const ValueKey('registration-avatar-preview'),
                radius: RegistrationReferenceTokens.avatarRadius,
                backgroundColor: AuthReferenceTokens.ink100,
                backgroundImage: bytes == null ? null : MemoryImage(bytes!),
                child: picking
                    ? const SizedBox(
                        width: RegistrationReferenceTokens.avatarIconSize,
                        height: RegistrationReferenceTokens.avatarIconSize,
                        child: CircularProgressIndicator(
                            color: AuthReferenceTokens.brand500),
                      )
                    : bytes == null
                        ? const Icon(Icons.add_a_photo_outlined,
                            size: RegistrationReferenceTokens.avatarIconSize,
                            color: AuthReferenceTokens.link)
                        : null,
              ),
            ),
          ),
          TextButton(
            key: const ValueKey('registration-avatar-action'),
            onPressed: callback,
            style:
                TextButton.styleFrom(foregroundColor: AuthReferenceTokens.link),
            child: Text(label),
          ),
        ],
      ),
    );
  }
}
