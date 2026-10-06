import 'registration_avatar_service.dart';

/// Owned by the first step so going back keeps the local profile draft.
class RegistrationProfileDraft {
  String nickname = '';
  RegistrationAvatar? avatar;
}
