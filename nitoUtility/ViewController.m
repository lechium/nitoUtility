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

- (void)showInvalidPasswordAlertForIP:(NSString *)ipAddress {
    

    
    UIAlertController *alertCon = [UIAlertController alertControllerWithTitle:@"Non default root password" message:@"Please enter the root password for your AppleTV" preferredStyle:UIAlertControllerStyleAlert];
    
    [alertCon addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        
        textField.secureTextEntry = true;
    }];
    
    UIAlertAction *setPassword = [UIAlertAction actionWithTitle:@"Set Password" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        
        NSString *newPassword = alertCon.textFields[0].text;
        NSError *newError = nil;
        SSHWrapper *wrapper = [SSHWrapper new];[wrapper connectToHost:ipAddress port:22 user:@"root" password:newPassword error:&newError];
        
        if (newError == nil){
            [self fixStuffOnSession:wrapper];
        } else {
            [self showInvalidPasswordAlertForIP:ipAddress];
        }
        
    }];
    
    [alertCon addAction:setPassword];
    [alertCon addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    dispatch_async(dispatch_get_main_queue(), ^{
            [self presentViewController:alertCon animated:true completion:nil];
    });

}


- (void)fixDeviceAtIP:(NSString *)ipAddress {
    
    if ([self isJailbroken]){
        NSLog(@"is jailbroken!");
    } else {
        NSLog(@"is NOT jailbroken!");
        return;
    }
    __block NSError *connectError = nil;
    SSHWrapper *wrapper = [SSHWrapper new];
    [wrapper connectToHost:ipAddress port:22 user:@"root" password:@"alpine" error:&connectError];
    
    if (connectError){
        NSLog(@"connection error: %@", connectError);
        [self showInvalidPasswordAlertForIP:ipAddress];
        
    } else {
        [self fixStuffOnSession:wrapper];
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
    NSString *results = [wrapper executeCommand:@"/usr/local/bin/jtool --sig /usr/lib/libssl.1.1.dylib" error:&connectError];
    NSString *perms = [wrapper executeCommand:@"/usr/bin/stat -c \"%a\" /usr/libexec/goNito" error:nil];
    NSString *lastCheck = [wrapper executeCommand:@"file /var/mobile/Documents/.token" error:nil];
    
    if ([perms integerValue] != 6755){
        issuesDetected++;
        NSLog(@"invalid permissions detected for goNito, repairing...");
        [wrapper executeCommand:@"/usr/bin/chmod 6755 /usr/libexec/goNito" error:nil];
        perms =  [wrapper executeCommand:@"/usr/bin/stat -c \"%a\" /usr/libexec/goNito" error:nil];
        if (perms.integerValue == 6755){
            issuesFixed++;
            NSLog(@"goNito permissions fixed!");
        }
        
    }
    if (![results containsString:@"CDHash"]){
        issuesDetected++;
        NSLog(@"Detected unsigned libssl, Repairing!");
        [wrapper executeCommand:@"/usr/local/bin/jtool --sign platform --inplace /usr/lib/libssl.1.1.dylib" error:nil];
        results = [wrapper executeCommand:@"/usr/local/bin/jtool --sig /usr/lib/libssl.1.1.dylib" error:&connectError];
        if ([results containsString:@"CDHash"]){
            NSLog(@"libssl issue fixed!");
            issuesFixed++;
        }
    }
    
    if ([lastCheck containsString:@"No such file or directory"]){
        
        issuesDetected++;
        NSLog(@"Missing hidden token, this file is a relic but if its missing it can cause crashes in older versions preventing updates. Repairing!");
        [wrapper executeCommand:@"/usr/bin/touch /var/mobile/Documents/.token" error:nil];
        lastCheck = [wrapper executeCommand:@"file /var/mobile/Documents/.token" error:nil];
        if (![lastCheck containsString:@"No such file or directory"]){
            NSLog(@"Created .token file");
            issuesFixed++;
        }
    }
    NSString *reportString = [NSString stringWithFormat:@"%lu issues detected. %lu issues fixed", issuesDetected, issuesFixed];
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Finished" message:reportString preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alertController animated:TRUE completion:nil];
        
    });
    NSLog(@"%lu issues detected. %lu issues fixed", issuesDetected, issuesFixed);
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
    
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    
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
            
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                [self fixDeviceAtIP:self.device.ipAddress];
            });
        }

    }
    
}


@end
