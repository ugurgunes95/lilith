# Lilith

A small, fast Spotlight alternative for macOS. Press a shortcut, type, hit Enter.

Lilith lives in the menu bar (no Dock icon) and opens a search panel on the screen your mouse is on. It's plain Swift and AppKit with no dependencies.

## Install

Requires macOS 14 or later and the Swift toolchain (Xcode or Command Line Tools).

```sh
./build.sh            # builds build/Lilith.app
./build.sh --install  # also copies it to /Applications
```

Open `/Applications/Lilith.app`. A magnifying glass appears in the menu bar. Turn on **Launch at Login** there to keep it running.

## Uninstall

1. In the menu bar, turn off **Launch at Login**, then choose **Quit Lilith**.
   If you skip this, remove Lilith from System Settings › General › Login Items afterwards.
2. Delete the app and its data:

   ```sh
   rm -rf /Applications/Lilith.app
   defaults delete local.lilith    # settings, clipboard history, app usage counts, saved exchange rates
   rm -rf ~/Library/Preferences/local.lilith.plist ~/Library/Caches/local.lilith ~/Library/HTTPStorages/local.lilith
   tccutil reset All local.lilith  # forget the Accessibility and Automation permissions
   ```

3. If you set the launcher to `⌘Space`, turn Spotlight's shortcut back on in System Settings › Keyboard › Keyboard Shortcuts › Spotlight.

Lilith itself writes nothing else. Your scripts folder, and anything your scripts create, are left alone.

## Using the panel

| Key | Does |
|---|---|
| Launcher shortcut (default `⌥Space`) | Open / close the panel |
| `↑` `↓` | Move the selection |
| `Enter` | Run the selected result |
| `⌘K` | Actions for the selected app, file or script |
| `Esc` | Close the panel, or leave the actions list |
| `⌘A` `⌘C` `⌘V` `⌘X` `⌘Z` `⇧⌘Z` | Usual text editing in the search field |

Results can also be clicked. The panel closes when it loses focus.

## Features

### App search

Type part of an app's name. Matching is forgiving and ranks matches in this order:

1. Name starts with what you typed: `saf` → Safari
2. Initials: `vsc` → Visual Studio Code
3. A word starts with it: `code` → Visual Studio Code
4. Letters appear in order: `trml` → Terminal

App names show in your system language (e.g. **Hesap Makinesi** for Calculator on a Turkish Mac).
With an empty search field, Lilith lists your most used apps. It counts every app activation, from the Dock, `⌘Tab` or Lilith.

Searched folders: `/Applications`, `/System/Applications` (and their `Utilities`), `~/Applications`, plus Finder.

### Calculator

Type a math expression and the result is the first row. `Enter` copies it.

```
7000000*2        → 14.000.000
(2+3)*4          → 20
2^10             → 1.024
-2^2             → -4
3,5 * 2          → 7
1/3              → 0,3333333333
```

- Supports `+ - * / ^` and parentheses. `^` is right-associative (`2^3^2` = 512).
- `,` and `.` both work as the decimal point.
- Results use your region's number format (14.000.000 in Turkish, 14,000,000 in English).
- `Enter` copies the plain number without thousands separators (`14000000`), so it pastes cleanly into other apps.

### Unit conversions

Type a number, a unit and a target unit. The word `to`, `in` or `into` is optional.

```
10 km to mi      → 6,21371 mil
100 f in c       → 37,7778°C
5 kg lb          → 11,0231 lb
2,5 l ml         → 2.500 ml
90 km/h mph      → 55,9235 mil/sa
3 dönüm m2       → 3.000 m²
1 gb to mb       → 1.000 MB
5 in in cm       → 12,7 cm
```

| Kind | Units (English and Turkish names accepted) |
|---|---|
| Length | `km` `m` `cm` `mm` `mi`/`mil` `yd` `ft` `in`/`inç` |
| Weight | `t`/`ton` `kg`/`kilo` `g` `lb`/`libre` `oz`/`ons` |
| Volume | `l`/`litre` `ml` `gal`/`galon` |
| Temperature | `c`/`santigrat` `f`/`fahrenhayt` `kelvin` |
| Speed | `km/h` `mph` `m/s` `kn` |
| Area | `km2` `m2` `ft2` `ha`/`hektar` `acre` `dönüm` |
| Time | `h`/`saat` `min`/`dakika` `s`/`saniye` |
| Data | `b` `kb` `mb` `gb` `tb` |

Full names and plurals work too: `3 miles to kilometers`.
A unit needs a target, so `10 km` alone shows nothing. `Enter` copies the plain number.

### Currency conversions

```
100 usd to try   → ₺4.952,70
100 dolar tl     → ₺4.952,70
$100             → ₺4.952,70      (no target: converts to your currency)
€50 tl           → ₺2.783,62
1000 jpy to tl   → ₺313,46
100 tl           → $2,02          (from your own currency: converts to USD)
```

- Any of 166 ISO codes (`usd`, `eur`, `gbp`, `jpy`, `chf`…), the symbols `$ € £ ₺ ¥`, and the names `dolar`/`dollar`, `euro`/`avro`, `sterlin`, `tl`/`lira`, `yen`.
- `pound` and `cup` mean the units. Use `gbp`, `£` or `sterlin` for pounds sterling.
- Results use your region's currency format. `Enter` copies the plain amount (`4952,70`).
- Rates come from [Exchange Rate API](https://www.exchangerate-api.com) (free, no key). They update once a day, and each result shows the rate date.
- Lilith fetches rates at launch and when you open the panel if they're over 12 hours old. Rates are saved, so conversions work offline. Only the rate list is downloaded; what you type is never sent anywhere.

### Websites

Type a URL and `Enter` opens it in your default browser.

```
github.com            → https://github.com
ugurgunes.dev         → https://ugurgunes.dev
http://localhost.dev/a?b=1
```

Bare file names that look like domains (`main.py`, `Package.swift`) are left alone.

### Web search

When nothing else matches, the panel offers **Search the web for “…”**. `Enter` opens a Google search for what you typed in your default browser.

```
how to center a div   → Search the web for “how to center a div”
```

The row appears only when there are no other results. File results arrive a moment after you type, so if one turns up, it takes the row's place.

### File search

Searches file and folder **names and contents** in your home folder via the Spotlight index. Type at least 3 characters.

```
invoice          → invoice-2026.pdf, files containing the word "invoice"…
```

- Name matches come first, then content matches, each sorted by last used. Up to 20 results.
- Skips `~/Library`, hidden folders and `node_modules`.
- `Enter` opens a **Quick Look** preview. `⌘K` offers **Quick Look**, **Open** and **Reveal in Finder**.

### Clipboard history

Lilith remembers the last 50 texts you copied. Open it with the clipboard shortcut (default `⇧⌘V`) or by typing `cb` in the panel.

```
cb               → recent clipboard items
cb invoice       → only items containing "invoice"
```

- `Enter` pastes the item into the app you were using. The first time, macOS asks for **Accessibility** permission. Without it, the item is still copied and you paste with `⌘V`.
- Passwords copied from password managers are never recorded.
- History survives restarts. **Clear Clipboard History** in the menu empties it.

### Scripts

Pick a folder with **Choose Scripts Folder…** in the menu. Every `.sh` file in it becomes a searchable result.

```
deploy           → runs deploy.sh
```

- Scripts run in their own folder with your login shell's `PATH`. Executable scripts use their shebang, others run with `/bin/sh`.
- By default they run in the background. When a script finishes, the panel reopens with its exit status and output (`Enter` copies all of it, or pick one line). Scripts that succeed silently show nothing.
- Turn on **Run Scripts in Terminal** to run them in a new Terminal window instead.

### System commands

```
sleep            → Sleep
restart          → Restart
shut down        → Shut Down
log out          → Log Out
```

These go through System Events, so macOS asks for **Automation** permission the first time.

## Menu bar settings

| Item | |
|---|---|
| Open Lilith | Shows the panel |
| Launcher Shortcut | `⌥Space`, `⌃Space`, `⌘Space`, `⌥⌘Space`, `⇧⌘Space` |
| Clipboard Shortcut | `⇧⌘V`, `⌃⌥V`, `⌥⌘V`, `⌃⌘V` |
| Calculator, Conversions, System Commands, File Search, Clipboard History | Turn each feature on or off |
| Clear Clipboard History | |
| Choose Scripts Folder… / Run Scripts in Terminal | See [Scripts](#scripts) |
| Launch at Login | |
| Quit Lilith | |

To use `⌘Space`, first turn off Spotlight's shortcut in System Settings › Keyboard › Keyboard Shortcuts › Spotlight. If a shortcut is already taken by another app, Lilith beeps and keeps the old one.

## Development

```sh
swift build                       # debug build
.build/debug/Lilith --selftest    # runs the built-in checks, prints "selftest ok"
```

| File | |
|---|---|
| `Sources/Lilith/main.swift` | App setup, global shortcuts, menu bar |
| `Sources/Lilith/Panel.swift` | Search panel, results, keys, `⌘K` actions, Quick Look |
| `Sources/Lilith/Apps.swift` | App scanning, match scoring, self-test |
| `Sources/Lilith/Extras.swift` | Calculator, websites, system commands, file search, scripts, clipboard |
| `Sources/Lilith/Convert.swift` | Unit and currency conversions, exchange rates |
| `Resources/` | `Info.plist` and app icon |
