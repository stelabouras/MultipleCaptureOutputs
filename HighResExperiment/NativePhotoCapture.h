#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <GLKit/GLKit.h>
#import <ImageIO/CGImageProperties.h>
#import <UIKit/UIKit.h>

@interface NativePhotoCapture : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate>
{
}

@property (nonatomic) AVCaptureDevicePosition devicePosition;
@property (nonatomic, readonly) AVCaptureDevice *device;
@property (nonatomic, readonly) EAGLContext *eaglContext;

- (id)initWithPosition:(AVCaptureDevicePosition)capturePosition;
- (void)switchToPhotoMode;
- (void)switchToNormal;
- (void)startCamera;
- (void)stopCamera;
- (void)setVideoPreviewView:(GLKView *)videoPreviewView;
- (void)destroyVideoPreviewView;

@end