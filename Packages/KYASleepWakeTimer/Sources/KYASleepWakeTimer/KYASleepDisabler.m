//
//  KYASleepDisabler.m
//  KYASleepWakeTimer
//

#import <KYASleepWakeTimer/KYASleepDisabler.h>
#import <KYACommon/KYACommon.h>

// Set while system sleep is disabled, so that a later run can restore it.
static NSString * const KYASleepLeftDisabledKey = @"KYASleepDisablerSleepLeftDisabled";

static NSString * const KYASleepDisablerErrorDomain = @"KYASleepDisablerErrorDomain";

typedef NS_ENUM(NSInteger, KYASleepDisablerErrorCode)
{
    KYASleepDisablerErrorCodeDisableFailed = 1,
    KYASleepDisablerErrorCodeWatcherFailed = 2,
};

// The AppleScript error number of a cancelled password prompt.
static NSInteger const KYAAppleScriptUserCancelledError = -128;

const NSNotificationName KYASleepDisablerAuthorizationDidChangeNotification = @"KYASleepDisablerAuthorizationDidChangeNotification";

// One rule file per user, keyed by uid, so that two administrators do not
// replace each other's rule and any user name works.
static NSString *KYASudoersRulePath(void)
{
    return [NSString stringWithFormat:@"/etc/sudoers.d/macaffeinate-%u", getuid()];
}

// Runs `sudo -n pmset -a disablesleep 0|1` through the sudoers rule.
//
// Waits on a semaphore rather than -waitUntilExit, which runs the current
// run loop and would let queued main-thread work change the timer meanwhile.
static BOOL KYASetSystemSleepDisabled(BOOL disabled)
{
    Auto task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/sudo"];
    task.arguments = @[@"-n", @"/usr/bin/pmset", @"-a", @"disablesleep", disabled ? @"1" : @"0"];
    task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;

    dispatch_semaphore_t exited = dispatch_semaphore_create(0);
    task.terminationHandler = ^(NSTask *exitedTask) {
        dispatch_semaphore_signal(exited);
    };
    if([task launchAndReturnError:nil] == NO)
    {
        return NO;
    }
    if(dispatch_semaphore_wait(exited, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) != 0)
    {
        [task terminate];
        return NO;
    }
    return task.terminationStatus == 0;
}

// Runs a one-line shell script as root; macOS asks for an administrator password.
// Returns NO with a nil error when the user cancels the prompt.
static BOOL KYARunAsAdministrator(NSString *script, NSError **error)
{
    NSCParameterAssert(NSThread.isMainThread);

    Auto escapedScript = [[script stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
                          stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    Auto source = [NSString stringWithFormat:@"do shell script \"%@\" with administrator privileges", escapedScript];

    NSDictionary<NSString *, id> *errorInfo = nil;
    [[[NSAppleScript alloc] initWithSource:source] executeAndReturnError:&errorInfo];
    if(errorInfo == nil)
    {
        return YES;
    }

    if(error != NULL)
    {
        NSInteger code = [errorInfo[NSAppleScriptErrorNumber] integerValue];
        if(code == KYAAppleScriptUserCancelledError)
        {
            *error = nil;
        }
        else
        {
            NSString *message = errorInfo[NSAppleScriptErrorMessage] ?: @"The administrator script failed.";
            *error = [NSError errorWithDomain:KYASleepDisablerErrorDomain
                                         code:code
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
    }
    return NO;
}

static void KYAPostAuthorizationDidChange(void)
{
    [NSNotificationCenter.defaultCenter postNotificationName:KYASleepDisablerAuthorizationDidChangeNotification
                                                      object:nil];
}

@interface KYASleepDisabler ()
@property (nonatomic, readwrite, getter=isSleepDisabled) BOOL sleepDisabled;
@property (nonatomic, nullable) NSTask *watcherTask;
@property (nonatomic) os_log_t log;
@end

@implementation KYASleepDisabler

- (instancetype)init
{
    self = [super init];
    if(self)
    {
        self.log = KYALogCreateWithCategory("SleepDisabler");
    }
    return self;
}

- (void)dealloc
{
    [self restoreSleep];
}

#pragma mark - Authorization

+ (BOOL)isAuthorized
{
    return [NSFileManager.defaultManager fileExistsAtPath:KYASudoersRulePath()];
}

+ (BOOL)authorizeWithError:(NSError **)error
{
    Auto rule = [NSString stringWithFormat:
                 @"#%u ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1",
                 getuid()];
    // A sudoers file with a syntax error breaks sudo for every user, so the
    // rule is checked in a temporary file before it is moved into place.
    Auto script = [NSString stringWithFormat:
                   @"tmp=$(/usr/bin/mktemp /private/tmp/macaffeinate.XXXXXX) && "
                   @"/bin/echo '%@' > \"$tmp\" && "
                   @"if /usr/sbin/visudo -cqf \"$tmp\"; then "
                   @"/usr/sbin/chown root:wheel \"$tmp\" && /bin/chmod 0440 \"$tmp\" && /bin/mv -f \"$tmp\" %@; "
                   @"else /bin/rm -f \"$tmp\"; exit 1; fi",
                   rule, KYASudoersRulePath()];
    if(KYARunAsAdministrator(script, error) == NO)
    {
        return NO;
    }
    KYAPostAuthorizationDidChange();
    return YES;
}

+ (BOOL)revokeAuthorizationWithError:(NSError **)error
{
    Auto script = [NSString stringWithFormat:@"/bin/rm -f %@ && /usr/bin/pmset -a disablesleep 0",
                   KYASudoersRulePath()];
    if(KYARunAsAdministrator(script, error) == NO)
    {
        return NO;
    }
    [NSUserDefaults.standardUserDefaults removeObjectForKey:KYASleepLeftDisabledKey];
    KYAPostAuthorizationDidChange();
    return YES;
}

+ (void)restoreSleepLeftDisabledByEarlierRun
{
    Auto defaults = NSUserDefaults.standardUserDefaults;
    if([defaults boolForKey:KYASleepLeftDisabledKey] == NO)
    {
        return;
    }
    if(KYASetSystemSleepDisabled(NO))
    {
        [defaults removeObjectForKey:KYASleepLeftDisabledKey];
    }
}

#pragma mark - Disabling Sleep

- (BOOL)disableSleepWithError:(NSError **)error
{
    @synchronized(self)
    {
        if([self isSleepDisabled])
        {
            return YES;
        }

        // The marker goes first, so that a power loss right after pmset is covered.
        Auto defaults = NSUserDefaults.standardUserDefaults;
        [defaults setBool:YES forKey:KYASleepLeftDisabledKey];
        [defaults synchronize];
        if(KYASetSystemSleepDisabled(YES) == NO)
        {
            [defaults removeObjectForKey:KYASleepLeftDisabledKey];
            if(error != NULL)
            {
                *error = [NSError errorWithDomain:KYASleepDisablerErrorDomain
                                             code:KYASleepDisablerErrorCodeDisableFailed
                                         userInfo:@{NSLocalizedDescriptionKey: @"pmset -a disablesleep 1 failed."}];
            }
            return NO;
        }
        self.sleepDisabled = YES;

        // Without the watcher a crash would leave sleep disabled until the next launch.
        self.watcherTask = [self launchWatcherTask];
        if(self.watcherTask == nil)
        {
            [self restoreSleep];
            if(error != NULL)
            {
                *error = [NSError errorWithDomain:KYASleepDisablerErrorDomain
                                             code:KYASleepDisablerErrorCodeWatcherFailed
                                         userInfo:@{NSLocalizedDescriptionKey: @"The sleep watcher could not be launched."}];
            }
            return NO;
        }

        os_log(self.log, "System sleep disabled.");
        return YES;
    }
}

- (void)restoreSleep
{
    @synchronized(self)
    {
        if([self isSleepDisabled] == NO)
        {
            return;
        }

        // Fails only when the rule stopped working, e.g. removed by hand. The marker
        // stays then, so the next launch tries again.
        if(KYASetSystemSleepDisabled(NO))
        {
            [NSUserDefaults.standardUserDefaults removeObjectForKey:KYASleepLeftDisabledKey];
            os_log(self.log, "System sleep restored.");
        }
        else
        {
            os_log_error(self.log, "Failed to restore system sleep.");
        }
        [self.watcherTask terminate];
        self.watcherTask = nil;
        self.sleepDisabled = NO;
    }
}

// Restores system sleep once this process exits, even when it crashes
// or is force quit, the way `caffeinate -w` follows a process.
- (nullable NSTask *)launchWatcherTask
{
    NSString *script = @"while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 1; done; "
                       @"exec /usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0";
    Auto task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
    task.arguments = @[
        @"-c",
        script,
        @"sh",
        @(NSProcessInfo.processInfo.processIdentifier).stringValue,
    ];

    NSError *error = nil;
    if([task launchAndReturnError:&error] == NO)
    {
        os_log_error(self.log, "Failed to launch the sleep watcher: %{public}@", error);
        return nil;
    }
    return task;
}

@end
