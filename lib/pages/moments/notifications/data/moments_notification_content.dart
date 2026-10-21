import '../../../../services/moments_api.dart';

/// Resolves sparse inbox payloads through the existing permission-checked API.
/// Work is bounded, shared per post, and never retained across inbox refreshes.
class MomentsNotificationContent {
  static MomentNotification withFriend(
      MomentNotification item, Map<String, MomentUser> friends) {
    MomentUser resolve(MomentUser user) {
      final friend = friends[user.userId];
      if (friend == null) return user;
      return MomentUser(
        userId: user.userId,
        remark: friend.remark,
        nickname:
            friend.nickname.trim().isNotEmpty ? friend.nickname : user.nickname,
        avatarUrl: friend.avatarUrl.trim().isNotEmpty
            ? friend.avatarUrl
            : user.avatarUrl,
      );
    }

    return item.withContent(
      actor: resolve(item.actor),
      replyToUser: item.comment?.replyTargetDeleted == true
          ? null
          : item.replyToUser == null
              ? null
              : resolve(item.replyToUser!),
    );
  }

  static Future<List<MomentNotification>> load({
    required List<MomentNotification> items,
    required MomentsApi api,
    required bool Function() isCurrent,
    bool Function(MomentPost)? canReadPost,
  }) async {
    final groups = <String, List<MomentNotification>>{};
    for (final item in items) {
      if (item.available &&
          item.momentId.isNotEmpty &&
          (item.previewMedia == null ||
              item.momentText.trim().isEmpty ||
              (!item.type.toUpperCase().contains('LIKE') &&
                  (item.comment?.text.trim().isEmpty ?? true)))) {
        groups.putIfAbsent(item.momentId, () => []).add(item);
      }
    }
    final results = <String, MomentNotification>{};
    final entries = groups.entries.toList();
    var next = 0;
    Future<void> worker() async {
      while (isCurrent() && next < entries.length) {
        final group = entries[next++];
        try {
          final post = await api.detail(group.key);
          if (!isCurrent()) return;
          if (post.momentId != group.key) continue;
          if (canReadPost != null && !canReadPost(post)) {
            for (final item in group.value) {
              results[item.notificationId] = item.withContent(available: false);
            }
            continue;
          }
          final comments = {
            for (final c in post.commentsPreview) c.commentId: c
          };
          final missing = group.value
              .where((n) =>
                  !n.type.toUpperCase().contains('LIKE') &&
                  (n.comment?.text.trim().isEmpty ?? true) &&
                  n.commentId.isNotEmpty)
              .map((n) => n.commentId)
              .toSet()
            ..removeAll(comments.keys);
          String? cursor;
          // Do not crawl an unbounded comment history to paint the inbox.
          for (var page = 0; page < 3 && missing.isNotEmpty; page++) {
            try {
              final response =
                  await api.comments(group.key, cursor: cursor, pageSize: 100);
              if (!isCurrent()) return;
              for (final c in response.items) {
                comments[c.commentId] = c;
              }
              missing.removeAll(comments.keys);
              if (!response.hasMore ||
                  response.nextCursor == null ||
                  response.nextCursor == cursor) {
                break;
              }
              cursor = response.nextCursor;
            } on MomentsException catch (error) {
              if (error.permissionDenied ||
                  error.authRequired ||
                  error.statusCode == 404 ||
                  error.statusCode == 410) {
                rethrow;
              }
              break;
            } catch (_) {
              break;
            }
          }
          final media = post.mediaList.where((m) => m.isReady);
          for (final item in group.value) {
            final comment = comments[item.commentId];
            results[item.notificationId] = item.withContent(
              momentText: post.text,
              previewMedia: media.isEmpty ? null : media.first,
              comment: comment,
              replyToUser: comment?.replyToUser,
            );
          }
        } on MomentsException catch (error) {
          if (error.permissionDenied ||
              error.statusCode == 404 ||
              error.statusCode == 410) {
            for (final item in group.value) {
              results[item.notificationId] = item.withContent(available: false);
            }
          }
        } catch (_) {
          // Optional content failure must not discard the interaction inbox.
        }
      }
    }

    await Future.wait(List.generate(4, (_) => worker()));
    return items.map((item) => results[item.notificationId] ?? item).toList();
  }
}
