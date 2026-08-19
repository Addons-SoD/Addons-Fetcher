# Addons-Fetcher

One-click deployment script for World of Warcraft Classic Era (1.15.x client) addons.

## What it does

- Downloads every CurseForge addon listed in the script (latest Classic Era file)
  through the official CurseForge Core API, with a www.curseforge.com scraper as
  fallback.
- Downloads the `*-SoD` addons maintained under the
  [Addons-SoD](https://github.com/Addons-SoD) account directly from GitHub as
  source archive zips (works identically on every machine - no local git
  workspace required).
- Extracts everything into the `AddOns` subfolder next to the script. The
  script is meant to live in the `Interface` folder, so addons land in
  `...\_classic_era_\Interface\AddOns` (i.e. the game's `AddOns` directory).
- Deletes all downloaded zip files when finished.

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

1. Copy `Addons-Fetcher.cmd` into your `Interface` folder:
   `<WoW install dir>\_classic_era_\Interface`
2. Run it (double-click or from a terminal).
3. Wait for the progress bars to finish and check the deployment summary.

Tip: if you start from an empty folder, drop
[Addons-init](https://github.com/Addons-SoD/Addons-init) into the `Interface`
folder instead - it fetches the latest version of this script for you and
runs it.

### Running from a clone

The repository ignores the `AddOns/` folder, so you can also clone this
repository directly into your `Interface` folder, keep it up to date with
`git pull`, and run `Addons-Fetcher.cmd` from there.


## Stability (v3)

- **Slow-download guard** - a transfer averaging below 50 KB/s is killed and
  retried on another channel; after 3 slow kills the CDN channels are
  re-probed and the fastest one is picked again, so flaky networks self-heal
  mid-run.
- **Live throughput** - the progress bar shows the current overall download
  speed (MB/s).
- **CPU-scaled extraction** - extraction parallelism is logical cores - 2
  (min 1).
- SoD addons are downloaded from `codeload.github.com` first (direct, no
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

