# Addons-Fetcher (WoW Forever)

One-click deployment script for **World of Warcraft: Forever**
("魔兽世界：无限", client folder `_forever_`, product flavor `wowf`,
addon interface **16001**) addons.

This is the `wow-forever` branch. The `main` branch keeps the original
Classic Era / Season of Discovery deployer and is not affected by this port.

## What it does

- Downloads every CurseForge addon listed in the script, resolved to the
  newest file that supports **1.60.x** first, then **12.1.x**, **12.0.x**
  and **11.x** (Mainline - the API family Forever is built on), then the
  newest release file.
- Downloads the `*-SoD` addons maintained under the
  [Addons-SoD](https://github.com/Addons-SoD) account from the
  **`wow-forever` branch** of each repository (the ported, mainline-API
  version), as source archive zips - no local git workspace required.
- Extracts everything into the `AddOns` subfolder next to the script. The
  script is meant to live in the `Interface` folder, so addons land in
  `...\_forever_\Interface\AddOns` (the game's `AddOns` directory).
- **TOC normalisation**: after extraction every freshly deployed addon TOC
  gets `16001` added to its `## Interface:` line, so the Forever client does
  not flag it as out of date and skip it. The rest of the TOC is untouched
  (byte-level edit, original encoding preserved).
- Deletes all downloaded zip files when finished.

## CurseForge list: kept vs. dropped

The Classic Era list was filtered against the CurseForge API: a project is
kept only when it publishes a Forever (1.60.x) or Mainline (12.x/11.x) file.
Everything else has no Forever counterpart and was removed.

### Kept (26)

| Addon | Newest compatible file | Version family |
| --- | --- | --- |
| Auctionator | 341 | 1.60.1 |
| AutoFlood | AutoFlood 1.6.4 | 1.60.1 |
| Baganator | 840 | 1.60.1 |
| BigWigs | v427.8 | 1.60.1 |
| BigWigs_Transcriptor | v12.1.2 | 1.60.1 |
| BlizzMove | v3.8.6 | 1.60.1 |
| BugGrabber | v12.1.1 | 1.60.1 |
| BugSack | v12.1.9 | 1.60.1 |
| Decursive | 2.9.0-RC4-forever | 1.60.1 |
| Details | Details.20261104.15400.172 | 1.60.1 |
| idTip | 12.1.8 | 1.60.1 |
| Leatrix_Maps | 1.60.27-forever | 1.60.1 |
| MessageQueue | MessageQueue 0.9.4 | 1.60.1 |
| MinimapButtonButton | 1.24.15 | 1.60.1 |
| Myslot | v6.2.1 | 1.60.1 |
| Profession_Assistance | PA_V6.3.1 | 12.1.x (no 1.60 file) |
| Questie | v12.6.0 | 1.60.1 |
| RangeDisplay | v6.3.7 | 1.60.1 |
| RareScanner | RareScanner_FOREVER_1.60.1.1 | 1.60.1 |
| SpellActivationOverlay | SpellActivationOverlay-2.8.9-forever | 1.60.1 |
| Syndicator | 289 | 1.60.1 |
| ThreatClassic2 | 2.75-forever | 1.60.1 |
| TotemTimers | 5.0.13 | 1.60.1 |
| Transcriptor | v12.1.4 | 1.60.1 |
| _DebugLog | 1.3.3 | 12.0.x (no 1.60 file) |
| LoonBestInSlot | LoonBestInSlot-retail-v1.1.3 | 12.1.0 |

### Dropped - no Forever counterpart (16)

| Addon | Reason |
| --- | --- |
| AtlasLootClassic | files only for 1.15.x / 2.5.x, no Mainline build |
| CharacterStatsClassic | Classic Era only |
| DruidBarClassic | Classic Era only |
| ExtendedCharacterStats | TBC Classic only |
| GatherMate2 | Classic/TBC/Mists only |
| GatherMate2_Data | classic gathering data only (host addon is gone) |
| LiteButtonAuras | Classic-era API only |
| NovaWorldBuffs | Classic world-buff data only |
| Spy | Classic Era only |
| WeakAuras | no Mainline/Forever file; battle addons are restricted in Forever |
| WeWantBlueShamans | Classic Era only |
| alaGearMan | Cata/Mists only |
| alaTradeSkill | Cata/Mists only |
| Ranker | Classic Era only |
| RuneReminderReforged | Classic Era / SoD only |
| TalentEmuX | Cata/Mists only |

## Own GitHub addons (ported to the modern API)

The `*-SoD` repositories got a `wow-forever` branch with the addon code
ported from the Classic Era API to the Forever/Mainline API. The deployer
always fetches that branch.

| Addon | Repository |
| --- | --- |
| BFGadgets | [BFGadgets-SoD](https://github.com/Addons-SoD/BFGadgets-SoD) |
| BiaoGe | [BiaoGe-SoD](https://github.com/Addons-SoD/BiaoGe-SoD) |
| bloodOfHeros | [bloodOfHeros-SoD](https://github.com/Addons-SoD/bloodOfHeros-SoD) |
| MYStats | [MYStats-SoD](https://github.com/Addons-SoD/MYStats-SoD) |
| RepairHelper | [RepairHelper-SoD](https://github.com/Addons-SoD/RepairHelper-SoD) |
| SellerHelper | [SellerHelper-SoD](https://github.com/Addons-SoD/SellerHelper-SoD) |
| TheBurningTrade | [TheBurningTrade-SoD](https://github.com/Addons-SoD/TheBurningTrade-SoD) |
| WhisperPop | [WhisperPop-SoD](https://github.com/Addons-SoD/WhisperPop-SoD) |

Porting rules applied to those branches:

- TOC `## Interface: 16001`.
- Removed globals replaced with `C_` APIs: `GetSpellInfo` ->
  `C_Spell.GetSpellInfo`, `GetItemInfo` -> `C_Item.GetItemInfo`,
  `GetContainerItemInfo`/`GetContainerNumSlots` -> `C_Container.*`,
  `UnitAura`/`UnitBuff`/`UnitDebuff` -> `C_UnitAuras.*`,
  `GetSpellCooldown`/`GetSpellTexture` -> `C_Spell.*`.
- Combat log readers disabled (`COMBAT_LOG_EVENT_UNFILTERED` is not
  available in Forever); the affected features degrade gracefully.
- Secret values (`UnitHealth`, `UnitName`, ...) are never compared or
  concatenated without an `issecretvalue` guard.
- `WOW_PROJECT_ID` is `18` (`WOW_PROJECT_CAMELOT`) - no `== 1` Mainline
  checks remain.

## Smart download channels (v2)

Slow downloads are usually caused by poor direct routes to the CDN
(CloudFront) and by the fact that `curl.exe` does not use the Windows system
proxy. The script now handles both automatically:

1. **Channel probing** - after resolving the file list it speed-tests, in
   parallel, the Windows system proxy (if present) and every reachable CDN IP
   (system DNS + AliDNS) against the *biggest real file* being deployed
   (small files give misleading throughput on CDN edges).
2. **Fastest channel wins** - downloads go through the fastest route found
   (proxy or direct IP). No proxy is required: without one, the script simply
   picks the best direct IP among several.
3. **Channel pool** - the top channels (within the same speed league) are
   rotated across downloads so one flaky node cannot stall everything; files
   that still fail after retries get one last attempt through the plain
   default route.
4. **30-minute cache** - only *direct-IP* results are cached (in
   `.addons-fetcher-cache.json` next to the script), so repeat runs without
   a proxy skip the probing step. The system proxy is NEVER cached - it is
   re-validated on every run, so turning your proxy off can never break a
   download (a dead proxy simply fails its probe and the script falls back
   to direct links).

Other v2 speed-ups: metadata lookups run in parallel (x8) and extraction uses
`tar.exe` with 4 workers (fallback: `Expand-Archive`).

## Usage

1. Copy `Addons-Fetcher.cmd` into your Forever client's `Interface` folder:
   `<WoW install dir>\_forever_\Interface`
2. Run it (double-click or from a terminal).
3. Wait for the progress bars to finish and check the deployment summary.

Tip: if you start from an empty folder, drop
[Addons-init](https://github.com/Addons-SoD/Addons-init) into the `Interface`
folder instead - it fetches the latest version of this script for you and
runs it.

### Running from a clone

The repository ignores the `AddOns/` folder, so you can also clone this
repository (branch `wow-forever`) directly into your `Interface` folder, keep
it up to date with `git pull`, and run `Addons-Fetcher.cmd` from there.

## Stability (v3)

- **Slow-download guard** - a transfer averaging below 50 KB/s is killed and
  retried on another channel; after 3 slow kills the CDN channels are
  re-probed and the fastest one is picked again, so flaky networks self-heal
  mid-run.
- **Live throughput** - the progress bar shows the current overall download
  speed (MB/s).
- **CPU-scaled extraction** - extraction parallelism is logical cores - 2
  (min 1).
- Own addons are downloaded from `codeload.github.com` first (direct, no
  redirect), with the `github.com` archive and the GitHub API tarball as
  fallbacks.

## Notes

- Requires Windows PowerShell 5.1+ (built into Windows 10/11).
- CurseForge metadata lookups use the API key shipped with the official
  CurseForge desktop app; bulk downloads go straight to the ForgeCDN mirror.
- The addon list is defined inside the script (search for `$Projects` and
  `$SodRepos`).

## License

MIT - see [LICENSE](LICENSE).
