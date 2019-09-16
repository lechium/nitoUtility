
#import <UIKit/UIKit.h>
#import "ntvNetService.h"


@interface ntvBonjourViewController : UITableViewController <NSNetServiceBrowserDelegate>
{
    NSNetServiceBrowser * browser;
    NSMutableArray * services;
    BOOL searching;
    id delegate;
}

@property (nonatomic, retain) id delegate;
@property (nonatomic, copy) void (^deviceSelectedBlock)(ntvNetService *device);
@end
