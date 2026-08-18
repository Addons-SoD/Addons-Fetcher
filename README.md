# Addons-Fetcher

One-click deployment script for World of Warcraft Classic Era (1.15.x client) addons.

## What it does

- Downloads every CurseForge addon listed in the script (latest Classic Era file)
  through the official CurseForge Core API, with a www.curseforge.com scraper as
  fallback.
- Deploys the `*-SoD` addons maintained under the
  [Addons-SoD](https://github.com/Addons-SoD) account: copied from a local git
  workspace when present, otherwise downloaded from GitHub.
- Extracts everything into the `Addons` subfolder next to the script. The
  script is meant to live in the `Interface` folder, so addons land in
  `...\_classic_era_\Interface\Addons` (i.e. the game's `AddOns` directory).
- Deletes all downloaded zip files when finished.

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

The repository ignores the `Addons/` folder, so you can also clone this
repository directly into your `Interface` folder, keep it up to date with
`git pull`, and run `Addons-Fetcher.cmd` from there.

## Notes

- Requires Windows PowerShell 5.1+ (built into Windows 10/11).
- CurseForge metadata lookups use the API key shipped with the official
  CurseForge desktop app; bulk downloads go straight to the ForgeCDN mirror.
- The addon list is defined inside the script (search for `$Projects` and
  `$SodRepos`).

## License

MIT - see [LICENSE](LICENSE).
