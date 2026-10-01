# Local integration of voice_note_kit 1.3.3
Source: https://pub.dev/packages/voice_note_kit/versions/1.3.3
Original license is retained in LICENSE.

Local changes: permission_handler 11.3.1 compatibility (microphone API unchanged),
remove duplicate recorder start, serialize start/stop, guard late permission and
widget disposal, propagate native recorder errors, and remove cancelled files.
Application adapter checks actual audio duration, copies outgoing files and cancels
recording on background. Both chat entry points use the package recorder UI.
