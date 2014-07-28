#import <UIKit/UIKit.h>
#import "MainController.h"

@interface AppDelegate : UIResponder <UIApplicationDelegate>
{
    MainController *mainController;
}

@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) MainController *mainController;

@end