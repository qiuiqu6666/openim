// Copyright 2026 99Chat contributors. See LICENSE for the upstream BSD license.
package io.flutter.plugins.videoplayer;

import android.content.Context;
import android.util.Log;
import androidx.media3.common.PlaybackException;
import androidx.media3.exoplayer.DefaultRenderersFactory;
import androidx.media3.exoplayer.ExoPlaybackException;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.mediacodec.MediaCodecInfo;
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector;
import androidx.media3.exoplayer.mediacodec.MediaCodecUtil;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.WeakHashMap;

/** Per-player fallback: never blacklist a device or change other active players. */
public final class DecoderCompatibility implements MediaCodecSelector {
  private static final Map<ExoPlayer.Builder, DecoderCompatibility> builders = new WeakHashMap<>();
  private static final Map<ExoPlayer, DecoderCompatibility> players = new WeakHashMap<>();
  private volatile boolean softwareVideo;
  private final MediaCodecSelector delegate;

  public DecoderCompatibility() { this(MediaCodecSelector.DEFAULT); }
  DecoderCompatibility(MediaCodecSelector delegate) { this.delegate = delegate; }

  public static ExoPlayer.Builder builder(Context context) {
    DecoderCompatibility selector = new DecoderCompatibility();
    ExoPlayer.Builder builder = new ExoPlayer.Builder(context,
        new DefaultRenderersFactory(context).setEnableDecoderFallback(true)
            .setMediaCodecSelector(selector));
    builders.put(builder, selector);
    return builder;
  }

  public static ExoPlayer build(ExoPlayer.Builder builder) {
    ExoPlayer player = builder.build();
    players.put(player, builders.remove(builder));
    return player;
  }

  @Override
  public List<MediaCodecInfo> getDecoderInfos(String mimeType, boolean secure, boolean tunneling)
      throws MediaCodecUtil.DecoderQueryException {
    List<MediaCodecInfo> codecs = delegate.getDecoderInfos(mimeType, secure, tunneling);
    if (!softwareVideo || !mimeType.startsWith("video/")) return codecs;
    List<MediaCodecInfo> software = new ArrayList<>();
    for (MediaCodecInfo codec : codecs) {
      if (codec.softwareOnly) software.add(codec);
    }
    return software;
  }

  public static boolean recover(ExoPlayer player, PlaybackException failure) {
    DecoderCompatibility selector = players.get(player);
    return selector != null && selector.recoverPlayer(player, failure);
  }

  boolean recoverPlayer(ExoPlayer player, PlaybackException failure) {
    if (softwareVideo || !isVideoDecoderFailure(failure)) return false;
    ExoPlaybackException error = (ExoPlaybackException) failure;
    String mime = error.rendererFormat.sampleMimeType;
    // Encrypted playback must retain its secure decoder requirements.
    if (error.rendererFormat.drmInitData != null) return false;
    try {
      boolean available = false;
      for (MediaCodecInfo codec : delegate.getDecoderInfos(mime, false, false)) {
        if (codec.softwareOnly) available = true;
      }
      if (!available) return false;
    } catch (MediaCodecUtil.DecoderQueryException ignored) {
      return false;
    }
    softwareVideo = true;
    Log.w("ChatVideo", "Video decoder failed; retrying software decoder once, code=" + failure.errorCode);
    boolean play = player.getPlayWhenReady();
    long position = player.getCurrentPosition();
    boolean live = player.isCurrentMediaItemLive();
    player.stop();
    if (live) player.seekToDefaultPosition();
    else player.seekTo(position);
    player.prepare();
    player.setPlayWhenReady(play);
    return true;
  }

  static boolean isVideoDecoderFailure(PlaybackException failure) {
    if (!(failure instanceof ExoPlaybackException)) return false;
    ExoPlaybackException error = (ExoPlaybackException) failure;
    return error.type == ExoPlaybackException.TYPE_RENDERER
        && error.rendererFormat != null
        && error.rendererFormat.sampleMimeType != null
        && error.rendererFormat.sampleMimeType.startsWith("video/")
        && (failure.errorCode == PlaybackException.ERROR_CODE_DECODER_INIT_FAILED
            || failure.errorCode == PlaybackException.ERROR_CODE_DECODING_FAILED);
  }

  public static void release(ExoPlayer player) { players.remove(player); }
}
