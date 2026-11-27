//
//  KYAForcedAlertSound.h
//  KYAUserNotifications
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// An alert sound that is heard even when the output is muted or turned
/// down: playing it on the built-in speakers unmutes them and raises their
/// volume to a minimum, then restores both when the sound finishes.
/// Other outputs, such as headphones, play it at their current volume.
@interface KYAForcedAlertSound : NSObject

- (instancetype)init NS_UNAVAILABLE;

/// @param soundName A system sound name, e.g. @"Sosumi"
/// @param minimumVolume The output volume the sound plays at, at least, from 0 to 1
- (instancetype)initWithSoundNamed:(NSSoundName)soundName minimumVolume:(float)minimumVolume NS_DESIGNATED_INITIALIZER;

/// Plays the sound; does nothing while it is already playing.
- (void)play;

@end

NS_ASSUME_NONNULL_END
