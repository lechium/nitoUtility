//
//  ViewController.m
//  nitoUtility
//
//  Created by Kevin Bradley on 9/15/19.
//  Copyright © 2019 nito. All rights reserved.
//

#import "ViewController.h"
#import "SSHWrapper.h"
#import "ntvBonjourViewController.h"
#import "ObjSSH.h"
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
    
    //dispatch_async(dispatch_get_main_queue(), ^{
    
   // });
    
   
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
        }
    }
    if ([goNitoPermissionCheck integerValue] != 6755){
        issuesDetected++;
        NSLog(@"invalid permissions detected for goNito, repairing...");
        [wrapper executeCommand:@"/usr/bin/chmod 6755 /usr/libexec/goNito" error:nil];
        goNitoPermissionCheck =  [wrapper executeCommand:permissionCheckCommand error:nil];
        if (goNitoPermissionCheck.integerValue == 6755){
            issuesFixed++;
            NSLog(@"goNito permissions fixed!");
        }
        
    }
    if (![sslCodeSignCheck containsString:@"CDHash"]){
        issuesDetected++;
        NSLog(@"Detected unsigned libssl, Repairing!");
        [wrapper executeCommand:@"/usr/local/bin/jtool --sign platform --inplace /usr/lib/libssl.1.1.dylib" error:nil];
        sslCodeSignCheck = [wrapper executeCommand:csCheckCommand error:&connectError];
        if ([sslCodeSignCheck containsString:@"CDHash"]){
            NSLog(@"libssl issue fixed!");
            issuesFixed++;
        }
    }
    
    if ([tokenFileCheck containsString:@"No such file or directory"]){
        
        issuesDetected++;
        NSLog(@"Missing hidden token, this file is a relic but if its missing it can cause crashes in older versions preventing updates. Repairing!");
        [wrapper executeCommand:@"/usr/bin/touch /var/mobile/Documents/.token" error:nil];
        tokenFileCheck = [wrapper executeCommand:tokenCheckCommand error:nil];
        if (![tokenFileCheck containsString:@"No such file or directory"]){
            NSLog(@"Created .token file");
            issuesFixed++;
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
        reportString = [NSString stringWithFormat:@"%lu issue%@ detected. %lu issue%@ fixed", issuesDetected,plural , issuesFixed, plural];
    }
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Finished" message:reportString preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alertController animated:TRUE completion:nil];
        
    });
    NSLog(@"%lu issue(s) detected. %lu issue(s) fixed", issuesDetected, issuesFixed);
}

- (void)updateAllToLatest:(SSHWrapper *)session {
    
    
    
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
