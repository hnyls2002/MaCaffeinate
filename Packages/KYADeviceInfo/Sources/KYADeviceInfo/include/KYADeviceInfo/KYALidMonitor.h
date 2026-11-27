//
//  KYALidMonitor.h
//  KYADeviceInfo
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KYALidMonitor : NSObject

/// NO on Macs without a built-in display lid.
@property (nonatomic, readonly) BOOL hasLid;

@property (nonatomic, readonly, getter=isLidClosed) BOOL lidClosed;

@end

NS_ASSUME_NONNULL_END
