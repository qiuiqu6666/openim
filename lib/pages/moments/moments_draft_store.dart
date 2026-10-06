import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:openim_common/openim_common.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../services/moments_repository.dart';

class MomentsVisibilitySelection {
  const MomentsVisibilitySelection(
      {this.mode = 'FRIENDS', this.audienceUserIds = const []});
  final String mode;
  final List<String> audienceUserIds;
  bool get requiresAudience => mode == 'PARTIAL' || mode == 'EXCLUDE';
  Map<String, dynamic> toJson() => {
        'mode': mode,
        'audienceUserIds': requiresAudience ? audienceUserIds : <String>[],
      };
  factory MomentsVisibilitySelection.fromJson(Map<String, dynamic> json) {
    final mode = json['mode'];
    if (!const ['SELF', 'FRIENDS', 'PARTIAL', 'EXCLUDE'].contains(mode)) {
      throw const FormatException('Invalid moments visibility');
    }
    return MomentsVisibilitySelection(
      mode: mode as String,
      audienceUserIds:
          List<String>.from(json['audienceUserIds'] as List? ?? const [])
              .where((id) => id.isNotEmpty)
              .toSet()
              .toList(),
    );
  }
}

class MomentsDraftMedia {
  MomentsDraftMedia(
      {required this.clientMediaId,
      required this.path,
      this.uploadPath,
      this.mediaId});
  final String clientMediaId;
  final String path;
  String? uploadPath;
  String? mediaId;
  double progress = 0;
  Map<String, dynamic> toJson() => {
        'clientMediaId': clientMediaId,
        'path': path,
        'uploadPath': uploadPath,
        'mediaId': mediaId,
      };
  factory MomentsDraftMedia.fromJson(Map<String, dynamic> json) =>
      MomentsDraftMedia(
        clientMediaId: json['clientMediaId'] as String,
        path: json['path'] as String,
        uploadPath: json['uploadPath'] as String?,
        mediaId: json['mediaId'] as String?,
      );
}

enum MomentsPublishStage {
  draft,
  preparing,
  uploading,
  readyToCommit,
  submitting,
  submitUnknown,
  uploadFailed,
  submitFailed,
  awaitingAuth,
}

/// One immutable publish attempt. Never replace its key after a timeout.
class MomentsPublishJob {
  MomentsPublishJob(
      {required this.clientRequestID,
      required this.text,
      required this.visibility,
      required this.mediaOrder,
      this.submitted = false});
  final String clientRequestID;
  final String text;
  final MomentsVisibilitySelection visibility;
  final List<String> mediaOrder;
  bool submitted;
  Map<String, dynamic> toJson() => {
        'clientRequestID': clientRequestID,
        'text': text,
        'visibility': visibility.toJson(),
        'mediaOrder': mediaOrder,
        'submitted': submitted,
      };
  factory MomentsPublishJob.fromJson(Map<String, dynamic> json) =>
      MomentsPublishJob(
        clientRequestID: json['clientRequestID'] as String,
        text: json['text'] as String,
        visibility: MomentsVisibilitySelection.fromJson(
            Map<String, dynamic>.from(json['visibility'] as Map)),
        mediaOrder: List<String>.from(json['mediaOrder'] as List),
        submitted: json['submitted'] == true,
      );
}

typedef MomentsDraftReader = Future<Map<String, dynamic>?> Function();
typedef MomentsDraftWriter = Future<void> Function(Map<String, dynamic>? value);

/// Account-owned draft and durable publish worker. Pages only observe this store.
class MomentsDraftStore extends ChangeNotifier {
  MomentsDraftStore(
      {required this.repository,
      MomentsDraftReader? read,
      MomentsDraftWriter? write,
      Future<Directory> Function()? directory,
      Future<File?> Function(File)? compress})
      : ownerUserId = repository.currentUserId,
        serviceKey = repository.baseUrl,
        sessionScope = repository.sessionScope,
        _read = read,
        _write = write,
        _directory = directory,
        _compress = compress ?? IMUtils.compressImageAndGetFile {
    repository.addListener(_sessionChanged);
  }

  static final Map<String, MomentsDraftStore> _stores = {};
  static MomentsDraftStore forRepository(MomentsRepository repository) {
    final scope = repository.sessionScope;
    for (final entry in _stores.entries.toList()) {
      if (entry.key != scope) {
        entry.value.dispose();
        _stores.remove(entry.key);
      }
    }
    return _stores.putIfAbsent(
        scope, () => MomentsDraftStore(repository: repository));
  }

  final MomentsRepository repository;
  final String ownerUserId;
  final String serviceKey;
  final String sessionScope;
  final MomentsDraftReader? _read;
  final MomentsDraftWriter? _write;
  final Future<Directory> Function()? _directory;
  final Future<File?> Function(File) _compress;
  String text = '';
  MomentsVisibilitySelection visibility = const MomentsVisibilitySelection();
  final List<MomentsDraftMedia> media = [];
  MomentsPublishJob? job;
  MomentsPublishStage stage = MomentsPublishStage.draft;
  Object? error;
  Object? persistenceError;
  MomentPost? lastPublished;
  String? confirmedMomentId;
  bool recoveryFailed = false;
  bool loaded = false;
  bool _closed = false;
  bool _cancelRequested = false;
  Future<void>? _loading;
  Future<MomentPost?>? _work;
  Future<void>? _writes;
  CancelToken? _uploadCancel;
  Directory? _ownedDirectory;
  bool get sessionCurrent =>
      !_closed && repository.isSessionCurrent(sessionScope);
  bool get busy => _work != null;
  bool get frozen => job != null;
  bool get resultUncertain =>
      job?.submitted == true && stage != MomentsPublishStage.submitFailed;
  bool get hasContent => text.trim().isNotEmpty || media.isNotEmpty;
  String get cacheKey =>
      'momentsDraft:${Uri.encodeComponent(serviceKey)}:${Uri.encodeComponent(ownerUserId)}';

  void _changed() {
    if (!_closed) notifyListeners();
  }

  void _checkSession() {
    if (!sessionCurrent) throw StateError('Moments session changed');
    if (_cancelRequested) throw StateError('Moments upload cancelled');
  }

  void _sessionChanged() {
    if (sessionCurrent) return;
    _uploadCancel?.cancel();
    _changed();
  }

  Future<void> load() => loaded ? Future.value() : _readDraft();

  /// Re-read the original record; never replace an unreadable publish task.
  Future<void> retryRecovery() {
    if (!sessionCurrent || !recoveryFailed) return Future.value();
    return _readDraft();
  }

  Future<void> _readDraft() {
    if (_loading != null) return _loading!;
    loaded = false;
    _changed();
    return _loading = _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    try {
      final saved =
          _read != null ? await _read() : SpUtil().getObject(cacheKey);
      _checkSession();
      if (saved != null) {
        final json = Map<String, dynamic>.from(saved);
        if (json['owner'] != ownerUserId || json['service'] != serviceKey) {
          throw const FormatException('Draft belongs to another account');
        }
        final restoredText = json['text'] as String? ?? '';
        final restoredVisibility = MomentsVisibilitySelection.fromJson(
            Map<String, dynamic>.from(json['visibility'] as Map));
        final restored = (json['media'] as List? ?? const [])
            .map((item) => MomentsDraftMedia.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList();
        if (restored.length > 9 ||
            restored.any((m) => m.path.isEmpty || m.clientMediaId.isEmpty)) {
          throw const FormatException('Invalid draft media');
        }
        MomentsPublishJob? restoredJob;
        if (json['job'] != null) {
          restoredJob = MomentsPublishJob.fromJson(
              Map<String, dynamic>.from(json['job'] as Map));
          if (restoredJob.clientRequestID.isEmpty ||
              restoredJob.mediaOrder.length != restored.length ||
              restoredJob.mediaOrder.toSet().length != restored.length ||
              restoredJob.mediaOrder
                  .any((id) => !restored.any((m) => m.clientMediaId == id))) {
            throw const FormatException('Incomplete publish task');
          }
        }
        // Parse and validate the complete record before exposing any content.
        text = restoredText;
        visibility = restoredVisibility;
        media
          ..clear()
          ..addAll(restored);
        job = restoredJob;
        stage = restoredJob != null
            ? restoredJob.submitted
                ? MomentsPublishStage.submitUnknown
                : MomentsPublishStage.uploadFailed
            : MomentsPublishStage.draft;
      }
      persistenceError = null;
      recoveryFailed = false;
    } catch (e) {
      persistenceError = e;
      recoveryFailed = true;
    }
    loaded = true;
    _changed();
  }

  Map<String, dynamic> _snapshot() => {
        'version': 1,
        'owner': ownerUserId,
        'service': serviceKey,
        'text': text,
        'visibility': visibility.toJson(),
        'media': media.map((m) => m.toJson()).toList(),
        'job': job?.toJson(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };
  Future<void> save() {
    if (!sessionCurrent) return Future.value();
    if (!loaded || recoveryFailed) {
      return Future.error(StateError('Draft recovery failed'));
    }
    final snapshot = !hasContent && job == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(jsonEncode(_snapshot())) as Map);
    final next =
        (_writes ?? Future<void>.value()).catchError((_) {}).then((_) async {
      if (_write != null) {
        await _write(snapshot);
      } else {
        final success = snapshot == null
            ? await SpUtil().remove(cacheKey)
            : await SpUtil().putObject(cacheKey, snapshot);
        if (success != true) throw StateError('Could not save moments draft');
      }
    });
    _writes = next;
    return next.then((_) {
      if (identical(_writes, next)) _writes = null;
      persistenceError = null;
    }, onError: (Object e, StackTrace stack) {
      if (identical(_writes, next)) _writes = null;
      persistenceError = e;
      _changed();
      Error.throwWithStackTrace(e, stack);
    });
  }

  void updateText(String value) {
    if (!loaded || recoveryFailed || frozen || !sessionCurrent) return;
    text = value;
    error = null;
    _changed();
  }

  Future<void> updateVisibility(MomentsVisibilitySelection value) async {
    if (!loaded || recoveryFailed || frozen || !sessionCurrent) return;
    visibility = value;
    _changed();
    await save();
  }

  Future<Directory> _mediaDirectory() async {
    if (_ownedDirectory != null) return _ownedDirectory!;
    final base = _directory != null
        ? await _directory()
        : Directory(p.join(
            (await getApplicationSupportDirectory()).path,
            'moments',
            'drafts',
            const Uuid().v5(Namespace.url.value, '$serviceKey\n$ownerUserId')));
    await base.create(recursive: true);
    _ownedDirectory = base;
    return base;
  }

  Future<void> addFiles(List<File> files, {int maxImages = 9}) async {
    if (!loaded || recoveryFailed || frozen || !sessionCurrent) return;
    final directory = await _mediaDirectory();
    _checkSession();
    for (final file in files) {
      if (media.length >= maxImages.clamp(0, 9)) break;
      final ext = p.extension(file.path).toLowerCase();
      if (!const ['.jpg', '.jpeg', '.png', '.webp'].contains(ext)) {
        throw const FormatException(
            'Only JPEG, PNG and WebP images are supported');
      }
      final id = const Uuid().v4();
      final retained = await file.copy(p.join(directory.path, '$id$ext'));
      if (!sessionCurrent || frozen) {
        await retained.delete();
        return;
      }
      media.add(MomentsDraftMedia(clientMediaId: id, path: retained.path));
      _changed();
      await save();
    }
  }

  Future<void> removeMedia(String id) async {
    if (!loaded || recoveryFailed || frozen || !sessionCurrent) return;
    final item = media.firstWhere((m) => m.clientMediaId == id);
    media.remove(item);
    _changed();
    await save();
    await _deleteOwnedFiles([item]);
  }

  Future<void> moveMedia(String id, int newIndex) async {
    if (!loaded || recoveryFailed || frozen || !sessionCurrent) return;
    final old = media.indexWhere((m) => m.clientMediaId == id);
    if (old < 0 ||
        newIndex < 0 ||
        newIndex >= media.length ||
        old == newIndex) {
      return;
    }
    final item = media.removeAt(old);
    media.insert(newIndex, item);
    _changed();
    await save();
  }

  Future<MomentPost?> publish() {
    if (_work != null) return _work!;
    if (!sessionCurrent) {
      return Future.error(StateError('Moments session changed'));
    }
    if (!loaded || recoveryFailed) {
      return Future.error(StateError('Draft recovery failed'));
    }
    _cancelRequested = false;
    return _work = _publish().whenComplete(() {
      _work = null;
      _changed();
    });
  }

  Future<MomentPost?> _publish() async {
    var reconciling =
        job?.submitted == true && stage != MomentsPublishStage.submitFailed;
    try {
      error = null;
      final capabilities = await repository.ensureCapabilities();
      _checkSession();
      if (!capabilities.publishEnabled) {
        throw const MomentsException('Moments publishing is not enabled',
            unavailable: true);
      }
      if (job == null) {
        confirmedMomentId = null;
        final trimmed = text.trim();
        if (trimmed.isEmpty && media.isEmpty) {
          throw const FormatException('Please add text or images');
        }
        if (trimmed.runes.length > capabilities.maxTextLength ||
            media.length > capabilities.maxImages.clamp(0, 9)) {
          throw const FormatException('Content exceeds the server limit');
        }
        if (visibility.requiresAudience && visibility.audienceUserIds.isEmpty) {
          throw const FormatException('Please select at least one friend');
        }
        job = MomentsPublishJob(
            clientRequestID: const Uuid().v4(),
            text: trimmed,
            visibility: MomentsVisibilitySelection(
                mode: visibility.mode,
                audienceUserIds: List.unmodifiable(visibility.audienceUserIds)),
            mediaOrder: List.unmodifiable(media.map((m) => m.clientMediaId)));
        stage = MomentsPublishStage.preparing;
        _changed();
        await save();
      }
      _checkSession();
      final attempt = job!;
      if (attempt.submitted && stage != MomentsPublishStage.submitFailed) {
        reconciling = true;
        final result =
            await repository.api.queryPublishResult(attempt.clientRequestID);
        _checkSession();
        if (result.succeeded) {
          var post = result.post;
          if (post == null) {
            final id = result.resourceId;
            if (id == null || id.isEmpty) {
              stage = MomentsPublishStage.submitUnknown;
              _changed();
              return null;
            }
            try {
              post = await repository.api.detail(id);
              _checkSession();
            } catch (_) {
              _checkSession();
              await _completeWithoutPost(id);
              return null;
            }
          }
          return await _complete(post);
        }
        if (result.rejected) {
          stage = MomentsPublishStage.submitFailed;
          error = StateError('Publish request was rejected');
          _changed();
          await save();
          return null;
        }
        if (!result.notFound) {
          stage = MomentsPublishStage.submitUnknown;
          _changed();
          await save();
          return null;
        }
        // NOT_FOUND may race with an earlier request: retry its exact same key.
      }
      reconciling = false;
      for (final id in attempt.mediaOrder) {
        _checkSession();
        final item = media.firstWhere((m) => m.clientMediaId == id);
        if (item.mediaId != null) {
          item.progress = 1;
          continue;
        }
        stage = MomentsPublishStage.preparing;
        _changed();
        if (item.uploadPath == null) {
          final prepared = await _compress(File(item.path));
          _checkSession();
          if (prepared == null) throw StateError('Could not prepare image');
          final directory = await _mediaDirectory();
          final ext = p.extension(prepared.path).toLowerCase();
          final upload = await prepared
              .copy(p.join(directory.path, '${item.clientMediaId}.upload$ext'));
          _checkSession();
          item.uploadPath = upload.path;
          await save();
        }
        final upload = File(item.uploadPath!);
        if (!await upload.exists()) {
          throw StateError(
              'Draft image is missing. Restore the image before publishing.');
        }
        if (await upload.length() > capabilities.maxImageBytes) {
          throw const FormatException('Image exceeds the server size limit');
        }
        _checkSession();
        stage = MomentsPublishStage.uploading;
        _uploadCancel = CancelToken();
        _changed();
        final uploaded = await repository.api.uploadMedia(
            filePath: upload.path,
            clientMediaId: item.clientMediaId,
            fileName: p.basename(upload.path),
            cancelToken: _uploadCancel,
            onProgress: (sent, total) {
              if (sessionCurrent && !_cancelRequested && total > 0) {
                item.progress = (sent / total).clamp(0, 1);
                _changed();
              }
            });
        _checkSession();
        if (uploaded.status != 'READY' || uploaded.mediaId.isEmpty) {
          throw StateError(
              'Image is not ready. Retry when processing has completed.');
        }
        item.mediaId = uploaded.mediaId;
        item.progress = 1;
        await save();
      }
      _checkSession();
      stage = MomentsPublishStage.readyToCommit;
      _changed();
      final ids = attempt.mediaOrder
          .map((id) => media.firstWhere((m) => m.clientMediaId == id).mediaId!)
          .toList();
      // Persist the uncertain state BEFORE transmitting the commit request.
      attempt.submitted = true;
      stage = MomentsPublishStage.submitting;
      await save();
      _checkSession();
      _changed();
      final post = await repository.api.createPost(
          clientRequestID: attempt.clientRequestID,
          text: attempt.text,
          mediaIds: ids,
          visibility: attempt.visibility.mode,
          audienceUserIds: attempt.visibility.requiresAudience
              ? attempt.visibility.audienceUserIds
              : const []);
      _checkSession();
      return await _complete(post);
    } catch (e) {
      if (!sessionCurrent || _cancelRequested) return null;
      error = e;
      if (e is MomentsException && e.authRequired) {
        stage = MomentsPublishStage.awaitingAuth;
      } else if (job?.submitted == true) {
        stage = !reconciling &&
                e is MomentsException &&
                !e.unknownResult &&
                !e.unavailable
            ? MomentsPublishStage.submitFailed
            : MomentsPublishStage.submitUnknown;
      } else if (job != null) {
        stage = MomentsPublishStage.uploadFailed;
      }
      _changed();
      try {
        await save();
      } catch (_) {/* Surface the persistence error separately. */}
      return null;
    } finally {
      _uploadCancel = null;
    }
  }

  Future<MomentPost> _complete(MomentPost post) async {
    _checkSession();
    repository.applyPost(post);
    final oldMedia = List<MomentsDraftMedia>.from(media);
    text = '';
    media.clear();
    job = null;
    visibility = const MomentsVisibilitySelection();
    stage = MomentsPublishStage.draft;
    error = null;
    lastPublished = post;
    confirmedMomentId = post.momentId;
    // A failed local cleanup must never turn a confirmed creation into a retry.
    try {
      await save();
    } catch (_) {
      /* Existing task will reconcile with the same key after restart. */
    }
    await _deleteOwnedFiles(oldMedia);
    _changed();
    return post;
  }

  Future<void> _completeWithoutPost(String id) async {
    _checkSession();
    final oldMedia = List<MomentsDraftMedia>.from(media);
    text = '';
    media.clear();
    job = null;
    visibility = const MomentsVisibilitySelection();
    stage = MomentsPublishStage.draft;
    error = null;
    confirmedMomentId = id;
    try {
      await save();
    } catch (_) {/* Restart reconciliation uses the old key. */}
    await _deleteOwnedFiles(oldMedia);
    _changed();
  }

  Future<void> resumeEditing() async {
    if (!loaded || recoveryFailed) {
      throw StateError('Restore the original draft before editing');
    }
    if (resultUncertain || !sessionCurrent) return;
    _cancelRequested = true;
    _uploadCancel?.cancel();
    if (_work != null) await _work;
    if (!sessionCurrent) return;
    job = null;
    stage = MomentsPublishStage.draft;
    error = null;
    _cancelRequested = false;
    await save();
    _changed();
  }

  Future<void> discard() async {
    if (!loaded || recoveryFailed) {
      throw StateError('Restore the original draft before discarding');
    }
    if (resultUncertain) {
      throw StateError(
          'Confirm the publish result before discarding this task');
    }
    await resumeEditing();
    _checkSession();
    final oldMedia = List<MomentsDraftMedia>.from(media);
    text = '';
    media.clear();
    visibility = const MomentsVisibilitySelection();
    await save();
    await _deleteOwnedFiles(oldMedia);
    _changed();
  }

  Future<void> _deleteOwnedFiles(List<MomentsDraftMedia> items) async {
    if (items.isEmpty) return;
    final directory = await _mediaDirectory();
    for (final path in items
        .expand((m) => [m.path, if (m.uploadPath != null) m.uploadPath!])
        .toSet()) {
      final absolute = p.normalize(p.absolute(path));
      if (!p.isWithin(p.normalize(p.absolute(directory.path)), absolute)) {
        continue;
      }
      try {
        if (await File(absolute).exists()) await File(absolute).delete();
      } catch (_) {/* Retry cleanup on a future draft action. */}
    }
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _uploadCancel?.cancel();
    repository.removeListener(_sessionChanged);
    super.dispose();
  }
}
