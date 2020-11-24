//
//  ntvNetService.h
//  nitoUtility
//
//  Created by Kevin Bradley on 9/16/19.
//  Copyright © 2019 nito. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <sys/types.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>

@interface NSNetService (scienceBro)

- (NSString *)easyIP;

@end

@interface ntvNetService : NSObject

@property (nonatomic, strong) NSString *ipAddress;
@property (nonatomic, strong) NSString *fullIP;
@property (nonatomic, strong) NSString *serviceName;
@property (nonatomic, strong) NSString *title;
@property (nonatomic, strong) NSDictionary *serviceDictionary;
@property (readwrite, assign) NSInteger port;


- (id)initWithNetService:(NSNetService *)service;
- (void)updatePort:(NSInteger)port;

@end

