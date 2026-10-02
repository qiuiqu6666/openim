import 'dart:async';
import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/media_kit_video_controls/media_kit_video_controls.dart'
    as media_kit_video_controls;
import 'package:openim_common/openim_common.dart';

import 'custom_mk_controls.dart';
import 'photo_browser_hero.dart';
import 'native_media_video.dart';
import 'video_media_cache.dart';
import 'media_preview_glass.dart';

class MediaSource {
  final String? url;
  final String thumbnail;
  final File? file;
  final Uint8List? bytes;
  final bool isVideo;
  final String? tag;
  final String? senderName;
  final DateTime? sentAt;

  MediaSource(
      {required this.thumbnail,
      this.url,
      this.file,
      this.bytes,
      this.isVideo = false,
      this.tag,
      this.senderName,
      this.sentAt});
}

class MediaBrowser extends StatefulWidget {
  const MediaBrowser({
    super.key,
    required this.sources,
    required this.initialIndex,
    this.muted = false,
    this.showGallery = true,
    this.showCounter = true,
    this.onAutoPlay,
    this.onSave,
    this.onLongPress,
    this.onPageChanged,
    this.onForward,
    this.onDelete,
  });
  final int initialIndex;
  final List<MediaSource> sources;
  final bool muted;
  final bool showGallery;
  final bool showCounter;
  final bool Function(int index)? onAutoPlay;
  final ValueChanged<int>? onSave;
  final ValueChanged<int>? onLongPress;
  final ValueChanged<int>? onPageChanged;
  final ValueChanged<int>? onForward;
  final ValueChanged<int>? onDelete;
  @override
  State<MediaBrowser> createState() => _MediaBrowserState();
}

class _MediaBrowserState extends State<MediaBrowser>
    with TickerProviderStateMixin {
  GlobalKey<ExtendedImageSlidePageState> slidePagekey =
      GlobalKey<ExtendedImageSlidePageState>();

  final List<int> _cachedIndexes = <int>[];
  int currentIndex = 0;
  bool _showControls = true;
  bool _showGrid = false;
  SystemUiOverlayStyle? _previousSystemUiStyle;

  List<double> doubleTapScales = <double>[1.0, 2.0];
  late AnimationController _doubleClickAnimationController;
  Animation<double>? _doubleClickAnimation;
  late VoidCallback _doubleClickAnimationListener;

  @override
  void initState() {
    // Capture before this route's AnnotatedRegion paints. The image viewer
    // does not change SystemUiMode, so preserve the caller's mode as-is.
    _previousSystemUiStyle = SystemChrome.latestStyle;
    currentIndex = widget.initialIndex;
    _doubleClickAnimationController = AnimationController(
        duration: const Duration(milliseconds: 150), vsync: this);
    super.initState();
  }

  @override
  void dispose() {
    Logger.print('[MediaBrowser] dispose', fileName: 'media_browser.dart');
    _doubleClickAnimationController.dispose();

    final previousStyle = _previousSystemUiStyle;
    if (previousStyle != null) {
      SystemChrome.setSystemUIOverlayStyle(previousStyle);
    }
    // Reapply the platform's existing visibility configuration (also covers
    // temporarily hidden bars) without hardcoding edge-to-edge or a theme.
    unawaited(SystemChrome.restoreSystemUIOverlays());

    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _preloadImage(currentIndex - 1 < 0 ? 0 : currentIndex - 1);
    _preloadImage(currentIndex + 1);
  }

  void _preloadImage(int index) {
    if (_cachedIndexes.contains(index)) {
      return;
    }
    if (0 <= index && index < widget.sources.length) {
      final s = widget.sources[index];
      final url = s.isVideo ? s.thumbnail : s.url;
      if (url != null && url.isNotEmpty) {
        precacheImage(ExtendedNetworkImageProvider(url, cache: true), context);
      }

      _cachedIndexes.add(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final source = widget.sources[currentIndex];
    const background = Colors.black;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarDividerColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Material(
        color: background,
        shadowColor: Colors.transparent,
        child: Stack(children: [
          ExtendedImageSlidePage(
            key: slidePagekey,
            slideAxis:
                widget.sources.length > 1 ? SlideAxis.vertical : SlideAxis.both,
            slideType: SlideType.wholePage,
            resetPageDuration: const Duration(milliseconds: 300),
            slidePageBackgroundHandler: (offset, pageSize) {
              double rate = 1 - (offset.dy.abs() / (size.height / 2));
              rate = rate > 0 ? rate : 0;
              return background.withValues(alpha: rate);
            },
            child: GestureDetector(
              onTap: () => setState(() => _showControls = !_showControls),
              onLongPress: () => widget.onLongPress?.call(currentIndex),
              child: ExtendedImageGesturePageView.builder(
                controller: ExtendedPageController(
                  initialPage: currentIndex,
                  pageSpacing: 8,
                  shouldIgnorePointerWhenScrolling: true,
                ),
                itemCount: widget.sources.length,
                onPageChanged: (int page) {
                  setState(() => currentIndex = page);
                  widget.onPageChanged?.call(page);
                  _preloadImage(page - 1);
                  _preloadImage(page + 1);
                },
                itemBuilder: (BuildContext context, int index) {
                  final s = widget.sources[index];

                  if (s.isVideo && index != currentIndex) {
                    return const SizedBox.expand();
                  }
                  return s.isVideo
                      ? ExtendedImageSlidePageHandler(
                          child: VideoPlayerView(
                            key: ValueKey(s.tag ?? s.url),
                            url: s.url,
                            coverUrl: s.thumbnail,
                            file: s.file,
                            heroTag: s.tag,
                            autoPlay: widget.onAutoPlay?.call(index) ?? false,
                            muted: widget.muted,
                            onDownload: (url, file) =>
                                widget.onSave?.call(currentIndex),
                          ),
                          heroBuilderForSlidingPage: (Widget result) {
                            return Hero(
                              tag: s.tag ?? s.thumbnail,
                              child: result,
                              flightShuttleBuilder: (BuildContext flightContext,
                                  Animation<double> animation,
                                  HeroFlightDirection flightDirection,
                                  BuildContext fromHeroContext,
                                  BuildContext toHeroContext) {
                                final Hero hero =
                                    (flightDirection == HeroFlightDirection.pop
                                        ? fromHeroContext.widget
                                        : toHeroContext.widget) as Hero;

                                return hero.child;
                              },
                            );
                          },
                        )
                      : HeroWidget(
                          tag: s.tag ?? s.thumbnail,
                          slideType: SlideType.onlyImage,
                          slidePagekey: slidePagekey,
                          child: s.bytes != null
                              ? ExtendedImage.memory(
                                  s.bytes!,
                                  enableSlideOutPage: true,
                                  fit: BoxFit.contain,
                                  mode: ExtendedImageMode.gesture,
                                )
                              : s.file != null && s.file!.existsSync()
                                  ? ExtendedImage.file(
                                      s.file!,
                                      enableSlideOutPage: true,
                                      fit: BoxFit.contain,
                                      mode: ExtendedImageMode.gesture,
                                    )
                                  : ExtendedImage.network(
                                      s.url ?? s.thumbnail,
                                      enableSlideOutPage: true,
                                      fit: BoxFit.contain,
                                      mode: ExtendedImageMode.gesture,
                                      initGestureConfigHandler:
                                          (ExtendedImageState state) {
                                        return GestureConfig(
                                          minScale: 0.9,
                                          animationMinScale: 0.7,
                                          maxScale: 3.0,
                                          animationMaxScale: 3.5,
                                          speed: 1.0,
                                          inPageView: true,
                                          initialAlignment:
                                              InitialAlignment.center,
                                        );
                                      },
                                      onDoubleTap: (state) {
                                        final Offset? pointerDownPosition =
                                            state.pointerDownPosition;
                                        final double? begin =
                                            state.gestureDetails!.totalScale;
                                        double end;

                                        _doubleClickAnimation?.removeListener(
                                            _doubleClickAnimationListener);

                                        _doubleClickAnimationController.stop();

                                        _doubleClickAnimationController.reset();

                                        if (begin == doubleTapScales[0]) {
                                          end = doubleTapScales[1];
                                        } else {
                                          end = doubleTapScales[0];
                                        }

                                        _doubleClickAnimationListener = () {
                                          state.handleDoubleTap(
                                              scale:
                                                  _doubleClickAnimation!.value,
                                              doubleTapPosition:
                                                  pointerDownPosition);
                                        };
                                        _doubleClickAnimation =
                                            _doubleClickAnimationController
                                                .drive(Tween<double>(
                                                    begin: begin, end: end));

                                        _doubleClickAnimation!.addListener(
                                            _doubleClickAnimationListener);

                                        _doubleClickAnimationController
                                            .forward();
                                      },
                                      loadStateChanged: (state) {
                                        if (state.extendedImageLoadState ==
                                            LoadState.loading) {
                                          return Stack(
                                            alignment:
                                                AlignmentDirectional.center,
                                            children: [
                                              ExtendedImage.network(
                                                s.thumbnail,
                                                enableLoadState: false,
                                              ),
                                              const CupertinoActivityIndicator(
                                                radius: 15,
                                              ),
                                            ],
                                          );
                                        } else if (state
                                                .extendedImageLoadState ==
                                            LoadState.failed) {
                                          state.imageProvider.evict();

                                          return ImageRes.pictureError.toImage;
                                        }
                                        return null;
                                      },
                                    ),
                        );
                },
              ),
            ),
          ),
          if (_showControls)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                color: Colors.transparent,
                child: SafeArea(
                  bottom: false,
                  minimum: const EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    height: 72,
                    child: Row(children: [
                      Transform.translate(
                        offset:
                            Offset(0, (TitleBar.chatToolbarHeight - 72) / 2),
                        child: _roundAction(context,
                            icon: Icons.arrow_back_ios_new,
                            tooltip: MaterialLocalizations.of(context)
                                .backButtonTooltip,
                            onPressed: () => Navigator.of(context).pop()),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Transform.translate(
                          offset:
                              Offset(0, (TitleBar.chatToolbarHeight - 72) / 2),
                          child: Center(
                            child: MediaPreviewGlass(
                              borderRadius: BorderRadius.circular(28),
                              child: Container(
                                key: const ValueKey('media-preview-info'),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 4),
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (source.senderName?.isNotEmpty == true)
                                        Text(source.senderName!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                color: Colors.white)),
                                      if (widget.showCounter ||
                                          source.sentAt != null)
                                        Text(
                                            [
                                              if (source.sentAt != null)
                                                _previewTime(source.sentAt),
                                              if (widget.showCounter)
                                                '${currentIndex + 1}/${widget.sources.length}',
                                            ].join('  '),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                    color: Colors.white70)),
                                    ]),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                          width: (MediaQuery.sizeOf(context).width * 0.105)
                                  .clamp(42.0, 52.0) +
                              12),
                    ]),
                  ),
                ),
              ),
            ),
          if (_showControls && source.isVideo)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  height: MediaQuery.paddingOf(context).bottom + 96,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.72)
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_showControls)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Material(
                color: Colors.transparent,
                child: SafeArea(
                  top: false,
                  minimum: const EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    height: 72,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      spacing: NavigationGlassTokens.gap,
                      children: [
                        if (widget.onForward != null)
                          _roundAction(context,
                              icon: Icons.ios_share,
                              tooltip: '转发',
                              onPressed: () => widget.onForward!(currentIndex)),
                        if (widget.onSave != null)
                          _roundAction(context,
                              icon: Icons.download,
                              tooltip: StrRes.saveToAlbum,
                              onPressed: () => widget.onSave!(currentIndex)),
                        if (widget.showGallery)
                          _roundAction(context,
                              icon: Icons.grid_view_rounded,
                              tooltip: '图片和视频',
                              onPressed: () =>
                                  setState(() => _showGrid = true)),
                        if (widget.onDelete != null)
                          _roundAction(context,
                              icon: Icons.more_horiz,
                              tooltip: 'mediaMore'.tr,
                              onPressed: () => _showMoreMenu(context)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_showGrid) Positioned.fill(child: _buildGrid(context)),
        ]),
      ),
    );
  }

  String _previewTime(DateTime? time) {
    if (time == null) return '${currentIndex + 1}/${widget.sources.length}';
    final now = DateTime.now();
    final today =
        now.year == time.year && now.month == time.month && now.day == time.day;
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return today
        ? '今天 $hour:$minute'
        : '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} $hour:$minute';
  }

  Widget _roundAction(BuildContext context,
      {required IconData icon,
      required String tooltip,
      VoidCallback? onPressed}) {
    final diameter =
        (MediaQuery.sizeOf(context).width * 0.105).clamp(42.0, 52.0);
    return SizedBox.square(
      dimension: diameter,
      child: MediaPreviewGlass(
        borderRadius: BorderRadius.circular(diameter / 2),
        interactive: onPressed != null,
        child: IconButton.filled(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon, size: diameter * 0.48),
          style: IconButton.styleFrom(
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white70,
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
          ),
        ),
      ),
    );
  }

  void _showMoreMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (widget.onSave != null)
            ListTile(
              leading: const Icon(Icons.download),
              title: Text(StrRes.saveToAlbum),
              onTap: () {
                Navigator.pop(sheetContext);
                widget.onSave!(currentIndex);
              },
            ),
          if (widget.onForward != null)
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('转发'),
              onTap: () {
                Navigator.pop(sheetContext);
                widget.onForward!(currentIndex);
              },
            ),
          if (widget.onDelete != null)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除'),
              onTap: () {
                Navigator.pop(sheetContext);
                _deleteCurrent(context);
              },
            ),
        ]),
      ),
    );
  }

  void _deleteCurrent(BuildContext context) {
    final index = currentIndex;
    Navigator.of(context).pop();
    widget.onDelete?.call(index);
  }

  Widget _buildGrid(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    Widget placeholder({bool failed = false}) => ColoredBox(
          color: AppTokens.surface(dark: dark),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(failed ? Icons.broken_image_outlined : Icons.image_outlined,
                  color: AppTokens.textSecondary(dark: dark), size: 28),
              if (failed) ...[
                const SizedBox(height: 6),
                Text(zh ? '缩略图不可用' : 'Preview unavailable',
                    style: TextStyle(
                        color: AppTokens.textSecondary(dark: dark),
                        fontSize: 11)),
              ],
            ]),
          ),
        );
    Widget failed(BuildContext _, Object __, StackTrace? ___) =>
        placeholder(failed: true);
    return Material(
      color: AppTokens.background(dark: dark),
      child: SafeArea(
        child: Column(children: [
          SizedBox(
            height: 56,
            child: Stack(alignment: Alignment.center, children: [
              Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    tooltip: zh ? '返回预览' : 'Back to preview',
                    color: AppTokens.accent,
                    icon: const Icon(Icons.chevron_left_rounded, size: 32),
                    onPressed: () => setState(() => _showGrid = false),
                  )),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 56),
                child: Text(zh ? '图片和视频' : 'Photos and videos',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppTokens.textPrimary(dark: dark),
                        fontSize: 18,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    zh
                        ? '共 ${widget.sources.length} 项'
                        : '${widget.sources.length} items',
                    style: TextStyle(
                        color: AppTokens.textSecondary(dark: dark),
                        fontSize: 13))),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 160,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6),
              itemCount: widget.sources.length,
              itemBuilder: (context, index) {
                final item = widget.sources[index];
                final file = item.file;
                final uri =
                    item.thumbnail.isNotEmpty ? item.thumbnail : item.url ?? '';
                final localThumbnail = uri.isNotEmpty && !uri.startsWith('http')
                    ? File(uri.startsWith('file://')
                        ? Uri.parse(uri).toFilePath()
                        : uri)
                    : null;
                final thumb = !item.isVideo && item.bytes != null
                    ? Image.memory(item.bytes!,
                        fit: BoxFit.cover, errorBuilder: failed)
                    : !item.isVideo && file != null && file.existsSync()
                        ? Image.file(file,
                            fit: BoxFit.cover, errorBuilder: failed)
                        : localThumbnail != null && localThumbnail.existsSync()
                            ? Image.file(localThumbnail,
                                fit: BoxFit.cover, errorBuilder: failed)
                            : uri.startsWith('http')
                                ? Image.network(uri,
                                    fit: BoxFit.cover,
                                    errorBuilder: failed,
                                    loadingBuilder: (_, child, progress) =>
                                        progress == null
                                            ? child
                                            : placeholder())
                                : placeholder(failed: true);
                return Semantics(
                  button: true,
                  selected: currentIndex == index,
                  label:
                      '${item.isVideo ? (zh ? '视频' : 'Video') : (zh ? '图片' : 'Photo')} ${index + 1}',
                  child: InkWell(
                    onTap: () => setState(() {
                      currentIndex = index;
                      _showGrid = false;
                    }),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: currentIndex == index
                              ? Border.all(color: AppTokens.accent, width: 2)
                              : null),
                      padding: currentIndex == index
                          ? const EdgeInsets.all(2)
                          : EdgeInsets.zero,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Stack(fit: StackFit.expand, children: [
                          thumb,
                          if (item.isVideo)
                            const Center(
                                child: Icon(Icons.play_circle_fill,
                                    color: Colors.white, size: 32)),
                        ]),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

class VideoPlayerView extends StatefulWidget {
  const VideoPlayerView({
    super.key,
    this.path,
    this.url,
    this.coverUrl,
    this.file,
    this.heroTag,
    this.onDownload,
    this.autoPlay = true,
    this.muted = false,
  });
  final String? path;
  final String? url;
  final File? file;
  final String? coverUrl;
  final String? heroTag;
  final bool autoPlay;
  final bool muted;
  final Function(String? url, File? file)? onDownload;
  @override
  State<VideoPlayerView> createState() => Platform.isAndroid || Platform.isIOS
      ? _MobileVideoPlayerViewState()
      : _VideoPlayerViewState();
}

class _MobileVideoPlayerViewState extends State<VideoPlayerView> {
  @override
  Widget build(BuildContext context) => NativeMediaVideo(
        file: widget.file,
        path: widget.path,
        url: widget.url,
        coverUrl: widget.coverUrl,
        autoPlay: widget.autoPlay,
        muted: widget.muted,
      );
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  late final player = Player();
  late final controller = VideoController(player);
  final _cacheManager = DefaultCacheManager();
  bool _showCover = true;

  StreamSubscription<bool>? _playingSubscription;
  Future<void>? _opening;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _playingSubscription = player.stream.playing.listen((event) {
      if (mounted && !_disposed && event && _showCover) {
        setState(() => _showCover = false);
      }
    });
    _opening = _openVideo();
  }

  Future<void> _openVideo() async {
    try {
      final local =
          widget.file ?? (widget.path == null ? null : File(widget.path!));
      String? source;
      if (local != null && await local.exists()) source = local.path;
      final url = widget.url;
      if (source == null && url != null && url.isNotEmpty) {
        final cached = await VideoMediaCache.cachedFile(url);
        source = cached?.path ?? url;
      }
      if (_disposed || source == null) return;
      await player.setVolume(widget.muted ? 0 : 100);
      if (_disposed) return;
      await player.open(Media(source), play: widget.autoPlay);
      if (source == url && url != null && url.isNotEmpty) {
        unawaited(Future<void>.delayed(
            const Duration(seconds: 2), () => VideoMediaCache.remember(url)));
      }
    } catch (_) {
      if (mounted && !_disposed) IMViews.showToast(StrRes.videoPlaybackFailed);
    }
  }

  Future<void> _releasePlayer() async {
    await _playingSubscription?.cancel();
    await _opening;
    await player.dispose();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_releasePlayer());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MaterialVideoControlsTheme(
          normal: media_kit_video_controls
              .kDefaultMaterialVideoControlsThemeData
              .copyWith(
            bottomButtonBarMargin: const EdgeInsets.only(bottom: 70),
            seekBarMargin:
                const EdgeInsets.only(bottom: 60, left: 24, right: 24),
            seekBarThumbColor: Colors.white,
            seekBarPositionColor: Colors.white,
            bottomButtonBar: [
              const MaterialPlayOrPauseButton(),
              const MaterialPositionIndicator(),
              const Spacer(),
              MaterialCustomButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () {
                    _showActionSheet(context);
                  }),
            ],
          ),
          fullscreen: media_kit_video_controls
              .kDefaultMaterialVideoControlsThemeDataFullscreen,
          child: Video(
            controller: controller,
            fit: BoxFit.contain,
            controls: (state) {
              return CustomMKMaterialVideoControls(state);
            },
          ),
        ),
        if (_showCover) _buildCoverView(context)
      ],
    );
  }

  void _showActionSheet(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) {
        return CupertinoActionSheet(
          actions: [
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.pop(context);
                final url = widget.url;
                final file = url == null || url.isEmpty
                    ? null
                    : await _cacheManager.getFileFromCache(url);
                if (_disposed) return;
                widget.onDownload?.call(url, widget.file ?? file?.file);
              },
              child: Text(StrRes.download),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
            },
            isDestructiveAction: true,
            child: Text(StrRes.cancel),
          ),
        );
      },
    );
  }

  Widget _buildCoverView(BuildContext context) {
    if (widget.coverUrl == null) {
      return const SizedBox.shrink();
    }

    final screenSize = MediaQuery.of(context).size;

    return Stack(
      alignment: Alignment.center,
      children: [
        ImageUtil.networkImage(
          url: widget.coverUrl!,
          loadProgress: false,
          height: screenSize.height,
          width: screenSize.width,
          fit: BoxFit.fitWidth,
        ),
        const CupertinoActivityIndicator(
          color: Colors.white,
          radius: 15,
        ),
      ],
    );
  }
}
