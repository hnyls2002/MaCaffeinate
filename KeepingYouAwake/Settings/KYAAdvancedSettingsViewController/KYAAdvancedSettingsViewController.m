//
//  KYAAdvancedSettingsViewController.m
//  KeepingYouAwake
//
//  Created by Marcel Dierkes on 18.12.15.
//  Copyright © 2015 Marcel Dierkes. All rights reserved.
//

#import "KYAAdvancedSettingsViewController.h"
#import <KYACommon/KYACommon.h>
#import "KYALocalizedStrings.h"
#import "KYAUserDefaultsSetting.h"
#import "KYABatteryCapacityThreshold.h"
#import <KYASleepWakeTimer/KYASleepWakeTimer.h>
#import <KYADeviceInfo/KYADeviceInfo.h>

/// Installs or removes the authorization to keep the Mac awake with its lid closed.
@interface KYAClosedLidAuthorizationSetting : NSObject <KYASetting>
@end

@implementation KYAClosedLidAuthorizationSetting

- (NSString *)title
{
    return KYA_L10N_ALLOW_CLOSED_LID;
}

- (BOOL)value
{
    return [KYASleepDisabler isAuthorized];
}

- (void)setValue:(BOOL)value
{
    [self willChangeValueForKey:@"value"];
    NSError *error = nil;
    BOOL success = value ? [KYASleepDisabler authorizeWithError:&error] : [KYASleepDisabler revokeAuthorizationWithError:&error];
    if(success == NO && error != nil) // No error when the password prompt was cancelled
    {
        [[NSAlert alertWithError:error] runModal];
    }
    [self didChangeValueForKey:@"value"];
}

- (void)reset
{
    // Removing the authorization needs an administrator password, so a reset keeps it.
}

@end

@interface KYAAdvancedSettingsViewController ()
@property (nonatomic) NSArray<id<KYASetting>> *settings;
@property (nonatomic, readwrite) BOOL batteryStatusAvailable;
@property (weak, nonatomic) IBOutlet NSUserDefaultsController *defaultsController;
@end

@implementation KYAAdvancedSettingsViewController

+ (NSImage *)tabViewItemImage
{
    return [NSImage imageWithSystemSymbolName:@"gearshape.2" accessibilityDescription:nil];
}

+ (NSString *)preferredTitle
{
    return KYA_SETTINGS_L10N_ADVANCED;
}

- (BOOL)resizesView
{
    return NO;
}

#pragma mark -

- (void)viewDidLoad
{
    [super viewDidLoad];

    [self configureAdvancedSettings];
}

#pragma mark - Configuration

- (void)configureAdvancedSettings
{
    Auto settings = [NSMutableArray<id<KYASetting>> new];
    
    [settings addObject:[[KYAUserDefaultsSetting alloc] initWithTitle:KYA_L10N_QUIT_ON_TIMER_EXPIRATION key:KYAUserDefaultsKeyIsQuitOnTimerExpirationEnabled]];
    [settings addObject:[[KYAUserDefaultsSetting alloc] initWithTitle:KYA_L10N_ALLOW_DISPLAY_SLEEP key:KYAUserDefaultsKeyAllowDisplaySleep]];
    [settings addObject:[[KYAUserDefaultsSetting alloc] initWithTitle:KYA_L10N_ACTIVATE_ON_EXTERNAL_DISPLAY key:KYAUserDefaultsKeyActivateOnExternalDisplayConnectedEnabled]];
    [settings addObject:[[KYAUserDefaultsSetting alloc] initWithTitle:KYA_L10N_DEACTIVATE_ON_USER_SWITCH key:KYAUserDefaultsKeyDeactivateOnUserSwitchEnabled]];
    if([KYADevice.currentDevice.lidMonitor hasLid])
    {
        [settings addObject:[KYAClosedLidAuthorizationSetting new]];
        [settings addObject:[[KYAUserDefaultsSetting alloc] initWithTitle:KYA_L10N_LID_CLOSE_ALARM key:KYAUserDefaultsKeyLidCloseAlarmEnabled]];
    }
    
    self.settings = [settings copy];
}

#pragma mark - Reset Advanced Settings

- (IBAction)resetAdvancedSettings:(id)sender
{
    for(id<KYASetting> setting in self.settings)
    {
        [setting reset];
    }
    [NSUserDefaults.standardUserDefaults synchronize];
    [self.tableView reloadData];
}

#pragma mark - Table View Delegate & Data Source

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)self.settings.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    return self.settings[(NSUInteger)row];
}

@end
