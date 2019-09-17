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

@interface ViewController ()

@property (nonatomic, strong) ntvNetService *device;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    self.title = @"";
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"defaultCell"];
    
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    
    UIAlertController *alertCon = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    
    [alertCon addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alertCon animated:true completion:nil];
    });
}

- (void)showInvalidPasswordAlert {
    
    UIAlertController *alertCon = [UIAlertController alertControllerWithTitle:@"Non default root password" message:@"Please enter the root password for your AppleTV" preferredStyle:UIAlertControllerStyleAlert];
    [alertCon addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.secureTextEntry = true;
    }];
    UIAlertAction *setPassword = [UIAlertAction actionWithTitle:@"Set Password" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        
        NSString *newPassword = alertCon.textFields[0].text;
        NSError *newError = nil;
        SSHWrapper *wrapper = [SSHWrapper new];[wrapper connectToHost:self.device.ipAddress port:22 user:@"root" password:newPassword error:&newError];
        
        if (newError == nil){
            [SVProgressHUD show];
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                [self fixStuffOnSession:wrapper];
            });
            
        } else {
            [self showInvalidPasswordAlert];
        }
    }];
    [alertCon addAction:setPassword];
    [alertCon addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alertCon animated:true completion:nil];
    });
}


- (void)fixCurrentDevice {
    if (![self isJailbroken]){
        //NSLog(@"is NOT jailbroken!");
        [self showAlertWithTitle:@"An error occured" message:[NSString stringWithFormat:@"The %@ '%@' running %@ is not currently jailbroken.", self.device.serviceDictionary[@"model"], self.device.serviceName, self.device.serviceDictionary[@"osvers"]]];
        return;
    }
    __block NSError *connectError = nil;
    SSHWrapper *wrapper = [SSHWrapper new];
    [wrapper connectToHost:self.device.ipAddress port:22 user:@"root" password:@"alpine" error:&connectError];
    
    if (connectError){
        NSLog(@"connection error: %@", connectError);
        [self showInvalidPasswordAlert];
    } else {
        [SVProgressHUD show];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            [self fixStuffOnSession:wrapper];
        });
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


- (void)fixStuffOnSession:(SSHWrapper *)wrapper {
    
    __block NSError *connectError = nil;
    NSInteger issuesDetected = 0;
    NSInteger issuesFixed = 0;
    NSString *csCheckCommand = @"/usr/local/bin/jtool --sig /usr/lib/libssl.1.1.dylib";
    NSString *tokenCheckCommand = @"file /var/mobile/Documents/.token";
    NSString *permissionCheckCommand = @"/usr/bin/stat -c \"%a\" /usr/libexec/goNito";
    NSString *sslCodeSignCheck = [wrapper executeCommand:csCheckCommand error:&connectError];
    NSString *goNitoPermissionCheck = [wrapper executeCommand:permissionCheckCommand error:nil];
    NSString *tokenFileCheck = [wrapper executeCommand:tokenCheckCommand error:nil];
    NSString *keyCheckCommand = @"/usr/bin/bash apt-key list | grep -c \"030F 5D6E 7E14 4939 7E04  B6B2 5330 AE38 84B9 841D\"";
    NSMutableString *fixedIssues = [NSMutableString new];
    NSString *keyCheck = [wrapper executeCommand:keyCheckCommand error:nil];
    if (keyCheck.integerValue != 1){
        issuesDetected++;
        NSString *keyCommand = @"/usr/bin/bash /usr/bin/apt-key add /Applications/nitoTV.app/pub.key";
        [wrapper executeCommand:keyCommand error:nil];
        keyCommand = @"/usr/bin/bash /usr/bin/apt-key add /Applications/nitoTV.app/pub2.key";
        [wrapper executeCommand:keyCommand error:nil];
        keyCheck = [wrapper executeCommand:keyCheckCommand error:nil];
        if (keyCheck.integerValue == 1){
            issuesFixed++;
            NSLog(@"missing keys fixed!");
            [fixedIssues appendString:@"Fixed missing gpg keys\n"];
        }
    }
    if ([goNitoPermissionCheck integerValue] != 6755){
        issuesDetected++;
        NSLog(@"invalid permissions detected for goNito, repairing...");
        [wrapper executeCommand:@"/usr/bin/chmod 6755 /usr/libexec/goNito" error:nil];
        goNitoPermissionCheck =  [wrapper executeCommand:permissionCheckCommand error:nil];
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
        [wrapper executeCommand:@"/usr/local/bin/jtool --sign platform --inplace /usr/lib/libssl.1.1.dylib" error:nil];
        sslCodeSignCheck = [wrapper executeCommand:csCheckCommand error:&connectError];
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
        [wrapper executeCommand:@"/usr/bin/touch /var/mobile/Documents/.token" error:nil];
        tokenFileCheck = [wrapper executeCommand:tokenCheckCommand error:nil];
        if (![tokenFileCheck containsString:@"No such file or directory"]){
            issuesFixed++;
            NSString *currentIssue = @"Missing .token file fixed!\n";
            NSLog(@"%@", currentIssue);
            [fixedIssues appendString:currentIssue];
        }
    }
    NSString *checkAptCommand = @"/usr/bin/apt-get check > /var/root/aptout 2&> /var/root/aptout";
    NSString *fixCommand = @"apt-get -f install";
    [wrapper executeCommand:checkAptCommand error:nil];
    NSError *theError = nil;
    NSString *checkApt = [wrapper executeCommand:@"/usr/bin/cat /var/root/aptout" error:&theError];
    [wrapper executeCommand:@"/usr/bin/rm /var/root/aptout" error:nil];
    NSString *interruptedDPKG = @"E: dpkg was interrupted, you must manually run 'dpkg --configure -a' to correct the problem.";
    if ([checkApt containsString:fixCommand]){
        NSLog(@"found unmet dependencies issue!");
        issuesDetected++;
        [wrapper executeCommand:[fixCommand stringByAppendingString:@" -y --force-yes"] error:nil];
        [wrapper executeCommand:checkAptCommand error:nil];
        sleep(2);
        //NSString *ls = [wrapper executeCommand:@"ls -al /var/root/aptout" error:nil];
        //NSLog(@"ls: %@", ls);
        NSString *newCheckApt = [wrapper executeCommand:@"/usr/bin/cat /var/root/aptout" error:nil];
        NSLog(@"newCheckApt: %@", newCheckApt);
        newCheckApt = [wrapper executeCommand:@"/usr/bin/cat /var/root/aptout" error:nil];
        NSLog(@"newCheckApt: %@", newCheckApt);
        if (![newCheckApt containsString:fixCommand]){
            issuesFixed++;
            NSString *currentIssue = @"Unmet dependency issue fixed!\n";
            NSLog(@"%@", currentIssue);
            [fixedIssues appendString:currentIssue];
            [wrapper executeCommand:@"/usr/bin/rm aptout" error:nil];
            
        } else {
            [wrapper executeCommand:@"/usr/bin/rm aptout" error:nil];
            
            //try try again
            NSString *newCheck = @"/usr/bin/apt-get check /dev/null | grep bulletinh4x -c -m 1";
            NSString *h4xCheck = [wrapper executeCommand:newCheck error:nil];
            NSLog(@"h4xCheck: %@", h4xCheck);
           // if (h4xCheck == 1){
                [wrapper executeCommand:@"dpkg -r com.matchstic.reprovision" error:nil];
                [wrapper executeCommand:@"apt-get -f install -y --force-yes" error:nil];
                [wrapper executeCommand:@"apt-get install com.matchstic.reprovision=0.4.5 -y --force-yes" error:nil];
                [wrapper executeCommand:checkAptCommand error:nil];
                checkApt = [wrapper executeCommand:@"/usr/bin/cat /var/root/aptout" error:&theError];
                checkApt = [wrapper executeCommand:@"/usr/bin/cat /var/root/aptout" error:&theError];
                [wrapper executeCommand:@"/usr/bin/rm /var/root/aptout" error:nil];
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
        NSString *config = [wrapper executeCommand:@"/usr/bin/dpkg --configure -a" error:&myErrors];
        //NSLog(@"config: %@", config);
        [wrapper executeCommand:checkAptCommand error:nil];
        checkApt = [wrapper executeCommand:@"/usr/bin/cat aptout" error:&theError];
        [wrapper executeCommand:@"/usr/bin/rm aptout" error:nil];
        if (![checkApt containsString:interruptedDPKG]){
            issuesFixed++;
            NSString *currentIssue = @"Unmet dependency issue fixed!\n";
            NSLog(@"%@", currentIssue);
            [fixedIssues appendString:currentIssue];
        } else {
            NSString *dpkgFirstCheck = @"dpkg -C | grep -c \"half configured\"";
            NSInteger returnValue = [[wrapper executeCommand:dpkgFirstCheck error:nil] integerValue];
            if (returnValue == 1){
                NSString *dpkgStatus =  @"dpkg -C | grep -m 1 \"appletvos\" | cut -d \":\" -f 1 | tr -d \" \"";
                NSString *errantPackage = [wrapper executeCommand:dpkgStatus error:nil];
                NSLog(@"errant package: %@", errantPackage);
                NSString *rmCmd = [NSString stringWithFormat:@"dpkg -r %@", errantPackage];
                [wrapper executeCommand:rmCmd error:nil];
                [wrapper executeCommand:@"/usr/bin/dpkg --configure -a" error:&myErrors];
                [wrapper executeCommand:checkAptCommand error:nil];
                checkApt = [wrapper executeCommand:@"/usr/bin/cat aptout" error:&theError];
                [wrapper executeCommand:@"/usr/bin/rm aptout" error:nil];
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

- (void)updateAllToLatest:(SSHWrapper *)session {
    
    [session executeCommand:@"apt-get update" error:nil];
    [session executeCommand:@"apt-get -y -u dist-upgrade --force-yes" error:nil];
    
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (self.device != nil){
        return 2;
    } else {
        return 1;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"defaultCell" forIndexPath:indexPath];
    
    //cell.selectionStyle = UITableViewCellSelectionStyleNone;
    switch (indexPath.section) {
        case 0:
            cell.textLabel.text = @"Select AppleTV";
            break;
            
        case 1:
            cell.textLabel.text = @"Run Diagnostics";
            cell.textLabel.textColor = [UIColor redColor];
            break;
            
        default:
            break;
    }
    
    return cell;
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
    
    [tableView deselectRowAtIndexPath:indexPath animated:true];
    if (indexPath.section == 0){
        ntvBonjourViewController *bv = [[ntvBonjourViewController alloc] initWithStyle:UITableViewStylePlain];
        bv.deviceSelectedBlock = ^(ntvNetService *device) {
            
            [self.navigationController popViewControllerAnimated:true];
            self.title = device.title;
            self.device = device;
            [self.tableView reloadData];
            
        };
        [self.navigationController pushViewController:bv animated:true];
        
    } else {
        
        if (self.device != nil){
            
            [self fixCurrentDevice];
        }
        
    }
    
}


@end
