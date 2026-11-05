# Headroom

How much of a Claude account's usage limits is spent, shown in the macOS
menu bar and on the desktop.

## Language

### Accounts

**Profile**:
One Claude Code configuration folder and the account logged in through it.
Each profile has its own limits and its own token.
_Avoid_: account (when the folder is meant), config, user

**Token expired**:
The state of a profile whose access token has passed its expiry, until
Claude Code refreshes it.
_Avoid_: logged out, signed out

### Limits

**Limit**:
A share of usage an account may spend within a window, reported as
utilization from 0 to 100 percent.
_Avoid_: quota, cap, budget

**Five-hour limit**:
The limit over a rolling five-hour window.
_Avoid_: session limit (in copy), 5h window

**Weekly limit**:
The limit over a seven-day window.
_Avoid_: seven-day limit, 7d

**Per-model weekly limit**:
A weekly limit that counts only one model family, such as Opus or Sonnet,
on the plans that have one.
_Avoid_: model quota

**Utilization**:
How much of a limit is spent, as a percentage.
_Avoid_: usage percentage, consumption

**Reset**:
The moment a limit's window ends and its utilization returns to zero.
_Avoid_: renewal, refill

**Burn rate**:
How fast the five-hour limit's utilization rises, in percentage points per
hour, measured across the app's own readings.
_Avoid_: speed, velocity

**Weekly trend**:
The weekly limit's utilization across its window, from readings the app saves
once the user opts in, and where it is heading by the reset.
_Avoid_: history, usage graph

### State

**Level**:
How close a limit is to full: ok, warn or critical, set by the warn and
critical thresholds.
_Avoid_: severity, status

**Outdated**:
Numbers older than three polls, because refreshing them failed; shown
with a warning instead of being hidden.
_Avoid_: old, expired (that is the token)
