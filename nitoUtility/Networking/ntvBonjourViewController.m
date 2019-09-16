#import "ntvBonjourViewController.h"


@interface ntvBonjourViewController ()

@end

@implementation ntvBonjourViewController

@synthesize  delegate;

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    browser = [[NSNetServiceBrowser alloc] init];
    services = [NSMutableArray array];
    [browser setDelegate:self];
    [browser stop]; //if you dont stop it, it never works in the first place
    [browser searchForServicesOfType:@"_mediaremotetv._tcp." inDomain:@""];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
}


#pragma mark NSNetService / Bonjour Stuff


- (NSDictionary *)stringDictionaryFromService:(NSNetService *)theService
{
	NSData *txtRecordDict = [theService TXTRecordData];
	
	NSDictionary *theDict = [NSNetService dictionaryFromTXTRecordData:txtRecordDict];
	NSMutableDictionary *finalDict = [[NSMutableDictionary alloc] init];
	NSArray *keys = [theDict allKeys];
	for (NSString *theKey in keys)
	{
		NSString *currentString = [[NSString alloc] initWithData:[theDict valueForKey:theKey] encoding:NSUTF8StringEncoding];
		[finalDict setObject:currentString forKey:theKey];
	}
	
	return finalDict;
}


- (void)setCurrentService:(NSNetService *)clickedService
{
	
	NSDictionary *finalDict = [self stringDictionaryFromService:clickedService];
	NSLog(@"finalDict: %@", finalDict);
	if ([[finalDict allKeys] count] > 0)
	{
		NSString *model = [finalDict objectForKey:@"model"];
		if ([model isEqualToString:@"AppleTV3,1"])
		{
            NSLog(@"is appletv3! nice try");
            return;
        }
   
    } else {
		return;
	}
	
    ntvNetService *service = [[ntvNetService alloc] initWithNetService:clickedService];
    service.serviceDictionary = finalDict;
    /*
    
	struct sockaddr_in *addr = (struct sockaddr_in *) [[[clickedService addresses] objectAtIndex:0]
								   bytes];
    NSString *ip = [NSString stringWithUTF8String:(char *) inet_ntoa(addr->sin_addr)];
	NSString *fullIP = [NSString stringWithFormat:@"%@:%i", ip, 22];
    NSLog(@"full IP: %@", fullIP);
    NSString *headerTitle = [NSString stringWithFormat:@"%@ (%@)", [clickedService name], fullIP];
    NSMutableDictionary *dict = [NSMutableDictionary new];
    dict[@"fullIP"] = fullIP;
    dict[@"IP"] = ip;
    dict[@"name"] = [clickedService name];
    dict[@"headerTitle"] = headerTitle;
    */
    if (self.deviceSelectedBlock){
        
        self.deviceSelectedBlock(service);
        
    }
    
    
//    BOOL jailbroken = [self isJailbroken];
//	if (jailbroken == FALSE)
//	{
//        [self showNotJailbrokenWarning];
//		[DEFAULTS removeObjectForKey:ATV_HOST];
//        [DEFAULTS removeObjectForKey:ATV_HOST_NAME];
//		[DEFAULTS removeObjectForKey:@"selectedValue"];
//        [self resetServerSettings];
//	}
    
}





- (void)updateUI {
    //NSLog(@"%@ %s", self, _cmd);
    if(searching) {

    } else {
		NSLog(@"services: %@", services);
        // Update the user interface to indicate not searching
    }
}

- (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)browser{
	//NSLog(@"%@ %s", self, _cmd);
    searching = NO;
    [self updateUI];
}



- (void)netServiceBrowserWillSearch:(NSNetServiceBrowser *)browser {
    
	//NSLog(@"%@ %s", self, _cmd);
    searching = YES;
    [self updateUI];
}

// Error handling code

- (void)handleError:(NSNumber *)error

{
	
    NSLog(@"An error occurred. Error code = %d", [error intValue]);
	
    // Handle error here
	
}


- (BOOL)searching {
    return searching;
}


- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didNotSearch:(NSDictionary *)errorDict
{
    //  LOG_SELF;
    // NSLog(@"errorDict: %@", errorDict);
    // [browser searchForServicesOfType:@"_airplay._tcp." inDomain:@""];
}

// This object is the delegate of its NSNetServiceBrowser object. We're only interested in services-related methods, so that's what we'll call.
- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didFindService:(NSNetService *)aNetService moreComing:(BOOL)moreComing {
	//NSLog(@"didFindService: %@", aNetService);
    
    [services addObject:aNetService];
	//int servicesCount = [services count]-1;
	
	//[services insertObject:aNetService atIndex:servicesCount];
    
    [aNetService resolveWithTimeout:0.0];
	
    if(!moreComing) {
        
        //set the content of the picker view from here
        //	[deviceController setContent:services];
       
        [[self tableView] reloadData];
        
    }
}



- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didRemoveService:(NSNetService *)aNetService moreComing:(BOOL)moreComing {
    [services removeObject:aNetService];
    
    if(!moreComing) {
        
	}
}

//resolution stuff


- (BOOL)addressesComplete:(NSArray *)addresses

		   forServiceType:(NSString *)serviceType

{
	//NSLog(@"%@ %s", self, _cmd);
    // Perform appropriate logic to ensure that [netService addresses]
	
    // contains the appropriate information to connect to the service
	
    return YES;
	
}

- (void)netServiceWillResolve:(NSNetService *)sender;
{
	NSLog(@"netServiceWillResolve: %@", sender);
}

// Sent when addresses are resolved

- (void)netServiceDidResolveAddress:(NSNetService *)netService {
    NSLog(@"netService: %@",netService);
	
    if ([self addressesComplete:[netService addresses]
				 forServiceType:[netService type]]) {
        NSLog(@"netService: %@",netService);
    }
}



// Sent if resolution fails

- (void)netService:(NSNetService *)netService
	 didNotResolve:(NSDictionary *)errorDict {
    
	NSLog(@"%@ %p", self, _cmd);
    [self handleError:[errorDict objectForKey:NSNetServicesErrorCode]];
    [services removeObject:netService];
}



- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{

    // Return the number of sections.
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{

    // Return the number of rows in the section.
    return [services count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    NSString *currentService = [[services objectAtIndex:indexPath.row] name];
    
    
    cell.textLabel.text = currentService;
    // Configure the cell...
    
    return cell;
}





#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSNetService *currentService = [services objectAtIndex:indexPath.row];
    [self setCurrentService:currentService];

}

@end
