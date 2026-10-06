#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Renders the actual subscribed WebRTC track into an AVSampleBufferDisplayLayer.
@interface CallVideoFrameView : UIView
@property(nonatomic, copy, nullable) void (^onFirstFrame)(void);
@property(nonatomic, readonly) BOOL hasVideoFrame;
- (BOOL)attachRemoteTrack:(NSString *)trackID;
- (void)detach;
+ (BOOL)enableBackgroundCamera;
@end

NS_ASSUME_NONNULL_END
