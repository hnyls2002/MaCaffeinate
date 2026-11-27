//
//  KYAForcedAlertSound.m
//  KYAUserNotifications
//

#import <KYAUserNotifications/KYAForcedAlertSound.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudio.h>
#import <KYACommon/KYACommon.h>

static AudioObjectID KYADefaultOutputDevice(void)
{
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    AudioObjectID device = kAudioObjectUnknown;
    UInt32 size = sizeof(device);
    if(AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, &device) != noErr)
    {
        return kAudioObjectUnknown;
    }
    return device;
}

// Reads or writes a fixed-size output property of an audio device;
// returns NO when the device does not have the property.
static BOOL KYAGetOutputProperty(AudioObjectID device, AudioObjectPropertySelector selector, void *value, UInt32 size)
{
    AudioObjectPropertyAddress address = { selector, kAudioDevicePropertyScopeOutput, kAudioObjectPropertyElementMain };
    if(AudioObjectHasProperty(device, &address) == false)
    {
        return NO;
    }
    return AudioObjectGetPropertyData(device, &address, 0, NULL, &size, value) == noErr;
}

static void KYASetOutputProperty(AudioObjectID device, AudioObjectPropertySelector selector, const void *value, UInt32 size)
{
    AudioObjectPropertyAddress address = { selector, kAudioDevicePropertyScopeOutput, kAudioObjectPropertyElementMain };
    AudioObjectSetPropertyData(device, &address, 0, NULL, size, value);
}

// The data source of the built-in output when it plays through the speakers.
static UInt32 const KYABuiltInSpeakerDataSource = 'ispk';

// YES for the built-in speakers. Headphones keep their volume, since a sudden
// loud sound there could hurt, and so does any output that cannot be told apart.
static BOOL KYAIsBuiltInSpeaker(AudioObjectID device)
{
    UInt32 transportType = 0;
    if(KYAGetOutputProperty(device, kAudioDevicePropertyTransportType, &transportType, sizeof(transportType)) == NO
       || transportType != kAudioDeviceTransportTypeBuiltIn)
    {
        return NO;
    }
    // The built-in output switches between the speakers and the headphone jack.
    UInt32 dataSource = 0;
    return KYAGetOutputProperty(device, kAudioDevicePropertyDataSource, &dataSource, sizeof(dataSource))
        && dataSource == KYABuiltInSpeakerDataSource;
}

@interface KYAForcedAlertSound () <NSSoundDelegate>
@property (nonatomic) NSSound *sound;
@property (nonatomic) float minimumVolume;

// The output device state to restore after playing.
@property (nonatomic) AudioObjectID device;
@property (nonatomic, nullable) NSNumber *originalVolume;
@property (nonatomic, nullable) NSNumber *originalMute;
@end

@implementation KYAForcedAlertSound

- (instancetype)initWithSoundNamed:(NSSoundName)soundName minimumVolume:(float)minimumVolume
{
    NSParameterAssert(soundName);

    self = [super init];
    if(self)
    {
        // A copy, so that the delegate is not set on the shared named sound.
        self.sound = [[NSSound soundNamed:soundName] copy];
        self.sound.delegate = self;
        self.minimumVolume = minimumVolume;

        // Quitting in the middle of the sound must not leave the output forced.
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(applicationWillTerminate:)
                                                   name:NSApplicationWillTerminateNotification
                                                 object:nil];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self restoreOutput];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    [self.sound stop];
    [self restoreOutput];
}

- (void)play
{
    if(self.sound == nil || [self.sound isPlaying])
    {
        return;
    }

    [self forceOutputAudible];
    if([self.sound play] == NO)
    {
        [self restoreOutput];
    }
}

#pragma mark - Output Device

- (void)forceOutputAudible
{
    AudioObjectID device = KYADefaultOutputDevice();
    if(device == kAudioObjectUnknown || KYAIsBuiltInSpeaker(device) == NO)
    {
        return;
    }
    self.device = device;

    UInt32 mute = 0;
    if(KYAGetOutputProperty(device, kAudioDevicePropertyMute, &mute, sizeof(mute)) && mute != 0)
    {
        self.originalMute = @(mute);
        UInt32 unmuted = 0;
        KYASetOutputProperty(device, kAudioDevicePropertyMute, &unmuted, sizeof(unmuted));
    }

    Float32 volume = 0;
    if(KYAGetOutputProperty(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, &volume, sizeof(volume))
       && volume < self.minimumVolume)
    {
        self.originalVolume = @(volume);
        Float32 minimumVolume = self.minimumVolume;
        KYASetOutputProperty(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, &minimumVolume, sizeof(minimumVolume));
    }
}

- (void)restoreOutput
{
    if(self.originalVolume != nil)
    {
        Float32 volume = self.originalVolume.floatValue;
        KYASetOutputProperty(self.device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, &volume, sizeof(volume));
        self.originalVolume = nil;
    }
    if(self.originalMute != nil)
    {
        UInt32 mute = self.originalMute.unsignedIntValue;
        KYASetOutputProperty(self.device, kAudioDevicePropertyMute, &mute, sizeof(mute));
        self.originalMute = nil;
    }
}

#pragma mark - NSSoundDelegate

- (void)sound:(NSSound *)sound didFinishPlaying:(BOOL)flag
{
    [self restoreOutput];
}

@end
