//
//  KYALidMonitor.m
//  KYADeviceInfo
//

#import "KYALidMonitor+Private.h"
#import <IOKit/IOKitLib.h>
#import <IOKit/pwr_mgt/IOPM.h>
#import <KYACommon/KYACommon.h>

@interface KYALidMonitor ()
@property (nonatomic, nullable) IONotificationPortRef notificationPort;
@property (nonatomic) io_object_t interestNotification;
@end

// Reads the AppleClamshellState property of the power management root domain;
// nil on Macs without a lid.
static NSNumber *_Nullable KYAReadClamshellState(void)
{
    io_service_t rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"));
    if(rootDomain == IO_OBJECT_NULL)
    {
        return nil;
    }
    CFTypeRef state = IORegistryEntryCreateCFProperty(rootDomain, CFSTR(kAppleClamshellStateKey), kCFAllocatorDefault, 0);
    IOObjectRelease(rootDomain);
    return CFBridgingRelease(state);
}

static void KYALidMonitorInterestCallback(void *refcon, io_service_t service, uint32_t messageType, void *messageArgument)
{
    if(messageType != kIOPMMessageClamshellStateChange)
    {
        return;
    }

    Auto monitor = (__bridge KYALidMonitor *)refcon;
    BOOL closed = ((uintptr_t)messageArgument & kClamshellStateBit) != 0;
    Auto handler = monitor.lidChangeHandler;
    if(handler != nil)
    {
        handler(closed);
    }
}

@implementation KYALidMonitor

- (void)dealloc
{
    [self unregisterFromLidChanges];
}

- (BOOL)hasLid
{
    return KYAReadClamshellState() != nil;
}

- (BOOL)isLidClosed
{
    return [KYAReadClamshellState() boolValue];
}

#pragma mark - Lid Changes

- (void)registerForLidChanges
{
    if([self isRegistered]) { return; }

    io_service_t rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"));
    if(rootDomain == IO_OBJECT_NULL) { return; }

    // The callback runs on the main queue.
    IONotificationPortRef port = IONotificationPortCreate(kIOMainPortDefault);
    if(port == NULL)
    {
        IOObjectRelease(rootDomain);
        return;
    }
    IONotificationPortSetDispatchQueue(port, dispatch_get_main_queue());

    io_object_t notification = IO_OBJECT_NULL;
    kern_return_t result = IOServiceAddInterestNotification(port,
                                                            rootDomain,
                                                            kIOGeneralInterest,
                                                            KYALidMonitorInterestCallback,
                                                            (__bridge void *)self,
                                                            &notification);
    IOObjectRelease(rootDomain);
    if(result != KERN_SUCCESS)
    {
        IONotificationPortDestroy(port);
        return;
    }

    self.notificationPort = port;
    self.interestNotification = notification;
    self.registered = YES;
}

- (void)unregisterFromLidChanges
{
    if([self isRegistered] == NO) { return; }

    IOObjectRelease(self.interestNotification);
    self.interestNotification = IO_OBJECT_NULL;
    IONotificationPortDestroy(self.notificationPort);
    self.notificationPort = NULL;
    self.registered = NO;
}

@end
