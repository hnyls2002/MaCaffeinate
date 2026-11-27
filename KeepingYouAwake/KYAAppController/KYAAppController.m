//
//  KYAAppController.m
//  KeepingYouAwake
//
//  Created by Marcel Dierkes on 17.10.14.
//  Copyright (c) 2014 Marcel Dierkes. All rights reserved.
//

#import "KYAAppController.h"
#import <KYACommon/KYACommon.h>
#import "KYALocalizedStrings.h"
#import "KYAMainMenu.h"
#import "KYABatteryCapacityThreshold.h"
#import "KYAActivationDurationsMenuController.h"
#import "KYAActivationUserNotification.h"

// Deprecated!
#define KYA_MINUTES(m) (m * 60.0f)
#define KYA_HOURS(h) (h * 3600.0f)

@interface KYAAppController () <KYAStatusItemControllerDataSource, KYAStatusItemControllerDelegate, KYAActivationDurationsMenuControllerDelegate, KYASleepWakeTimerDelegate>
@property (nonatomic, readwrite) KYASleepWakeTimer *sleepWakeTimer;
@property (nonatomic, readwrite) KYAStatusItemController *statusItemController;
@property (nonatomic) KYAActivationDurationsMenuController *menuController;

@property (nonatomic) NSTimeInterval workspaceScheduledTimeInterval;

// Beeps when the lid closes while the Mac is kept awake with its lid closed.
@property (nonatomic) KYAForcedAlertSound *lidCloseAlarm;

// Battery Status
@property (nonatomic, direct, getter=isBatteryOverrideEnabled) BOOL batteryOverrideEnabled;

// Menu
@property (nonatomic) NSMenu *menu;
@end

@implementation KYAAppController

#pragma mark - Life Cycle

- (instancetype)init
{
    self = [super init];
    if(self)
    {
        [NSUserDefaults.standardUserDefaults registerDefaults:@{
            KYAUserDefaultsKeyLidCloseAlarmEnabled: @YES,
        }];
        self.lidCloseAlarm = [[KYAForcedAlertSound alloc] initWithSoundNamed:@"Sosumi" minimumVolume:0.75f];

        [self configureStatusItemController];
        [self configureSleepWakeTimer];
        [self configureEventHandler];
        [self configureUserNotificationCenter];
        [self configureMainMenu];

        Auto center = NSNotificationCenter.defaultCenter;
        [center addObserver:self
                   selector:@selector(applicationWillFinishLaunching:)
                       name:NSApplicationWillFinishLaunchingNotification
                     object:nil];
        [center addObserver:self
                   selector:@selector(applicationDidChangeScreenParameters:)
                       name:NSApplicationDidChangeScreenParametersNotification
                     object:nil];
        [center addObserver:self
                   selector:@selector(batteryCapacityThresholdDidChange:)
                       name:kKYABatteryCapacityThresholdDidChangeNotification
                     object:nil];
        [center addObserver:self
                   selector:@selector(sleepDisablerAuthorizationDidChange:)
                       name:KYASleepDisablerAuthorizationDidChangeNotification
                     object:nil];
        
        [self registerForWorkspaceSessionNotifications];
    }
    return self;
}

- (void)dealloc
{
    Auto center = NSNotificationCenter.defaultCenter;
    [center removeObserver:self name:NSApplicationDidFinishLaunchingNotification object:nil];
    [center removeObserver:self name:NSApplicationDidChangeScreenParametersNotification object:nil];
    [center removeObserver:self name:kKYABatteryCapacityThresholdDidChangeNotification object:nil];
    [center removeObserver:self name:KYASleepDisablerAuthorizationDidChangeNotification object:nil];
    
    [self unregisterFromWorkspaceSessionNotifications];
}

#pragma mark - Main Menu

- (void)configureMainMenu
{
    Auto menuController = [KYAActivationDurationsMenuController new];
    menuController.delegate = self;
    self.menuController = menuController;
    
    self.menu = KYACreateMainMenuWithActivationDurationsSubMenu(menuController.menu);
}

#pragma mark - Status Item Controller

- (void)configureStatusItemController
{
    Auto statusItemController = [KYAStatusItemController new];
    statusItemController.dataSource = self;
    statusItemController.delegate = self;
    self.statusItemController = statusItemController;
}

#pragma mark - Sleep Wake Timer

- (void)configureSleepWakeTimer
{
    // A crash or power loss can leave the closed lid mode on.
    [KYASleepDisabler restoreSleepLeftDisabledByEarlierRun];

    Auto sleepWakeTimer = [KYASleepWakeTimer new];
    sleepWakeTimer.delegate = self;
    self.sleepWakeTimer = sleepWakeTimer;
    
    // Activate on launch if needed
    if([NSUserDefaults.standardUserDefaults kya_isActivatedOnLaunch])
    {
        [self activateTimer];
    }
}

- (void)activateTimer
{
    [self activateTimerWithTimeInterval:self.defaultTimeInterval];
}

- (void)activateTimerWithTimeInterval:(NSTimeInterval)timeInterval
{
    // Do not allow negative time intervals
    if(timeInterval < 0)
    {
        return;
    }

    Auto defaults = NSUserDefaults.standardUserDefaults;
    
    Auto timerCompletion = ^(BOOL cancelled) {
        // Post deactivation notification
        Auto notification = [[KYAActivationUserNotification alloc] initWithFireDate:nil activating:NO];
        [KYAUserNotificationCenter.sharedCenter postNotification:notification];

        // Quit on timer expiration
        if(cancelled == NO && [defaults kya_isQuitOnTimerExpirationEnabled])
        {
            [NSApplication.sharedApplication terminate:nil];
        }
    };
    [self.sleepWakeTimer scheduleWithTimeInterval:timeInterval completion:timerCompletion];

    // Post activation notification
    Auto fireDate = self.sleepWakeTimer.fireDate;
    Auto notification = [[KYAActivationUserNotification alloc] initWithFireDate:fireDate activating:YES];
    [KYAUserNotificationCenter.sharedCenter postNotification:notification];
}

- (void)terminateTimer
{
    [self disableBatteryOverride];

    if([self.sleepWakeTimer isScheduled])
    {
        [self.sleepWakeTimer invalidate];
    }
}

#pragma mark - Closed Lid

// A Mac without a lid has nothing to keep awake while closed. A user who
// declined the authorization turns the mode on in the advanced settings.
- (BOOL)isClosedLidAvailable
{
    if([KYADevice.currentDevice.lidMonitor hasLid] == NO)
    {
        return NO;
    }
    return [KYASleepDisabler isAuthorized] || [NSUserDefaults.standardUserDefaults kya_isClosedLidPromptDeclined] == NO;
}

// Keeps the Mac awake with its lid closed while the timer runs,
// asking for the one-time authorization first if needed.
- (BOOL)enableClosedLid
{
    if([KYASleepDisabler isAuthorized] == NO && [self requestClosedLidAuthorization] == NO)
    {
        return NO;
    }
    
    // The timer may have stopped during the prompts; then nothing is reported.
    NSError *error = nil;
    if([self.sleepWakeTimer enableClosedLidWithError:&error] == NO)
    {
        [self presentClosedLidError:error];
        return NO;
    }
    self.statusItemController.appearance = KYAStatusItemAppearanceActiveClosedLid;
    return YES;
}

- (BOOL)requestClosedLidAuthorization
{
    Auto alert = [NSAlert new];
    alert.messageText = KYA_L10N_CLOSED_LID_AUTHORIZATION_TITLE;
    alert.informativeText = KYA_L10N_CLOSED_LID_AUTHORIZATION_MESSAGE;
    [alert addButtonWithTitle:KYA_L10N_CONTINUE];
    [alert addButtonWithTitle:KYA_L10N_CANCEL];
    [self activateApplication];
    if([alert runModal] != NSAlertFirstButtonReturn)
    {
        [self declineClosedLid];
        return NO;
    }
    
    NSError *error = nil;
    if([KYASleepDisabler authorizeWithError:&error] == NO)
    {
        if(error == nil) // The password prompt was cancelled
        {
            [self declineClosedLid];
        }
        [self presentClosedLidError:error];
        return NO;
    }
    return YES;
}

// Clicks skip the closed lid step from now on, until the user authorizes it in the settings.
- (void)declineClosedLid
{
    NSUserDefaults.standardUserDefaults.kya_closedLidPromptDeclined = YES;
    self.statusItemController.closedLidAvailable = [self isClosedLidAvailable];
}

// A nil error means there is nothing to report, e.g. a cancelled prompt.
- (void)presentClosedLidError:(nullable NSError *)error
{
    if(error == nil)
    {
        return;
    }
    
    Auto alert = [NSAlert new];
    alert.messageText = KYA_L10N_CLOSED_LID_FAILED_TITLE;
    alert.informativeText = error.localizedDescription ?: @"";
    [self activateApplication];
    [alert runModal];
}

- (void)activateApplication
{
    if(@available(macOS 14.0, *))
    {
        [NSApplication.sharedApplication activate];
    }
    else
    {
        [NSApplication.sharedApplication activateIgnoringOtherApps:YES];
    }
}

- (void)sleepDisablerAuthorizationDidChange:(NSNotification *)notification
{
    // Removing the authorization opts out; the revocation already restored sleep.
    if([KYASleepDisabler isAuthorized] == NO)
    {
        [self declineClosedLid];
        if([self.sleepWakeTimer isClosedLidEnabled])
        {
            [self.sleepWakeTimer disableClosedLid];
            self.statusItemController.appearance = KYAStatusItemAppearanceActive;
        }
    }
    else
    {
        self.statusItemController.closedLidAvailable = [self isClosedLidAvailable];
    }
}

#pragma mark - Default Time Interval

- (NSTimeInterval)defaultTimeInterval
{
    return NSUserDefaults.standardUserDefaults.kya_defaultTimeInterval;
}

#pragma mark - Activate on Launch

- (IBAction)toggleActivateOnLaunch:(id)sender
{
    Auto defaults = NSUserDefaults.standardUserDefaults;
    defaults.kya_activateOnLaunch = ![defaults kya_isActivatedOnLaunch];
    [defaults synchronize];
}

#pragma mark - User Notification Center

- (void)configureUserNotificationCenter
{
    Auto center = KYAUserNotificationCenter.sharedCenter;
    [center requestAuthorizationIfUndetermined];
    [center clearAllDeliveredNotifications];
}

#pragma mark - Device Power Monitoring

- (void)checkAndEnableBatteryOverride
{
    Auto batteryMonitor = KYADevice.currentDevice.batteryMonitor;
    CGFloat currentCapacity = batteryMonitor.currentCapacity;
    CGFloat threshold = NSUserDefaults.standardUserDefaults.kya_batteryCapacityThreshold;

    self.batteryOverrideEnabled = (currentCapacity <= threshold);
}

- (void)disableBatteryOverride
{
    self.batteryOverrideEnabled = NO;
}

- (void)deviceParameterDidChange:(NSNotification *)notification
{
    NSParameterAssert(notification);
    
    Auto device = (KYADevice *)notification.object;
    Auto defaults = NSUserDefaults.standardUserDefaults;
    
    Auto userInfo = notification.userInfo;
    Auto deviceParameter = (KYADeviceParameter)userInfo[KYADeviceParameterKey];
    if([deviceParameter isEqualToString:KYADeviceParameterBattery])
    {
        if([defaults kya_isBatteryCapacityThresholdEnabled] == NO) { return; }
        
        CGFloat threshold = defaults.kya_batteryCapacityThreshold;
        Auto capacity = device.batteryMonitor.currentCapacity;
        if([self.sleepWakeTimer isScheduled] && (capacity <= threshold) && ![self isBatteryOverrideEnabled])
        {
            [self terminateTimer];
        }
    }
    else if([deviceParameter isEqualToString:KYADeviceParameterLowPowerMode])
    {
        if([defaults kya_isLowPowerModeMonitoringEnabled] == NO) { return; }
        
        if([device.lowPowerModeMonitor isLowPowerModeEnabled] && [self.sleepWakeTimer isScheduled])
        {
            [self terminateTimer];
        }
    }
    else if([deviceParameter isEqualToString:KYADeviceParameterLid])
    {
        if([defaults kya_isLidCloseAlarmEnabled] == NO) { return; }
        
        if([device.lidMonitor isLidClosed] && [self.sleepWakeTimer isClosedLidEnabled])
        {
            [self.lidCloseAlarm play];
        }
    }
}

- (void)enableDevicePowerMonitoring
{
    Auto device = KYADevice.currentDevice;
    Auto center = NSNotificationCenter.defaultCenter;
    Auto defaults = NSUserDefaults.standardUserDefaults;
    
    // Check battery overrides and register for capacity changes.
    [self checkAndEnableBatteryOverride];
    
    [center addObserver:self
               selector:@selector(deviceParameterDidChange:)
                   name:KYADeviceParameterDidChangeNotification
                 object:device];
    
    if([defaults kya_isBatteryCapacityThresholdEnabled])
    {
        device.batteryMonitoringEnabled = YES;
    }
    if([defaults kya_isLowPowerModeMonitoringEnabled])
    {
        device.lowPowerModeMonitoringEnabled = YES;
    }
    device.lidMonitoringEnabled = YES;
}

- (void)disableDevicePowerMonitoring
{
    Auto device = KYADevice.currentDevice;
    Auto center = NSNotificationCenter.defaultCenter;
    
    [center removeObserver:self
                      name:KYADeviceParameterDidChangeNotification
                    object:device];
    
    device.batteryMonitoringEnabled = NO;
    device.lowPowerModeMonitoringEnabled = NO;
    device.lidMonitoringEnabled = NO;
}

#pragma mark - Battery Capacity Threshold Changes

- (void)batteryCapacityThresholdDidChange:(NSNotification *)notification
{
    if([self.sleepWakeTimer isScheduled])
    {
        [self terminateTimer];
    }
}

#pragma mark - Workspace Session Handling

- (void)registerForWorkspaceSessionNotifications
{
    Auto workspaceCenter = NSWorkspace.sharedWorkspace.notificationCenter;
    [workspaceCenter addObserver:self
                        selector:@selector(workspaceSessionDidBecomeActive:)
                            name:NSWorkspaceSessionDidBecomeActiveNotification
                          object:nil];
    [workspaceCenter addObserver:self
                        selector:@selector(workspaceSessionDidResignActive:)
                            name:NSWorkspaceSessionDidResignActiveNotification
                          object:nil];
}

- (void)unregisterFromWorkspaceSessionNotifications
{
    Auto workspaceCenter = NSWorkspace.sharedWorkspace.notificationCenter;
    [workspaceCenter removeObserver:self
                               name:NSWorkspaceSessionDidBecomeActiveNotification
                             object:nil];
    [workspaceCenter removeObserver:self
                               name:NSWorkspaceSessionDidResignActiveNotification
                             object:nil];
}

- (void)workspaceSessionDidBecomeActive:(NSNotification *)notification
{
    Auto defaults = NSUserDefaults.standardUserDefaults;
    if([defaults kya_isDeactivateOnUserSwitchEnabled] && self.workspaceScheduledTimeInterval >= 0)
    {
        [self activateTimerWithTimeInterval:self.workspaceScheduledTimeInterval];
        self.workspaceScheduledTimeInterval = -1;
    }
}

- (void)workspaceSessionDidResignActive:(NSNotification *)notification
{
    Auto defaults = NSUserDefaults.standardUserDefaults;
    if([defaults kya_isDeactivateOnUserSwitchEnabled] && [self.sleepWakeTimer isScheduled])
    {
        self.workspaceScheduledTimeInterval = self.sleepWakeTimer.scheduledTimeInterval;
        [self terminateTimer];
    }
}

#pragma mark - Event Handling

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    [KYAEventHandler.defaultHandler registerAsDefaultEventHandler];
}

- (void)configureEventHandler
{
    Auto eventHandler = KYAEventHandler.defaultHandler;
    
    AutoWeak weakSelf = self;
    [eventHandler registerActionNamed:@"activate" block:^(KYAEvent *event) {
        [weakSelf handleActivateActionForEvent:event];
    }];
    
    [eventHandler registerActionNamed:@"deactivate" block:^(KYAEvent *event) {
        Auto strongSelf = weakSelf;
        [strongSelf terminateTimer];
        strongSelf.statusItemController.appearance = KYAStatusItemAppearanceInactive;
    }];
    
    [eventHandler registerActionNamed:@"toggle" block:^(KYAEvent *event) {
        Auto strongSelf = weakSelf;
        if([strongSelf.sleepWakeTimer isScheduled])
        {
            [strongSelf terminateTimer];
        }
        else
        {
            [strongSelf activateTimer];
        }
    }];
}

- (void)handleActivateActionForEvent:(KYAEvent *)event
{
    Auto parameters = event.arguments;
    NSString *seconds = parameters[@"seconds"];
    NSString *minutes = parameters[@"minutes"];
    NSString *hours = parameters[@"hours"];

    [self terminateTimer];
    
    Auto statusItemController = self.statusItemController;

    // Activate indefinitely if there are no parameters
    if(parameters == nil || parameters.count == 0)
    {
        [self activateTimer];
        statusItemController.appearance = KYAStatusItemAppearanceActive;
    }
    else if(seconds != nil)
    {
        [self activateTimerWithTimeInterval:(NSTimeInterval)ceil(seconds.doubleValue)];
        statusItemController.appearance = KYAStatusItemAppearanceActive;
    }
    else if(minutes != nil)
    {
        [self activateTimerWithTimeInterval:(NSTimeInterval)KYA_MINUTES(ceil(minutes.doubleValue))];
        statusItemController.appearance = KYAStatusItemAppearanceActive;
    }
    else if(hours != nil)
    {
        [self activateTimerWithTimeInterval:(NSTimeInterval)KYA_HOURS(ceil(hours.doubleValue))];
        statusItemController.appearance = KYAStatusItemAppearanceActive;
    }
    else
    {
        statusItemController.appearance = KYAStatusItemAppearanceInactive;
    }
}

#pragma mark - Internal / External Screen Parameter Changes

- (void)applicationDidChangeScreenParameters:(NSNotification *)notification
{
    if([NSUserDefaults.standardUserDefaults kya_isActivateOnExternalDisplayConnectedEnabled] == NO)
    {
        return;
    }
    
    NSUInteger numberOfExternalScreens = KYADisplayParametersGetNumberOfExternalDisplays();
    Auto sleepWakeTimer = self.sleepWakeTimer;
    
    if(numberOfExternalScreens == 0)
    {
        // Only the main screen is connected, deactivate!
        if([sleepWakeTimer isScheduled])
        {
            [self terminateTimer];
        }
    }
    else
    {
        // The main screen and at least one external screen, activate!
        if([sleepWakeTimer isScheduled] == NO)
        {
            [self activateTimer];
        }
    }
}

#pragma mark - KYAStatusItemControllerDataSource

- (NSMenu *)menuForStatusItemController:(KYAStatusItemController *)controller
{
    return self.menu;
}

#pragma mark - KYAStatusItemControllerDelegate

- (void)statusItemControllerShouldPerformPrimaryAction:(KYAStatusItemController *)controller
{
    // Each click moves on: inactive, active, active with the lid closed, inactive.
    // The closed lid step is skipped where it is not available.
    Auto sleepWakeTimer = self.sleepWakeTimer;
    if([sleepWakeTimer isScheduled] == NO)
    {
        [self activateTimer];
        return;
    }
    
    if([sleepWakeTimer isClosedLidEnabled] == NO && [self isClosedLidAvailable])
    {
        if([self enableClosedLid])
        {
            return;
        }
    }
    
    [self terminateTimer];
}

#pragma mark - KYAActivationDurationsMenuControllerDelegate

- (KYAActivationDuration *)currentActivationDuration
{
    Auto sleepWakeTimer = self.sleepWakeTimer;
    if(![sleepWakeTimer isScheduled])
    {
        return nil;
    }

    NSTimeInterval seconds = sleepWakeTimer.scheduledTimeInterval;
    return [[KYAActivationDuration alloc] initWithSeconds:seconds];
}

- (void)activationDurationsMenuController:(KYAActivationDurationsMenuController *)controller didSelectActivationDuration:(KYAActivationDuration *)activationDuration
{
    // A new duration keeps the closed lid mode.
    BOOL closedLidEnabled = [self.sleepWakeTimer isClosedLidEnabled];
    [self terminateTimer];

    AutoWeak weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        Auto strongSelf = weakSelf;
        NSTimeInterval seconds = activationDuration.seconds;
        [strongSelf activateTimerWithTimeInterval:seconds];
        if(closedLidEnabled)
        {
            [strongSelf enableClosedLid];
        }
    });
}

- (NSDate *)fireDateForMenuController:(KYAActivationDurationsMenuController *)controller
{
    return self.sleepWakeTimer.fireDate;
}

#pragma mark - KYASleepWakeTimerDelegate

- (void)sleepWakeTimer:(KYASleepWakeTimer *)sleepWakeTimer willActivateWithTimeInterval:(NSTimeInterval)timeInterval
{
    // Update the status item
    self.statusItemController.closedLidAvailable = [self isClosedLidAvailable];
    self.statusItemController.appearance = KYAStatusItemAppearanceActive;
    
    [self enableDevicePowerMonitoring];
}

- (void)sleepWakeTimerDidDeactivate:(KYASleepWakeTimer *)sleepWakeTimer
{
    // Update the status item
    self.statusItemController.appearance = KYAStatusItemAppearanceInactive;
    
    [self disableDevicePowerMonitoring];
}

@end
