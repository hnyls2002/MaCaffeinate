# MaCaffeinate

MaCaffeinate is a menu bar app for macOS 12 and newer that keeps your Mac awake, for a set duration or until you turn it off. On a MacBook it can also keep the Mac awake with the lid closed.

## Install

1. Download `MaCaffeinate.zip` from the [latest release](https://github.com/hnyls2002/MaCaffeinate/releases/latest), unzip it, and move `MaCaffeinate.app` to Applications.
2. The app is not notarized, so macOS blocks its first launch. Open System Settings > Privacy & Security and click Open Anyway, or run:

   ```bash
   xattr -dr com.apple.quarantine /Applications/MaCaffeinate.app
   ```

## Usage

Click the cup in the menu bar to step through three states:

1. **Off**: the Mac sleeps as usual.
2. **Awake**: the Mac stays awake while the lid is open.
3. **Awake with the lid closed**: the Mac also stays awake when you close the lid. A bolt appears next to the cup.

The next click turns it off. A Mac without a lid has only the first two states.

Right-click the cup for the menu: activate for a set duration, open Settings, or quit.

## Closed-lid mode

A MacBook goes to sleep when its lid closes, even while `caffeinate` holds it awake. Closed-lid mode runs `pmset -a disablesleep 1` to turn that sleep off, and `pmset -a disablesleep 0` to turn it back on.

### Permission

`pmset` needs administrator rights. The first time you switch to closed-lid mode, MaCaffeinate asks for your administrator password once and installs `/etc/sudoers.d/macaffeinate-<your user id>`. That file lets your user run only these two commands without a password:

```text
/usr/bin/pmset -a disablesleep 0
/usr/bin/pmset -a disablesleep 1
```

If you cancel instead, clicks skip closed-lid mode until you allow it in Settings > Advanced.

### When sleep comes back

MaCaffeinate turns sleep back on when:

- you click the cup again, or the activation duration ends;
- the battery falls below the level set in Settings > Battery, or Low Power Mode turns on, if you turned those options on;
- MaCaffeinate quits, crashes, or is force quit;
- MaCaffeinate launches again after the Mac lost power with closed-lid mode on.

> **Note:** a closed MacBook that stays awake can get hot in a bag or sleeve. Turn on the battery level option in Settings > Battery if you use closed-lid mode on battery.

### Lid-close beep

When you close the lid in closed-lid mode, MaCaffeinate plays a loud beep, so the Mac does not go into a bag awake by accident.

- On the built-in speakers, it unmutes and raises the volume to at least 75% for the beep, then restores your volume.
- On headphones and other outputs, it plays at your current volume.
- Turn it off in Settings > Advanced.

### Check or remove it

Check whether sleep is turned off right now (`SleepDisabled 1` means it is):

```bash
pmset -g | grep SleepDisabled
```

To remove the permission, untick "Allow keeping the Mac awake with the lid closed" in Settings > Advanced, or run:

```bash
sudo rm /etc/sudoers.d/macaffeinate-$(id -u)
sudo pmset -a disablesleep 0
```

## Automation

The `macaffeinate://` URL scheme starts and stops MaCaffeinate from scripts, for example:

```bash
open -g "macaffeinate:///activate?minutes=30"
open -g "macaffeinate:///deactivate"
```

URL actions switch between off and awake only; closed-lid mode is turned on from the menu bar. See [Automation](Documentation/Automation.md) for every action.

## Build

Open `KeepingYouAwake.xcworkspace` in Xcode 26 or later and build the `KeepingYouAwake` scheme, or build an ad-hoc signed app from the command line as CI does:

```bash
xcodebuild build -workspace KeepingYouAwake.xcworkspace -scheme KeepingYouAwake \
  -configuration Release -derivedDataPath build \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  PROVISIONING_PROFILE_SPECIFIER= OTHER_CODE_SIGN_FLAGS=
```

The app lands in `build/Build/Products/Release/MaCaffeinate.app`.

## License

MIT; see [LICENSE](LICENSE). MaCaffeinate is a fork of [KeepingYouAwake](https://github.com/newmarcel/KeepingYouAwake) by Marcel Dierkes.
