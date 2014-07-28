#import "MainController.h"
#import "NativePhotoCapture.h"

@interface MainController()
{
    GLKView *_videoPreviewView;
    UIButton *switchNormal;
    UIButton *switchPhoto;
    NativePhotoCapture *photoCapture;
}

@end

@implementation MainController

- (id)init
{
    if (self = [super init])
    {
    }
    
    return self;
}

- (void)viewDidLoad
{
    _videoPreviewView = [GLKView new];
    [_videoPreviewView setEnableSetNeedsDisplay:NO];
    [_videoPreviewView setTransform:CGAffineTransformMakeRotation(M_PI_2)];
    [self.view addSubview:_videoPreviewView];
    
    switchPhoto = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 200, 50)];
    [switchPhoto setTitle:@"Switch to Photo" forState:UIControlStateNormal];
    [switchPhoto setBackgroundColor:[UIColor redColor]];
    [switchPhoto setCenter:CGPointMake(self.view.center.x, self.view.frame.size.height - 270)];
    [switchPhoto addTarget:self action:@selector(switchPhoto) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:switchPhoto];
    
    switchNormal = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 200, 50)];
    [switchNormal setTitle:@"Switch to Normal" forState:UIControlStateNormal];
    [switchNormal setBackgroundColor:[UIColor redColor]];
    [switchNormal setCenter:CGPointMake(self.view.center.x, self.view.frame.size.height - 200)];
    [switchNormal addTarget:self action:@selector(switchNormal) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:switchNormal];
    
    [self initCapture];
    
    [super viewDidLoad];
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

#pragma mark Custom Methods

- (void)switchPhoto
{
    [switchPhoto setBackgroundColor:[UIColor blackColor]];
    [switchNormal setBackgroundColor:[UIColor redColor]];

    [photoCapture switchToPhotoMode];
}

- (void)switchNormal
{
    [switchPhoto setBackgroundColor:[UIColor redColor]];
    [switchNormal setBackgroundColor:[UIColor blackColor]];
    
    [photoCapture switchToNormal];
}

- (void)initCapture
{
    photoCapture = [[NativePhotoCapture alloc] initWithPosition:AVCaptureDevicePositionBack];
    
    CGRect bounds = [[UIScreen mainScreen] bounds];
    [_videoPreviewView setContext:photoCapture.eaglContext];
    [_videoPreviewView setBounds:bounds];
    [_videoPreviewView setFrame:bounds];
    [_videoPreviewView bindDrawable];
    [photoCapture setVideoPreviewView:_videoPreviewView];
    
    [photoCapture startCamera];
    
    [switchNormal setBackgroundColor:[UIColor blackColor]];
}

@end