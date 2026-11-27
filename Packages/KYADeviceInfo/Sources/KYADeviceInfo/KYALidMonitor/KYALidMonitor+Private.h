//
//  KYALidMonitor+Private.h
//  KYADeviceInfo
//

#import <Foundation/Foundation.h>
#import <KYADeviceInfo/KYALidMonitor.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^KYALidChangeBlock)(BOOL closed);

@interface KYALidMonitor ()
@property (nonatomic, getter=isRegistered) BOOL registered;

/// An optional block that is called on the main queue when the lid opens
/// or closes and -registerForLidChanges was called.
@property (copy, nonatomic, nullable) KYALidChangeBlock lidChangeHandler;

/// Registers for lid changes; the `lidChangeHandler` is called on each change.
- (void)registerForLidChanges;

/// Unregisters from lid changes.
- (void)unregisterFromLidChanges;

@end

NS_ASSUME_NONNULL_END
