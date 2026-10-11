package io.flutter.plugins.videoplayer;

import static org.junit.Assert.*;
import static org.mockito.Mockito.*;
import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.PlaybackException;
import androidx.media3.exoplayer.ExoPlaybackException;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.mediacodec.MediaCodecInfo;
import java.util.Arrays;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;

@RunWith(RobolectricTestRunner.class)
public class DecoderCompatibilityTest {
  private MediaCodecInfo codec(boolean software) {
    return MediaCodecInfo.newInstance(software ? "c2.android.avc.decoder" : "vendor.avc",
        "video/avc", "video/avc", null, !software, software, !software, false, false);
  }
  private ExoPlaybackException failure(String mime, int code) {
    return ExoPlaybackException.createForRenderer(new IllegalStateException("decoder"),
        "renderer", 0, new Format.Builder().setSampleMimeType(mime).build(),
        C.FORMAT_HANDLED, false, code);
  }
  @Test public void videoDecodeFailureRetriesOnceAndFiltersHardware() throws Exception {
    MediaCodecInfo hardware = codec(false), software = codec(true);
    DecoderCompatibility policy = new DecoderCompatibility((m, s, t) -> Arrays.asList(hardware, software));
    ExoPlayer player = mock(ExoPlayer.class);
    when(player.getCurrentPosition()).thenReturn(4200L);
    when(player.getPlayWhenReady()).thenReturn(true);
    PlaybackException error = failure("video/avc", PlaybackException.ERROR_CODE_DECODING_FAILED);
    assertEquals(2, policy.getDecoderInfos("video/avc", false, false).size());
    assertTrue(policy.recoverPlayer(player, error));
    verify(player).stop();
    verify(player).seekTo(4200L);
    verify(player).prepare();
    verify(player).setPlayWhenReady(true);
    assertEquals(Arrays.asList(software), policy.getDecoderInfos("video/avc", false, false));
    assertEquals(2, policy.getDecoderInfos("audio/mp4a-latm", false, false).size());
    assertFalse(policy.recoverPlayer(player, error));
    verify(player, times(1)).prepare();
  }
  @Test public void liveRecoveryUsesLiveEdgeAndPreservesPause() {
    DecoderCompatibility policy = new DecoderCompatibility((m, s, t) -> Arrays.asList(codec(true)));
    ExoPlayer player = mock(ExoPlayer.class);
    when(player.isCurrentMediaItemLive()).thenReturn(true);
    assertTrue(policy.recoverPlayer(player, failure("video/avc", PlaybackException.ERROR_CODE_DECODER_INIT_FAILED)));
    verify(player).seekToDefaultPosition();
    verify(player).setPlayWhenReady(false);
  }
  @Test public void noSoftwareOrNonVideoErrorDoesNotRetry() {
    DecoderCompatibility policy = new DecoderCompatibility((m, s, t) -> Arrays.asList(codec(false)));
    ExoPlayer player = mock(ExoPlayer.class);
    assertFalse(policy.recoverPlayer(player, failure("video/avc", PlaybackException.ERROR_CODE_DECODING_FAILED)));
    assertFalse(policy.recoverPlayer(player, failure("audio/mp4a-latm", PlaybackException.ERROR_CODE_DECODING_FAILED)));
    assertFalse(policy.recoverPlayer(player, new PlaybackException("network", null, PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED)));
    verifyNoInteractions(player);
  }
}
