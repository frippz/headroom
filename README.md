# Headroom

Claude Code's five-hour and weekly usage limits in the macOS menu bar and as a
desktop widget.

Originally based on
[saeedkolivand/claude-usage-mac](https://github.com/saeedkolivand/claude-usage-mac)
by Saeed Kolivand, since cut down to the limits alone. It has no updater,
never writes Claude Code's credentials, and does not read your transcripts.

![Headroom: its icon and tagline, the menu bar ring in its three threshold colours, a small widget, and the popover showing the five-hour and weekly limits](docs/screenshot.png)

## Build and install

Requires macOS 14 or later, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
./build.sh               # build, install to /Applications, launch
./build.sh --no-install  # build only, into .build-xcode
```

[Releases](#releasing) carry no binary. Build it yourself.

Both targets are signed with an Apple Development certificate from team
`XU3G5KB593`, which is mine. To build under your own team, change the team ID
in `project.yml` (`DEVELOPMENT_TEAM` and both App Group entitlements) and in
`SnapshotBundle.appGroup`. A free Personal Team works: the App Group is
team-prefixed, so it needs no provisioning profile.

The widget appears in the widget gallery once the app has run.

## What it reads

| Source | Used for |
|---|---|
| The OAuth access token Claude Code already stored | Authenticating the request below |
| `api.anthropic.com/api/oauth/usage` | Five-hour and seven-day utilization, per-model weekly windows where the plan has them, and when each resets |

That request is the only thing sent anywhere. It identifies itself honestly as
`headroom/<version>`. The endpoint is undocumented and may change or
disappear without notice; if it does, the app shows an error rather than
numbers.

The token is read from `<config dir>/.credentials.json`, falling back to the
login Keychain. Claude Code names the Keychain item after its config folder:
`Claude Code-credentials` for `~/.claude`, and
`Claude Code-credentials-<first 8 hex of sha256(config dir)>` for a folder
relocated with `CLAUDE_CONFIG_DIR`.

The Keychain item is read through `/usr/bin/security`. Claude Code writes the
item with that tool, so macOS already trusts it and never prompts. Reading it
directly would prompt again after every token refresh, because Claude Code's
refresh resets the item's access list.

**Tokens are read-only.** The app never refreshes or writes a token. Refreshing
would use up Claude Code's single-use refresh token behind its back and could log
it out. When the access token expires, the app says "Token expired — open Claude
Code in this profile" until Claude Code refreshes it.

The burn rate is measured, not reported: percentage points per hour across the
app's own readings of the five-hour window. It shows nothing until a couple of
polls of active use have gone by.

## Weekly trend

Off by default. **Save weekly readings** in Settings → General makes the app save
each profile's weekly utilization about once an hour, and medium and large
widgets then draw it as a graph: spending so far, an even pace to compare with,
and a projection to the reset, with a line of text saying where that ends up.

The projection uses the window's average rate and starts after the first day.
The API reports only when a window ends, so the graph takes it to have started
seven days before. Before enough readings exist, the line runs straight from
zero, as it does for any part of the week the app wasn't running.

Readings are kept in `bundle.json` and nowhere else. They are cleared at each
reset, and deleted when the setting is turned off.

## Profiles

A profile is a Claude Code config folder, which means one logged-in account.
Discovery looks at `~/.claude`, at any folder beside it whose name starts with
`.claude`, and at folders you add in Settings. A folder counts if it contains a
`projects` directory.

Pick the menu bar's profile in Settings. Each widget picks its own in Edit
Widget.

The Keychain item's name is hashed from the literal `CLAUDE_CONFIG_DIR` string
you exported. Claude Code doesn't resolve the path, so `~/.claude-work` and
`/Users/you/.claude-work/` are different items. The app tries the likely
spellings. If yours is unusual, the profile reports `no-token`. Settings → Profiles
shows the name it looks for.

## Settings

| Tab | What's there |
|---|---|
| General | Refresh interval, open at login, global shortcut, [weekly trend](#weekly-trend) |
| Display | Menu bar style and colour, which limit it shows, amber and red thresholds |
| Alerts | Notifications when a limit crosses a threshold |
| Profiles | Which account the menu bar shows, extra folders, rescan |

Numbers are marked outdated after three missed polls, whatever the interval.

## Reporting bugs

Report a bug with the
[bug report form](https://github.com/frippz/headroom/issues/new?template=bug_report.yml),
which says what to include and what to leave out.

## How it fits together

- **`UsageCore`**: a Swift package holding credentials, the API client,
  profiles, snapshots and formatting. It has no UI.
- **`Headroom.app`**: the menu bar app. It polls every profile and writes
  one `bundle.json`, readable only by you, to the App Group container
  `XU3G5KB593.se.frodlund.claude-usage`. Then it asks WidgetKit to reload.
- **`HeadroomWidget.appex`**: the sandboxed widget. It reads that file and
  nothing else, and never touches the network or credentials.
- **`usage-cli`**: a read-only command-line view of the same data.

## Development

Changes reach `main` through pull requests from `agent/` branches; the
workflow, for people and coding agents alike, is in [AGENTS.md](AGENTS.md).
Enable the Git hooks that enforce it once per clone:

```sh
git config core.hooksPath .githooks
```

```sh
swift test                       # unit tests
swift run usage-cli              # human-readable summary
swift run usage-cli --profiles   # discovered profiles
swift run usage-cli --json       # what the widget will render
```

To build the app and widget without signing or installing, and to run the
snapshot tests, which render every widget size and the menu popover to PNGs
in `snapshots/`:

```sh
xcodegen generate
xcodebuild build -project Headroom.xcodeproj -scheme Headroom \
  -configuration Release -derivedDataPath .build-xcode CODE_SIGNING_ALLOWED=NO
xcodebuild test -project Headroom.xcodeproj -scheme SnapshotTests
```

## Releasing

Versions follow [semantic versioning](https://semver.org) and come from
`vX.Y.Z` Git tags, which [`scripts/version.sh`](scripts/version.sh) stamps
into every build. To release the current `main`:

```sh
git pull --ff-only
git tag v0.2.0
git push origin v0.2.0
```

The Release workflow then creates a GitHub release with notes generated from
the merged pull requests. It refuses a tag on a commit that is not on
`main`.

Releases from v0.2.3 on are immutable: once published, a release's tag
can't be moved, deleted or reused, even if the release is deleted. Fix a
wrong release by tagging the next patch version.

## License

MIT, see [LICENSE](LICENSE). The original repository declares MIT in its
README but ships no license file, so this one uses the standard MIT text.
