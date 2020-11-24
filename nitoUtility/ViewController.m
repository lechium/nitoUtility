//
//  ViewController.m
//  nitoUtility
//
//  Created by Kevin Bradley on 9/15/19.
//  Copyright © 2019 nito. All rights reserved.
//

#import "ViewController.h"
#import "Networking/SSHWrapper.h"
#import "Networking/ntvBonjourViewController.h"
#import "Networking/ObjSSH.h"
#import "SVProgressHUD/SVProgressHUD.h"
#import "UICKeyChainStore/UICKeyChainStore.h"
#import <objc/runtime.h>

@interface UIView (darkMode)
- (BOOL)darkMode;
@end

@implementation UIView (darkMode)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
#pragma clang diagnostic ignored "-Wunguarded-availability"
- (BOOL)darkMode {

    if ([[self traitCollection] respondsToSelector:@selector(userInterfaceStyle)]){
        return ([[self traitCollection] userInterfaceStyle] == UIUserInterfaceStyleDark);
    } else {
        return false;
    }
    return false;
}
#pragma clang diagnostic pop

@end

@interface PBSSystemService : NSObject
+(id)sharedInstance;
-(void)deactivateScreenSaver;
@end

@interface PBSPowerManager : NSObject

+(id)sharedInstance;
+(void)load;
+(void)setupPowerManagement;
-(void)_performUserEventWakeDevice;
-(void)wakeDeviceWithOptions:(id)arg1;
-(void)setNeedsDisplayWakeOnPowerOn:(BOOL)arg1;
- (void)sleepDeviceWithOptions:(id)arg1;
-(void)_registerForPowerNotifications;
-(void)_registerForThermalNotifications;
-(void)_enableIdleSleepAndWatchdog;
-(void)_registerForBackBoardNotifications;
-(void)_updateIdleTimer;
@end


@interface ViewController ()

@property (nonatomic, strong) ntvNetService *device;
@property (nonatomic, strong) SSHWrapper *session;
@property (nonatomic, strong) NSArray *applications;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    self.title = @"";
   // [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"defaultCell"];
 
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    
    UIAlertController *alertCon = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    
    [alertCon addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alertCon animated:true completion:nil];
    });
}

- (void)showInvalidPasswordAlertWithCompletion:(void(^)(BOOL shouldContinue))block {
    
    UIAlertController *alertCon = [UIAlertController alertControllerWithTitle:@"Error authenticating" message:@"Please enter the root password for your AppleTV" preferredStyle:UIAlertControllerStyleAlert];
    [alertCon addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.secureTextEntry = true;
    }];
    UIAlertAction *setPassword = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        
        NSString *newPassword = alertCon.textFields[0].text;
        NSError *newError = nil;
        self.session = [SSHWrapper new];
        [self.session connectToHost:self.device.ipAddress port:22 user:@"root" password:newPassword error:&newError];
        
        if (newError == nil){
            [SVProgressHUD show];
            UICKeyChainStore *store = [UICKeyChainStore keyChainStoreWithService:self.device.serviceName];
            store[@"password"] = newPassword;
            if (block){
                block(true);
            }
            
            
        } else {
            [self showInvalidPasswordAlertWithCompletion:block];
        }
    }];
    [alertCon addAction:setPassword];
    [alertCon addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alertCon animated:true completion:nil];
    });
}

- (void)fixCurrentDevice {
    
    [self createSessionWithBlock:^(BOOL success) {
        
        if (success){
            [SVProgressHUD show];
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                [self fixStuffOnSession];
                [self populateApplications];
            });
        }
        
    }];
    
}

- (void)attemptPortCheck {
    NSError *error = nil;
    if (self.device != nil){
        ObjSSH *ssh = [ObjSSH connectToHost:self.device.fullIP withUsername:@"root" password:@"alpine" error:&error];
        if (error) {
            NSLog(@"error: %@", error);
            if (error.code == 100){
                [ssh disconnect];
                NSLog(@"22 failed, attempting 44!");
                [[self device] updatePort:44];
                self.title = [[self device] title];
            }
        }
    }
}

- (BOOL)isJailbroken
{
    NSError *error = nil;
    if (self.device != nil)
    {
        ObjSSH *ssh = [ObjSSH connectToHost:self.device.fullIP withUsername:@"root" password:@"alpine" error:&error];
        if (error)
        {
            NSLog(@"error: %@", [error localizedDescription]);
            if ([[error localizedDescription] isEqualToString:@"Failed to connect"])
            {
                [ssh disconnect];
                return (FALSE);
            }
            [ssh disconnect];
        }
    } else {
        return (FALSE);
    }
    
    return (TRUE);
}


- (void)fixStuffOnSession {
    
  
    __block NSError *connectError = nil;
    NSInteger issuesDetected = 0;
    NSInteger issuesFixed = 0;
    NSString *csCheckCommand = @"/usr/local/bin/jtool --sig /usr/lib/libssl.1.1.dylib";
    NSString *tokenCheckCommand = @"file /var/mobile/Documents/.token";
    NSString *permissionCheckCommand = @"/usr/bin/stat -c \"%a\" /usr/libexec/goNito";
    NSString *sslCodeSignCheck = [self.session executeCommand:csCheckCommand error:&connectError];
    NSString *goNitoPermissionCheck = [self.session executeCommand:permissionCheckCommand error:nil];
    NSString *tokenFileCheck = [self.session executeCommand:tokenCheckCommand error:nil];
    NSString *keyCheckCommand = @"/usr/bin/bash apt-key list | grep -c \"030F 5D6E 7E14 4939 7E04  B6B2 5330 AE38 84B9 841D\"";
    NSMutableString *fixedIssues = [NSMutableString new];
    NSString *keyCheck = [self.session executeCommand:keyCheckCommand error:nil];
    if (keyCheck.integerValue != 1){
        issuesDetected++;
        NSString *keyCommand = @"/usr/bin/bash /usr/bin/apt-key add /Applications/nitoTV.app/pub.key";
        [self.session executeCommand:keyCommand error:nil];
        keyCommand = @"/usr/bin/bash /usr/bin/apt-key add /Applications/nitoTV.app/pub2.key";
        [self.session executeCommand:keyCommand error:nil];
        keyCheck = [self.session executeCommand:keyCheckCommand error:nil];
        if (keyCheck.integerValue == 1){
            issuesFixed++;
            NSLog(@"missing keys fixed!");
            [fixedIssues appendString:@"Fixed missing gpg keys\n"];
        }
    }
    if ([goNitoPermissionCheck integerValue] != 6755){
        issuesDetected++;
        NSLog(@"invalid permissions detected for goNito, repairing...");
        [self.session executeCommand:@"/usr/bin/chmod 6755 /usr/libexec/goNito" error:nil];
        goNitoPermissionCheck =  [self.session executeCommand:permissionCheckCommand error:nil];
        if (goNitoPermissionCheck.integerValue == 6755){
            issuesFixed++;
            NSString *currentIssue = @"goNito permissions fixed!\n";
            NSLog(@"%@", currentIssue);
            [fixedIssues appendString:currentIssue];
        }
        
    }
    if (![sslCodeSignCheck containsString:@"CDHash"]){
        issuesDetected++;
        NSLog(@"Detected unsigned libssl, Repairing!");
        [self.session executeCommand:@"/usr/local/bin/jtool --sign platform --inplace /usr/lib/libssl.1.1.dylib" error:nil];
        sslCodeSignCheck = [self.session executeCommand:csCheckCommand error:&connectError];
        if ([sslCodeSignCheck containsString:@"CDHash"]){
            issuesFixed++;
            NSString *currentIssue = @"unsigned libssl.1.1.dylib fixed!\n";
            NSLog(@"%@", currentIssue);
            [fixedIssues appendString:currentIssue];
        }
    }
    
    if ([tokenFileCheck containsString:@"No such file or directory"]){
        
        issuesDetected++;
        NSLog(@"Missing hidden token, this file is a relic but if its missing it can cause crashes in older versions preventing updates. Repairing!");
        [self.session executeCommand:@"/usr/bin/touch /var/mobile/Documents/.token" error:nil];
        tokenFileCheck = [self.session executeCommand:tokenCheckCommand error:nil];
        if (![tokenFileCheck containsString:@"No such file or directory"]){
            issuesFixed++;
            NSString *currentIssue = @"Missing .token file fixed!\n";
            NSLog(@"%@", currentIssue);
            [fixedIssues appendString:currentIssue];
        }
    }
    NSString *checkAptCommand = @"/usr/bin/apt-get check > /var/root/aptout 2&> /var/root/aptout";
    NSString *fixCommand = @"apt-get -f install";
    [self.session executeCommand:checkAptCommand error:nil];
    NSError *theError = nil;
    NSString *checkApt = [self.session executeCommand:@"/usr/bin/cat /var/root/aptout" error:&theError];
    [self.session executeCommand:@"/usr/bin/rm /var/root/aptout" error:nil];
    NSString *interruptedDPKG = @"E: dpkg was interrupted, you must manually run 'dpkg --configure -a' to correct the problem.";
    if ([checkApt containsString:fixCommand]){
        NSLog(@"found unmet dependencies issue!");
        issuesDetected++;
        [self.session executeCommand:[fixCommand stringByAppendingString:@" -y --force-yes"] error:nil];
        [self.session executeCommand:checkAptCommand error:nil];
        sleep(2);
        //NSString *ls = [wrapper executeCommand:@"ls -al /var/root/aptout" error:nil];
        //NSLog(@"ls: %@", ls);
        NSString *newCheckApt = [self.session executeCommand:@"/usr/bin/cat /var/root/aptout" error:nil];
        NSLog(@"newCheckApt: %@", newCheckApt);
        newCheckApt = [self.session executeCommand:@"/usr/bin/cat /var/root/aptout" error:nil];
        NSLog(@"newCheckApt: %@", newCheckApt);
        if (![newCheckApt containsString:fixCommand]){
            issuesFixed++;
            NSString *currentIssue = @"Unmet dependency issue fixed!\n";
            NSLog(@"%@", currentIssue);
            [fixedIssues appendString:currentIssue];
            [self.session executeCommand:@"/usr/bin/rm aptout" error:nil];
            
        } else {
            [self.session executeCommand:@"/usr/bin/rm aptout" error:nil];
            
            //try try again
            NSString *newCheck = @"/usr/bin/apt-get check /dev/null | grep bulletinh4x -c -m 1";
            NSString *h4xCheck = [self.session executeCommand:newCheck error:nil];
            NSLog(@"h4xCheck: %@", h4xCheck);
            // if (h4xCheck == 1){
            [self.session executeCommand:@"dpkg -r com.matchstic.reprovision" error:nil];
            [self.session executeCommand:@"apt-get -f install -y --force-yes" error:nil];
            [self.session executeCommand:@"apt-get install com.matchstic.reprovision=0.4.5 -y --force-yes" error:nil];
            [self.session executeCommand:checkAptCommand error:nil];
            checkApt = [self.session executeCommand:@"/usr/bin/cat /var/root/aptout" error:&theError];
            checkApt = [self.session executeCommand:@"/usr/bin/cat /var/root/aptout" error:&theError];
            [self.session executeCommand:@"/usr/bin/rm /var/root/aptout" error:nil];
            if (![checkApt containsString:fixCommand]){
                issuesFixed++;
                NSString *currentIssue = @"Reprovision dependency issue fixed!\n";
                NSLog(@"%@", currentIssue);
                [fixedIssues appendString:currentIssue];
            }
            //}
        }
    } else if ([checkApt containsString:interruptedDPKG]){
        issuesDetected++;
        NSError *myErrors = nil;
        NSString *config = [self.session executeCommand:@"/usr/bin/dpkg --configure -a" error:&myErrors];
        //NSLog(@"config: %@", config);
        
        [self.session executeCommand:checkAptCommand error:nil];
        checkApt = [self.session executeCommand:@"/usr/bin/cat aptout" error:&theError];
        [self.session executeCommand:@"/usr/bin/rm aptout" error:nil];
        if (![checkApt containsString:interruptedDPKG]){
            issuesFixed++;
            NSString *currentIssue = @"Unmet dependency issue fixed!\n";
            NSLog(@"%@", currentIssue);
            [fixedIssues appendString:currentIssue];
        } else {
            NSString *dpkgFirstCheck = @"dpkg -C | grep -c \"half configured\"";
            NSInteger returnValue = [[self.session executeCommand:dpkgFirstCheck error:nil] integerValue];
            if (returnValue == 1){
                NSString *dpkgStatus =  @"dpkg -C | grep -m 1 \"appletvos\" | cut -d \":\" -f 1 | tr -d \" \"";
                NSString *errantPackage = [self.session executeCommand:dpkgStatus error:nil];
                NSLog(@"errant package: %@", errantPackage);
                NSString *rmCmd = [NSString stringWithFormat:@"dpkg -r %@", errantPackage];
                [self.session executeCommand:rmCmd error:nil];
                [self.session executeCommand:@"/usr/bin/dpkg --configure -a" error:&myErrors];
                [self.session executeCommand:checkAptCommand error:nil];
                checkApt = [self.session executeCommand:@"/usr/bin/cat aptout" error:&theError];
                [self.session executeCommand:@"/usr/bin/rm aptout" error:nil];
                if (![checkApt containsString:interruptedDPKG]){
                    issuesFixed++;
                    NSString *currentIssue = @"Interrupted dpkg issue fixed!\n";
                    NSLog(@"%@", currentIssue);
                    [fixedIssues appendString:currentIssue];
                }
            }
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [SVProgressHUD dismiss];
    });
    //[wrapper executeCommand:@"dpkg --configure -a" error:nil];
    //[wrapper executeCommand:@"apt-get install -f -y --force-yes" error:nil];
    //[wrapper executeCommand:@"apt-get update" error:nil];
    NSString *plural = @"";
    if (issuesFixed > 1){
        plural = @"s";
    }
    NSString *reportString = @"0 issues detected." ;
    if (issuesFixed > 0 || issuesDetected > 0){
        reportString = [NSString stringWithFormat:@"%lu issue%@ detected. %lu issue%@ fixed\nReport: %@", issuesDetected,plural , issuesFixed, plural, fixedIssues];
    }
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Finished" message:reportString preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alertController animated:TRUE completion:nil];
        
    });
    NSLog(@"%lu issue(s) detected. %lu issue(s) fixed", issuesDetected, issuesFixed);
}

- (void)showNotJailbrokenAlert {
    [self showAlertWithTitle:@"An error occured" message:[NSString stringWithFormat:@"The %@ '%@' running %@ is not currently jailbroken.", self.device.serviceDictionary[@"model"], self.device.serviceName, self.device.serviceDictionary[@"osvers"]]];
}

- (void)attemptCreateSessionWithBlock:(void(^)(BOOL success))block {
 
    __block NSError *connectError = nil;
    if (self.session == nil){
        
        self.session = [SSHWrapper new];
        UICKeyChainStore *store = [UICKeyChainStore keyChainStoreWithService:self.device.serviceName];
        NSString *pwCheck = store[@"password"];
        if (!pwCheck){
            pwCheck = @"alpine";
        }
        [self.session connectToHost:self.device.ipAddress port:self.device.port user:@"root" password:pwCheck error:&connectError];
        if (connectError != nil){
            if (connectError.code == 403){
                NSLog(@"bad pasword");
            } else if (connectError.code == 400){
                NSLog(@"failed to connect!");
            }
            //NSLog(@"connect error: %@", connectError);
            if (block){
                block(false);
            }
            
        } else {
            
            block(true);
        }
    } else {
        block(true);
    }
    
}

- (void)createSessionWithBlock:(void(^)(BOOL success))block {
    [self attemptPortCheck];
    if (![self isJailbroken]){
        [self showNotJailbrokenAlert];
        block(false);
        return;
    }
    __block NSError *connectError = nil;
    if (self.session == nil){
 
        self.session = [SSHWrapper new];
        UICKeyChainStore *store = [UICKeyChainStore keyChainStoreWithService:self.device.serviceName];
        NSString *pwCheck = store[@"password"];
        if (!pwCheck){
            pwCheck = @"alpine";
        }
        [self.session connectToHost:self.device.ipAddress port:self.device.port user:@"root" password:pwCheck error:&connectError];
        if (connectError != nil){
            [self showInvalidPasswordAlertWithCompletion:^(BOOL shouldContinue) {
                if (block){
                    block(shouldContinue);
                }
            }];
        } else {
           
            block(true);
        }
    } else {
        block(true);
    }
}


/*
 
 The following packages are only half configured, probably due to problems
 configuring them the first time.  The configuration should be retried using
 dpkg --configure <package> or the configure menu option in dselect:
 com.nito.breaker:appletvos-arm64 This is a test application to deliberately break dpkg, do
 
 The following packages have been triggered, but the trigger processing
 has not yet been done.  Trigger processing can be requested using
 dselect or dpkg --configure --pending (or dpkg --triggers-only):
 com.nito.nitotv4:appletvos-arm64 AppleTV 4 Package installer
 
 The following packages are missing the md5sums control file in the
 database, they need to be reinstalled:
 cy+cpu.arm64:appletvos-arm64 virtual CPU dependency
 cy+kernel.darwin:appletvos-arm64 virtual kernel dependency
 cy+lib.corefoundation:appletvos-arm64 virtual corefoundation dependency
 cy+model.appletv:appletvos-arm64 virtual model dependency
 cy+os.ios:appletvos-arm64 virtual operating system dependency
 firmware:appletvos-arm64 almost impressive Apple frameworks
 
 */

- (void)attemptUpdate:(NSString *)update {
    
    [self createSessionWithBlock:^(BOOL success) {
        
        if (success){
            [SVProgressHUD show];
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                
                [self updateToLatest:update];
                [self populateApplications];
            });
        }
        
    }];
}

- (void)_changePasswordSetup {
    
    __block NSString *thePassword = nil;
    __block NSString *verifyPassword = nil;
    UIAlertController *alertCon = [UIAlertController alertControllerWithTitle:@"Enter new password" message:@"Enter a new root & mobile password for your AppleTV" preferredStyle:UIAlertControllerStyleAlert];
    [alertCon addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Enter Password";
        textField.secureTextEntry = true;
    }];
    [alertCon addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Verify Password";
        textField.secureTextEntry = true;
    }];
    UIAlertAction *commandAction = [UIAlertAction actionWithTitle:@"Change Password" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        
        thePassword = alertCon.textFields[0].text;
        verifyPassword = alertCon.textFields[1].text;
        if ([thePassword isEqualToString:verifyPassword]){
            [self createSessionWithBlock:^(BOOL success) {
                
                if (success){
                    [SVProgressHUD show];
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                        
                        NSString *sendString = [NSString stringWithFormat:@"echo -e \"%@\n%@\" | passwd root", thePassword, thePassword];
                        NSString *sendString2 = [NSString stringWithFormat:@"echo -e \"%@\n%@\" | passwd mobile", thePassword, thePassword];
                        [self runCustomCommand:sendString];
                        [self runCustomCommand:sendString2];
                        UICKeyChainStore *store = [UICKeyChainStore keyChainStoreWithService:self.device.serviceName];
                        store[@"password"] = thePassword;
                        //[self populateApplications];
                    });
                }
                
            }];

        } else {
            [self _changePasswordSetup];
        }
        
            }];
    
    [alertCon addAction:commandAction];
    [alertCon addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alertCon animated:true completion:nil];
    });
    
}

- (void)_runCommandSetup {
    
    __block NSString *commandString = nil;
    UIAlertController *alertCon = [UIAlertController alertControllerWithTitle:@"Enter command" message:@"Please enter a custom command you would like to send to your AppleTV" preferredStyle:UIAlertControllerStyleAlert];
    [alertCon addTextFieldWithConfigurationHandler:nil];
    UIAlertAction *commandAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        
        commandString = alertCon.textFields[0].text;
        [self createSessionWithBlock:^(BOOL success) {
            
            if (success){
                [SVProgressHUD show];
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                    
                    [self runCustomCommand:commandString];
                    sleep(1);
                    [self populateApplications];
                });
            }
            
        }];
    }];
    
    [alertCon addAction:commandAction];
    [alertCon addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alertCon animated:true completion:nil];
    });
    
}

- (void)runCustomCommand:(NSString *)command {
    
    NSLog(@"command: %@", command);
    NSString *results = [self.session executeCommand:command error:nil];
    NSLog(@"results: %@", results);
    dispatch_async(dispatch_get_main_queue(), ^{
        [SVProgressHUD dismiss];
    });
    [self showAlertWithTitle:@"Finished" message:results];
}
- (NSArray *)availableApps {
    
    NSMutableArray *apps = [NSMutableArray new];
    [self.session executeCommand:@"lsdtrip apps  | tr -d \"\t\" > /var/root/trip.txt" error:nil];
    NSString *rawList = [self.session executeCommand:@"cat /var/root/trip.txt" error:nil];
    NSLog(@"rawList: %@", rawList);
    if (rawList.length > 0){
        NSArray *lines = [rawList componentsSeparatedByString:@"\n"];
        [lines enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSArray *appComponents = [obj componentsSeparatedByString:@" ("];
            if (appComponents.count > 1){
                NSString *appName = appComponents[0];
                NSString *identifier = [appComponents[1] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@") "]];
                if (appName.length > 0 && identifier.length > 0){
                    NSDictionary *anApp = @{@"name": appName, @"identifier":identifier };
                    [apps addObject:anApp];
                }
            }
        }];
    }
    NSSortDescriptor *nameDesc = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:true];
    return [apps sortedArrayUsingDescriptors:@[nameDesc]];
    
    
}
- (void)updateToLatest:(NSString *)latest {
    
    [self.session executeCommand:@"apt-get update" error:nil];
    NSString *installString = @"apt-get -y -u dist-upgrade --force-yes";
    if (latest.length > 0){
        installString = [NSString stringWithFormat:@"apt-get install %@ -y --force-yes", latest];
    }
    NSLog(@"install string: %@", installString);
    NSString *results = [self.session executeCommand:installString error:nil];
    NSLog(@"results: %@", results);

    dispatch_async(dispatch_get_main_queue(), ^{
        [SVProgressHUD dismiss];
    });
    [self showAlertWithTitle:@"Finished" message:results];
    
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (self.device != nil){
        if (self.applications.count > 0){
            return 4;
        }
        return 3;
    } else {
        return 1;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.device == nil) return 1;
    switch (section) {
        case 1:
            return 3;
        case 2:
            return 7;
        case 3:
            return self.applications.count;
        default:
            break;
    }
    return 1;
}

-(NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    
    switch (section) {
        case 0:
            return nil;
        case 1:
            return @"Utilities";
        case 2:
            return @"Commands";
        case 3:
            return @"Applications";
        default:
            break;
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
   // UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"defaultCell" forIndexPath:indexPath];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"defaultCell"];
    if (!cell){
        
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"defaultCell"];
    }
    cell.detailTextLabel.text = nil;
    //cell.selectionStyle = UITableViewCellSelectionStyleNone;
    switch (indexPath.section) {
        case 0:
            cell.textLabel.text = @"Select AppleTV";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            if ([self.view darkMode]){
                cell.textLabel.textColor = [UIColor whiteColor];
            } else {
                cell.textLabel.textColor = [UIColor blackColor];
            }
            break;
            
        case 1:
            cell.accessoryType = UITableViewCellAccessoryNone;
            switch (indexPath.row) {
                case 0:
                    cell.textLabel.text = @"Run Diagnostics";
                    cell.textLabel.textColor = [UIColor redColor];
                    break;
                case 1:
                    cell.textLabel.text = @"Update nitoTV";
                    if ([self.view darkMode]){
                        cell.textLabel.textColor = [UIColor whiteColor];
                    } else {
                        cell.textLabel.textColor = [UIColor blackColor];
                    }
                    break;
                case 2:
                    cell.textLabel.text = @"Update All";
                    if ([self.view darkMode]){
                        cell.textLabel.textColor = [UIColor whiteColor];
                    } else {
                        cell.textLabel.textColor = [UIColor blackColor];
                    }
                    break;
          
                    
                default:
                    break;
            }
            break;

            
        case 2: //section 2;
            cell.accessoryType = UITableViewCellAccessoryNone;
            if ([self.view darkMode]){
                cell.textLabel.textColor = [UIColor whiteColor];
            } else {
                cell.textLabel.textColor = [UIColor blackColor];
            }
            switch (indexPath.row) {
                case 0:
                    cell.textLabel.text = @"uicache";
                    break;
                case 1:
                    cell.textLabel.text = @"ldrestart";
                    break;
                case 2:
                    cell.textLabel.text = @"respring";
                    break;
                case 3:
                    cell.textLabel.text = @"sleep";
                    break;
                case 4:
                    cell.textLabel.text = @"wake";
                    break;
                case 5:
                    cell.textLabel.text = @"Custom command";
                    break;
                    
                case 6: //change root/mobile passwords
                    cell.textLabel.text = @"Change device passwords";
                    break;
                
                default:
                    break;
            }
            break;
            
        case 3:
        {
            NSDictionary *entry = self.applications[indexPath.row];
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.textLabel.text = entry[@"name"];
            cell.detailTextLabel.text = entry[@"identifier"];
            if ([self.view darkMode]){
                cell.textLabel.textColor = [UIColor whiteColor];
            } else {
                cell.textLabel.textColor = [UIColor blackColor];
            }
            cell.detailTextLabel.textColor = [UIColor grayColor];
        }
            break;
            
        default:
            break;
    }
    
    return cell;
}

- (void)terminateCurrentSession {
    
    if (self.session != nil){
        [self.session closeConnection];
        self.session = nil;
        self.applications = nil;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
    
    [tableView deselectRowAtIndexPath:indexPath animated:true];
    if (indexPath.section == 0){
        ntvBonjourViewController *bv = [[ntvBonjourViewController alloc] initWithStyle:UITableViewStylePlain];
        bv.deviceSelectedBlock = ^(ntvNetService *device) {
            
            [self.navigationController popViewControllerAnimated:true];
            self.title = device.title;
            self.device = device;
            [self terminateCurrentSession];
            [self.tableView reloadData];
            [self loadAppsIfPossible];
 
            
        };
        [self.navigationController pushViewController:bv animated:true];
        
    } else {
        
        if (self.device != nil){
            
            [self processIndexPathSelect:indexPath];
        }
        
    }
    
}

- (void)loadAppsIfPossible {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [self attemptCreateSessionWithBlock:^(BOOL success) {
            if (success){
                [self populateApplications];
            } else {
                self.session = nil;
            }
        }];
    });
   
    
}

- (void)processIndexPathSelect:(NSIndexPath *)indexPath {
    
    switch (indexPath.section) {
        case 1:
            [self processUtilityIndex:indexPath.row];
            break;
            
        case 2:
            [self processCommandIndex:indexPath.row];
            break;
            
        case 3:
            [self processApplicationIndex:indexPath.row];
            break;
            
        default:
            break;
    }
}

- (void)processApplicationIndex:(NSInteger)index {
    
    NSString *identifier = self.applications[index][@"identifier"];
    NSLog(@"launch app with identifier: %@", identifier );
    [self _runCommand:[NSString stringWithFormat:@"lsdtrip launch %@", identifier]];
    
}

- (void)processCommandIndex:(NSInteger)index {
    
    switch (index) {
        case 0:
            [self _runCommand:@"uicache"];
            break;
        case 1:
            [self _runCommand:@"ldrestart"];
            break;
        case 2:
            [self _runCommand:@"killall -9 backboardd"];
            break;
        case 3:
            [self _runCommand:@"sleepy"];
            break;
        case 4:
            [self _runCommand:@"wake"];
            break;
        case 5:
            [self _runCommandSetup];
            break;
            
        case 6:
            [self _changePasswordSetup];
            break;
            
        default:
            break;
    }
}

- (void)populateApplications {
    
    if (self.session != nil){
        if (self.applications == nil){
            self.applications = [self availableApps];
            dispatch_async(dispatch_get_main_queue(), ^{
                 [self.tableView reloadData];
            });
           
        }
    }
    
}

- (void)_runCommand:(NSString *)commandString {
    
    [self createSessionWithBlock:^(BOOL success) {
        
        if (success){
            [SVProgressHUD show];
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                [self runCustomCommand:commandString];
                [self populateApplications];
            });
        }
        
    }];
}



- (void)processUtilityIndex:(NSInteger)index {
    
    switch (index) {
        case 0:
            [self fixCurrentDevice];
            break;
        case 1:
            [self attemptUpdate:@"com.nito.nitotv4"];
            break;
        case 2:
            [self attemptUpdate:nil];
            break;
            break;
        default:
            break;
    }
}

@end
