#import <ImageIO/ImageIO.h>
#import "NativePhotoCapture.h"

static CGColorSpaceRef sDeviceRgbColorSpace = NULL;

@interface NativePhotoCapture()
{
    dispatch_queue_t serial_queue;
    GLKView *_videoPreviewView;
    CGRect _videoPreviewViewBounds;
    
    AVCaptureDevice *device;
    AVCaptureDevice *audioDevice;
    AVCaptureDevicePosition devicePosition;
    CIContext *_ciContext;
    CIContext *_ciContextCoreGraphics;
    dispatch_queue_t _captureSessionQueue;
    
    AVAssetWriterInput *_assetWriterVideoInput;
    AVAssetWriterInput *_assetWriterAudioInput;
    AVAssetWriterInputPixelBufferAdaptor *_assetWriterInputPixelBufferAdaptor;
    AVAssetWriter *_assetWriter;
    
    BOOL _videoWritingStarted;
    CMTime _videoWrtingStartTime;
    CMVideoDimensions _currentVideoDimensions;
    CMTime _currentVideoTime;
    CMFormatDescriptionRef _currentAudioSampleBufferFormatDescription;
    
    EAGLContext *_eaglContext;
    
    BOOL preferYUVForStillImage;
    NSString *_sessionPreset;
}

// Session Management
@property (nonatomic) AVCaptureSession *session;
@property (nonatomic) AVCaptureDeviceInput *input;
@property (nonatomic) AVCaptureVideoDataOutput *videoDataOutput;
@property (nonatomic) AVCaptureStillImageOutput *stillImageOutput;

// Utilities
@property (nonatomic) UIBackgroundTaskIdentifier backgroundRecordingID;
@property (nonatomic, getter = isDeviceAuthorized) BOOL deviceAuthorized;

@end

@implementation NativePhotoCapture

@synthesize device, devicePosition;

- (id)initWithPosition:(AVCaptureDevicePosition)capturePosition
{
    if(self = [super init])
    {
        serial_queue                = dispatch_queue_create("serial_queue", DISPATCH_QUEUE_SERIAL);
        _captureSessionQueue        = dispatch_queue_create("capture_session_queue", DISPATCH_QUEUE_SERIAL);
        _eaglContext                = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        _ciContext                  = [CIContext contextWithEAGLContext:_eaglContext
                                                                options:@{ kCIContextWorkingColorSpace : [NSNull null] }];
        _ciContextCoreGraphics      = [CIContext contextWithOptions:@{
                                                                      kCIContextUseSoftwareRenderer: [NSNumber numberWithBool:NO],
                                                                      kCIContextWorkingColorSpace  : [NSNull null]
                                                                      }];
        self.session                = [AVCaptureSession new];
        
        // Create the shared color space object once
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{ sDeviceRgbColorSpace = CGColorSpaceCreateDeviceRGB(); });
        
        // Check for device authorization
        [self checkDeviceAuthorizationStatus];
        
        [self setBackgroundRecordingID:UIBackgroundTaskInvalid];
        
        device                      = [NativePhotoCapture deviceWithMediaType:AVMediaTypeVideo preferringPosition:capturePosition];
        NSError *error              = nil;
        self.input                  = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
        devicePosition              = [device position];
        
        if (!self.input)
        {
            NSLog(@"ERROR: trying to open camera: %@", error);
            return self;
        }
        
        // Audio stuff
        audioDevice = [[AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio] firstObject];
        AVCaptureDeviceInput *audioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:&error];
        
        if (error)
        {
            NSLog(@"Error: %@", error);
            return self;
        }
        
        if ([self.session canAddInput:audioDeviceInput])
            [self.session addInput:audioDeviceInput];
        
        AVCaptureAudioDataOutput *audioDataOutput = [[AVCaptureAudioDataOutput alloc] init];
        [audioDataOutput setSampleBufferDelegate:self queue:_captureSessionQueue];
        
        if([self.session canAddOutput:audioDataOutput])
            [self.session addOutput:audioDataOutput];
        
        self.stillImageOutput = [AVCaptureStillImageOutput new];
        
        self.videoDataOutput = [AVCaptureVideoDataOutput new];
        [self.videoDataOutput setVideoSettings:@{(id)kCVPixelBufferPixelFormatTypeKey : [NSNumber numberWithInteger:kCVPixelFormatType_32BGRA]}];
        [self.videoDataOutput setAlwaysDiscardsLateVideoFrames:YES];
        [self.videoDataOutput setSampleBufferDelegate:self queue:_captureSessionQueue];
        
        if ([self.session canAddInput:self.input])
            [self.session addInput:self.input];

        // This generates the error in ios8
        if([self.session canAddOutput:self.stillImageOutput])
            [self.session addOutput:self.stillImageOutput];
        
        if ([self.session canAddOutput:self.videoDataOutput])
            [self.session addOutput:self.videoDataOutput];
        
        [self.session setSessionPreset:AVCaptureSessionPreset1280x720];
        
        // In order to catch the session error
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(sessionError:) name:AVCaptureSessionRuntimeErrorNotification object:nil];
    }
    
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)sessionError:(NSNotification*)notification
{
    NSDictionary *details = notification.userInfo;
    
    NSLog(@"%@", [details objectForKey:AVCaptureSessionErrorKey]);
}

#pragma mark Static methods

+ (AVCaptureDevice *)deviceWithMediaType:(NSString *)mediaType preferringPosition:(AVCaptureDevicePosition)position
{
	NSArray *devices = [AVCaptureDevice devicesWithMediaType:mediaType];
	AVCaptureDevice *captureDevice = [devices firstObject];
	
	for (AVCaptureDevice *device in devices)
	{
		if ([device position] == position)
		{
			captureDevice = device;
			break;
		}
	}
	
	return captureDevice;
}

- (void)setSessionPreset:(NSString*)newSessionPreset
{
    if([self.session canSetSessionPreset:newSessionPreset])
        [self.session setSessionPreset:newSessionPreset];
}

- (void)switchToNormal      { [self setSessionPreset:AVCaptureSessionPreset1280x720]; }
- (void)switchToPhotoMode   { [self setSessionPreset:AVCaptureSessionPresetPhoto]; }

#pragma mark Interface methods

- (void)setVideoPreviewView:(GLKView *)videoPreviewView
{
    _videoPreviewView                   = videoPreviewView;
    _videoPreviewViewBounds             = CGRectZero;
    _videoPreviewViewBounds.size.width  = _videoPreviewView.drawableWidth;
    _videoPreviewViewBounds.size.height = _videoPreviewView.drawableHeight;
    
    CGAffineTransform transform = CGAffineTransformMakeRotation(M_PI_2);
    
    if (devicePosition == AVCaptureDevicePositionFront)
        transform = CGAffineTransformConcat(transform, CGAffineTransformMakeScale(-1.0, 1.0));
    
    [_videoPreviewView setTransform:transform];
}

- (void)destroyVideoPreviewView
{
    _videoPreviewView       = nil;
    _videoPreviewViewBounds = CGRectZero;
}

- (void)startCamera { [self.session startRunning]; }
- (void)stopCamera  { [self.session stopRunning]; }

#pragma mark Helper methods

- (void)_showAlertViewWithMessage:(NSString *)message title:(NSString *)title
{
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
                                                        message:message
                                                       delegate:nil
                                              cancelButtonTitle:@"Dismiss"
                                              otherButtonTitles:nil];
        [alert show];
    });
}

- (void)_showAlertViewWithMessage:(NSString *)message
{
    [self _showAlertViewWithMessage:message title:@"Error"];
}

- (void)checkDeviceAuthorizationStatus
{
	[AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        
		if (granted)
			[self setDeviceAuthorized:YES];
		else
		{
			dispatch_async(dispatch_get_main_queue(), ^{
                [self _showAlertViewWithMessage:@"The app does not seem to have permission to use Camera, please change privacy settings"];
				[self setDeviceAuthorized:NO];
			});
		}
	}];
}

#pragma mark Private methods

- (CIImage*)applyFiltersOnCIImage:(CIImage*)cImage andIsPreview:(BOOL)isPreview
{
    CIFilter *effectFilter = [CIFilter filterWithName:@"CISepiaTone"];
    [effectFilter setValue:cImage forKey:kCIInputImageKey];
    [effectFilter setValue:@0.8f forKey:kCIInputIntensityKey];
    
    return effectFilter.outputImage;
}

#pragma mark AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer);
    CMMediaType mediaType = CMFormatDescriptionGetMediaType(formatDesc);
    
    // write the audio data if it's from the audio connection
    if (mediaType == kCMMediaType_Audio)
    {
        CMFormatDescriptionRef tmpDesc = _currentAudioSampleBufferFormatDescription;
        _currentAudioSampleBufferFormatDescription = formatDesc;
        CFRetain(_currentAudioSampleBufferFormatDescription);
        
        if (tmpDesc)
            CFRelease(tmpDesc);

        return;
    }
    
    CVImageBufferRef imageBuffer    = CMSampleBufferGetImageBuffer(sampleBuffer);
    CIImage *sourceImage            = [CIImage imageWithCVPixelBuffer:(CVPixelBufferRef)imageBuffer options:nil];
    
    // run the filter through the filter chain
    CIImage *filteredImage          = [self applyFiltersOnCIImage:sourceImage andIsPreview:YES];
    
    CGRect sourceExtent             = sourceImage.extent;
    CGFloat sourceAspect            = sourceExtent.size.width / sourceExtent.size.height;
    CGFloat previewAspect           = _videoPreviewViewBounds.size.width  / _videoPreviewViewBounds.size.height;
    
    // we want to maintain the aspect radio of the screen size, so we clip the video image
    CGRect drawRect = sourceExtent;
    if (sourceAspect > previewAspect)
    {
        // use full height of the video image, and center crop the width
        drawRect.origin.x += (drawRect.size.width - drawRect.size.height * previewAspect) / 2.0;
        drawRect.size.width = drawRect.size.height * previewAspect;
    }
    else
    {
        // use full width of the video image, and center crop the height
        drawRect.origin.y += (drawRect.size.height - drawRect.size.width / previewAspect) / 2.0;
        drawRect.size.height = drawRect.size.width / previewAspect;
    }
    
    [_videoPreviewView bindDrawable];
    
    if (_eaglContext != [EAGLContext currentContext])
        [EAGLContext setCurrentContext:_eaglContext];
    
    // clear eagl view to grey
    glClearColor(0.5, 0.5, 0.5, 1.0);
    glClear(GL_COLOR_BUFFER_BIT);
    
    // set the blend mode to "source over" so that CI will use that
    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
    
    if (filteredImage)
        [_ciContext drawImage:filteredImage inRect:_videoPreviewViewBounds fromRect:drawRect];
    
    [_videoPreviewView display];
}

@end