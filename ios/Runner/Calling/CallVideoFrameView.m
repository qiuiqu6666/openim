#import "CallVideoFrameView.h"
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <WebRTC/WebRTC.h>
#import <flutter_webrtc/FlutterWebRTCPlugin.h>
#import <math.h>
#import <string.h>

@interface CallVideoFrameView () <RTCVideoRenderer>
@property(atomic, strong, nullable) RTCVideoTrack *track;
@property(nonatomic, readwrite) BOOL hasVideoFrame;
@property(nonatomic) BOOL pendingFrame;
@property(nonatomic) NSUInteger generation;
@property(nonatomic, strong) AVSampleBufferDisplayLayer *displayLayer;
@property(nonatomic) RTCVideoRotation rotation;
@end

@implementation CallVideoFrameView

- (AVSampleBufferDisplayLayer *)videoLayer {
    return self.displayLayer;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.blackColor;
        self.clipsToBounds = YES;
        self.displayLayer = [AVSampleBufferDisplayLayer layer];
        self.videoLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        self.videoLayer.backgroundColor = UIColor.blackColor.CGColor;
        [self.layer addSublayer:self.displayLayer];
        [self layoutVideoLayer];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self layoutVideoLayer];
}

- (void)layoutVideoLayer {
    BOOL quarterTurn = self.rotation == 90 || self.rotation == 270;
    CGSize size = self.bounds.size;
    // Rotate the display canvas, keeping the UIView/autolayout bounds intact.
    // A quarter turn needs the pre-rotation width and height exchanged.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.displayLayer.bounds = CGRectMake(0, 0,
            quarterTurn ? size.height : size.width,
            quarterTurn ? size.width : size.height);
    self.displayLayer.position = CGPointMake(CGRectGetMidX(self.bounds),
                                            CGRectGetMidY(self.bounds));
    self.displayLayer.affineTransform = CGAffineTransformMakeRotation(
            self.rotation * M_PI / 180.0);
    [CATransaction commit];
}

- (BOOL)attachRemoteTrack:(NSString *)trackID {
    RTCMediaStreamTrack *candidate =
        [[FlutterWebRTCPlugin sharedSingleton] remoteTrackForId:trackID];
    if (![candidate isKindOfClass:RTCVideoTrack.class]) {
        [self detach];
        return NO;
    }
    if (self.track == candidate) return YES;
    [self detach];
    self.track = (RTCVideoTrack *)candidate;
    [self.track addRenderer:self];
    return YES;
}

- (void)detach {
    [self.track removeRenderer:self];
    self.track = nil;
    @synchronized (self) {
        self.generation++;
        self.hasVideoFrame = NO;
    }
    [self.videoLayer flushAndRemoveImage];
    self.rotation = (RTCVideoRotation)0;
    [self layoutVideoLayer];
}

+ (BOOL)enableBackgroundCamera {
    if (@available(iOS 16.0, *)) {
        AVCaptureSession *session =
            [FlutterWebRTCPlugin sharedSingleton].videoCapturer.captureSession;
        if (session != nil && session.isMultitaskingCameraAccessSupported) {
            session.multitaskingCameraAccessEnabled = YES;
            return session.isMultitaskingCameraAccessEnabled;
        }
    }
    return NO;
}

- (void)setSize:(CGSize)size { /* The actual frame controls the pixel dimensions. */ }

- (void)renderFrame:(RTCVideoFrame *)frame {
    if (frame == nil) return;
    NSUInteger generation;
    @synchronized (self) {
        // Bound main-thread backlog to one real frame, dropping older samples.
        if (self.pendingFrame || self.track == nil) return;
        self.pendingFrame = YES;
        generation = self.generation;
    }
    CVPixelBufferRef pixels = [self copyPixels:frame.buffer];
    if (pixels == NULL) {
        @synchronized (self) { self.pendingFrame = NO; }
        return;
    }
    CMVideoFormatDescriptionRef format = NULL;
    CMSampleBufferRef sample = NULL;
    OSStatus status = CMVideoFormatDescriptionCreateForImageBuffer(
        kCFAllocatorDefault, pixels, &format);
    if (status == noErr) {
        CMSampleTimingInfo timing = {
            kCMTimeInvalid, CMTimeMake(frame.timeStampNs, 1000000000), kCMTimeInvalid
        };
        status = CMSampleBufferCreateReadyWithImageBuffer(
            kCFAllocatorDefault, pixels, format, &timing, &sample);
    }
    if (format != NULL) CFRelease(format);
    CVPixelBufferRelease(pixels);
    if (status != noErr || sample == NULL) {
        @synchronized (self) { self.pendingFrame = NO; }
        return;
    }
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sample, YES);
    if (attachments != NULL && CFArrayGetCount(attachments) > 0) {
        CFMutableDictionaryRef flags =
            (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
        CFDictionarySetValue(flags, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
    }
    RTCVideoRotation rotation = frame.rotation;
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL current;
        @synchronized (self) {
            self.pendingFrame = NO;
            current = generation == self.generation && self.track != nil;
        }
        if (current) {
            AVSampleBufferDisplayLayer *layer = self.videoLayer;
            if (layer.status == AVQueuedSampleBufferRenderingStatusFailed
                    || layer.requiresFlushToResumeDecoding) {
                [layer flushAndRemoveImage];
            }
            // WebRTC orientation is metadata; rotate only the video sublayer.
            if (self.rotation != rotation) {
                self.rotation = rotation;
                [self layoutVideoLayer];
            }
            if (layer.isReadyForMoreMediaData) {
                [layer enqueueSampleBuffer:sample];
                if (!self.hasVideoFrame) {
                    self.hasVideoFrame = YES;
                    if (self.onFirstFrame != nil) self.onFirstFrame();
                }
            }
        }
        CFRelease(sample);
    });
}

- (CVPixelBufferRef)copyPixels:(id<RTCVideoFrameBuffer>)buffer CF_RETURNS_RETAINED {
    if ([buffer isKindOfClass:RTCCVPixelBuffer.class]) {
        CVPixelBufferRef pixels = ((RTCCVPixelBuffer *)buffer).pixelBuffer;
        CVPixelBufferRetain(pixels);
        return pixels;
    }
    // Software decoders supply I420. Convert its real planes to NV12 rather
    // than introducing a placeholder bitmap or a synthetic playback stream.
    id<RTCI420Buffer> i420 = [buffer toI420];
    if (i420 == nil || i420.width <= 0 || i420.height <= 0) return NULL;
    NSDictionary *options = @{
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
        (id)kCVPixelBufferMetalCompatibilityKey: @YES,
    };
    CVPixelBufferRef pixels = NULL;
    if (CVPixelBufferCreate(kCFAllocatorDefault, i420.width, i420.height,
                           kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                           (__bridge CFDictionaryRef)options, &pixels) != kCVReturnSuccess) {
        return NULL;
    }
    if (CVPixelBufferLockBaseAddress(pixels, 0) != kCVReturnSuccess) {
        CVPixelBufferRelease(pixels);
        return NULL;
    }
    uint8_t *y = CVPixelBufferGetBaseAddressOfPlane(pixels, 0);
    uint8_t *uv = CVPixelBufferGetBaseAddressOfPlane(pixels, 1);
    size_t yStride = CVPixelBufferGetBytesPerRowOfPlane(pixels, 0);
    size_t uvStride = CVPixelBufferGetBytesPerRowOfPlane(pixels, 1);
    for (int row = 0; row < i420.height; row++) {
        memcpy(y + row * yStride, i420.dataY + row * i420.strideY, i420.width);
    }
    for (int row = 0; row < i420.chromaHeight; row++) {
        for (int column = 0; column < i420.chromaWidth; column++) {
            uv[row * uvStride + column * 2] = i420.dataU[row * i420.strideU + column];
            uv[row * uvStride + column * 2 + 1] = i420.dataV[row * i420.strideV + column];
        }
    }
    CVPixelBufferUnlockBaseAddress(pixels, 0);
    return pixels;
}

- (void)dealloc {
    [self.track removeRenderer:self];
}
@end
