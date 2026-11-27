//
//  KYASleepDisabler.h
//  KYASleepWakeTimer
//

#import <Foundation/Foundation.h>
#import <KYACommon/KYAExport.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted on the main thread after the authorization is installed or removed;
/// removing it also re-enables system sleep.
KYA_EXPORT const NSNotificationName KYASleepDisablerAuthorizationDidChangeNotification;

/// Switches the system-wide `pmset disablesleep` setting, which keeps a
/// portable Mac awake with its lid closed.
///
/// Changing the setting needs root. A one-time authorization installs a
/// sudoers rule that allows exactly `pmset -a disablesleep 0` and
/// `pmset -a disablesleep 1` for the current user without a password.
///
/// The authorization methods return NO with a nil error when the user
/// cancels the password prompt.
@interface KYASleepDisabler : NSObject

/// YES if the current user's sudoers rule is installed.
@property (class, nonatomic, readonly, getter=isAuthorized) BOOL authorized;

/// Installs the sudoers rule. macOS asks for an administrator password.
/// Must be called on the main thread.
///
/// Posts KYASleepDisablerAuthorizationDidChangeNotification on success.
+ (BOOL)authorizeWithError:(NSError **)error;

/// Removes the sudoers rule and re-enables system sleep. macOS asks for an
/// administrator password. Must be called on the main thread.
///
/// Posts KYASleepDisablerAuthorizationDidChangeNotification on success.
+ (BOOL)revokeAuthorizationWithError:(NSError **)error;

/// Re-enables system sleep if an earlier run left it disabled, e.g. after
/// a power loss.
+ (void)restoreSleepLeftDisabledByEarlierRun;

/// YES while this instance keeps system sleep disabled.
@property (nonatomic, readonly, getter=isSleepDisabled) BOOL sleepDisabled;

/// Disables system sleep until -restoreSleep is called or the current
/// process exits, whichever comes first.
- (BOOL)disableSleepWithError:(NSError **)error;

/// Re-enables system sleep if this instance disabled it. When the sudoers rule
/// no longer works, asks for an administrator password if on the main thread.
- (void)restoreSleep;

@end

NS_ASSUME_NONNULL_END
