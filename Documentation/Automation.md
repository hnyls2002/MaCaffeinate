# MaCaffeinate Automation

## URL Scheme

MaCaffeinate supports the `macaffeinate:///` URL scheme to activate and deactive the app externally.

### activate

```
macaffeinate:///activate
```

Activates and prevents sleep for the configured default duration.

#### activate?seconds=X

```
macaffeinate:///activate?seconds=30
```

Activates and prevents sleep for exactly 30 seconds.

#### activate?minutes=X

```
macaffeinate:///activate?minutes=5
```

Activates and prevents sleep for exactly 5 minutes.

#### activate?hours=X

```
macaffeinate:///activate?hours=2
```

Activates and prevents sleep for exactly 2 hours.

_Please note: the seconds, minutes and hours parameters cannot be combined at the moment._

### deactivate

```
macaffeinate:///deactivate
```

Deactivates and allows the system to go to sleep.

### toggle

```
macaffeinate:///toggle
```

Toggles the activation state between activated and deactivated.

## Command Line Usage

The URL scheme can be used together with the `open` command to control MaCaffeinate from the command line.

```
open -g "macaffeinate:///activate"
open -g "macaffeinate:///activate?seconds=30"
open -g "macaffeinate:///deactivate"
open -g "macaffeinate:///toggle"
```
