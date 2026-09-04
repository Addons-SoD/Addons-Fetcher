@echo off
title Addons-Fetcher - WoW Classic Era AddOns One-Click Deploy
chcp 65001 >nul
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$env:DEPLOY_SELF='%~f0'; $env:DEPLOY_DIR='%~dp0'; $c=[IO.File]::ReadAllText('%~f0',[Text.Encoding]::UTF8); $m=([char]10).ToString()+'#PS'+'START'; $i=$c.IndexOf($m); if($i -lt 0){ Write-Host 'Script marker not found.'; exit 1 }; Invoke-Expression ($c.Substring($i+$m.Length))"
exit /b %ERRORLEVEL%
#PSSTART
# ============================================================================
#  WoW Classic Era - AddOns one-click deployment script  (v3)
#  - Downloads all CurseForge addons listed below (latest Classic Era file)
#  - Downloads the *-SoD addons from GitHub (source archive zip; works on
#    any machine, no local git workspace required)
#  - Extracts everything into the 'AddOns' subfolder next to THIS script
#    (put this script into the 'Interface' folder and run it there)
#  - Deletes all downloaded zip files when finished
#  v3 changes:
#  * SoD addons are always fetched from GitHub (github.com archive ->
#    codeload direct -> api.github.com tarball), with a proxy-vs-direct
#    channel probe when a proxy is available.
#  * Slow-download guard: a transfer averaging below 50 KB/s is killed and
#    retried on another channel; after 3 slow kills the CDN channels are
#    re-probed and the fastest one is picked again.
#  * The progress bar now shows the live overall throughput (MB/s).
#  * Extraction parallelism = logical CPU cores - 2 (min 1).
#  v2 changes:
#  * Smart channel selection: detects the Windows system proxy, enumerates
#    multiple CDN IPs (system DNS + AliDNS), speed-tests every candidate in
#    parallel and uses the fastest one. No proxy required - a proxy is only
#    used when the system has one AND it proves faster than direct links.
#    The chosen channel is cached for 30 minutes ('.addons-fetcher-cache.json'
#    next to this script).
#  * Phase 1 metadata lookups run in parallel (x8 curl processes).
#  * Extraction uses tar.exe with 4 parallel workers (fallback: Expand-Archive).
#  Notes:
#  - Metadata lookups use the official CurseForge Core API
#    (api.curseforge.com) with the API key of the locally installed
#    CurseForge app.
#  - If the Core API is unavailable, the script falls back to scraping
#    www.curseforge.com with the Windows native Schannel HTTP stack.
#  - Bulk downloads go straight to the ForgeCDN mirror.
# ============================================================================
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$Self      = $env:DEPLOY_SELF
$ScriptDir = ($env:DEPLOY_DIR).TrimEnd('\')
$DeployDir  = Join-Path $ScriptDir 'AddOns'
$CacheFile = Join-Path $ScriptDir '.addons-fetcher-cache.json'
$StateFile = Join-Path $ScriptDir '.addons-fetcher-state.json'
$CacheTtl  = 1800

# ----------------------------- configuration --------------------------------
$Ua          = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'
$Referer     = 'https://www.curseforge.com/wow/addons'
$ApiBase     = 'https://www.curseforge.com/api/v1'
$CoreBase    = 'https://api.curseforge.com/v1'
$CfApiKey    = '$2a$10$bL4bIL5pUWqfcO7KQtnMReakwtfHbNKh6v1uTpKlzhwoueEJQnPnm'
$GhUser      = 'Addons-SoD'
# Parallel curl workers for CurseForge resolves and downloads: logical
# cores - 2 (min 1), the same rule extraction uses below.
$Concurrency = [Math]::Max(1, [Environment]::ProcessorCount - 2)
$SilenceSec   = 180
$CdnSilenceSec = 60
$CdnToken    = '267C6CA3'

$CfHeaders = @{
  'User-Agent'      = $Ua
  'Referer'         = $Referer
  'Accept'          = 'application/json'
  'Accept-Language' = 'en-US,en;q=0.9'
}
$CoreHeaders = @{ 'x-api-key' = $CfApiKey; 'Accept' = 'application/json' }
# CurseForge projects: display name -> numeric CurseForge project id
$Projects = @(
  @{ Name = 'AtlasLootClassic';         Id = 1180455 },
  @{ Name = 'Auctionator';              Id = 6124    },
  @{ Name = 'AutoFlood';                Id = 21367   },
  @{ Name = 'Baganator';                Id = 914482  },
  @{ Name = 'BigWigs';                  Id = 2382    },
  @{ Name = 'BigWigs_Classic';          Id = 50625   },
  @{ Name = 'BigWigs_Transcriptor';     Id = 53389   },
  @{ Name = 'BlizzMove';                Id = 17809   },
  @{ Name = 'BugGrabber';               Id = 13344   },
  @{ Name = 'BugSack';                  Id = 6273    },
  @{ Name = 'CharacterStatsClassic';    Id = 338856  },
  @{ Name = 'Decursive';                Id = 2154    },
  @{ Name = 'Details';                  Id = 61284   },
  @{ Name = 'DruidBarClassic';          Id = 334762  },
  @{ Name = 'ExtendedCharacterStats';   Id = 334877  },
  @{ Name = 'GatherMate2';              Id = 405809  },
  @{ Name = 'idTip';                    Id = 24541   },
  @{ Name = 'Leatrix_Maps';             Id = 298842  },
  @{ Name = 'LiteButtonAuras';          Id = 526431  },
  @{ Name = 'MessageQueue';             Id = 358350  },
  @{ Name = 'MinimapButtonButton';      Id = 446096  },
  @{ Name = 'Myslot';                   Id = 48863   },
  @{ Name = 'NovaWorldBuffs';           Id = 366310  },
  @{ Name = 'Profession_Assistance';    Id = 65085   },
  @{ Name = 'Questie';                  Id = 334372  },
  @{ Name = 'RangeDisplay';             Id = 14570   },
  @{ Name = 'RareScanner';              Id = 84208   },
  @{ Name = 'SpellActivationOverlay';   Id = 649417  },
  @{ Name = 'Spy';                      Id = 323123  },
  @{ Name = 'Syndicator';               Id = 988370  },
  @{ Name = 'ThreatClassic2';           Id = 355497  },
  @{ Name = 'TotemTimers';              Id = 339602  },
  @{ Name = 'Transcriptor';             Id = 14837   },
  @{ Name = 'WeakAuras';                Id = 65387   },
  @{ Name = 'WeWantBlueShamans';        Id = 962536  },
  @{ Name = 'alaGearMan';               Id = 347869  },
  @{ Name = 'alaTradeSkill';            Id = 380889  },
  @{ Name = 'Ranker';                   Id = 907755  },
  @{ Name = 'RuneReminderReforged';     Id = 1640798 },
  @{ Name = 'TalentEmuX';               Id = 338706  },
  @{ Name = 'GatherMate2_Data';         Id = 350035  },
  @{ Name = '_DebugLog';                Id = 382165  },
  @{ Name = 'LoonBestInSlot';           Id = 570934  }
)

# Own SoD addons from git repositories (repo name -> addon folder name)
$SodRepos = @(
  @{ Repo = 'BFGadgets-SoD';        Folder = 'BFGadgets'       },
  @{ Repo = 'BiaoGe-SoD';           Folder = 'BiaoGe'          },
  @{ Repo = 'bloodOfHeros-SoD';     Folder = 'bloodOfHeros'    },
  @{ Repo = 'RepairHelper-SoD';     Folder = 'RepairHelper'    },
  @{ Repo = 'SellerHelper-SoD';     Folder = 'SellerHelper'    },
  @{ Repo = 'TheBurningTrade-SoD';  Folder = 'TheBurningTrade' },
  @{ Repo = 'WhisperPop-SoD';       Folder = 'WhisperPop'      }
)

# ------------------------------- helpers ------------------------------------
# Console width is kept at 80 columns (best compatibility); long lines are
# truncated with '...'.
$ConWidth = 80
$HLine = '=' * $ConWidth

# Disable QuickEdit (clicking the console pauses the script in select mode)
# and hide the cursor while running.
function Init-ConsoleMode{
  try{
    if(-not ('AddonsConsoleHelper' -as [type])){
      $src = @'
using System;
using System.Runtime.InteropServices;
public static class AddonsConsoleHelper {
  [DllImport("kernel32.dll", SetLastError = true)]
  public static extern IntPtr GetStdHandle(int nStdHandle);
  [DllImport("kernel32.dll", SetLastError = true)]
  public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
  [DllImport("kernel32.dll", SetLastError = true)]
  public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
  [DllImport("kernel32.dll", SetLastError = true)]
  public static extern bool SetConsoleCursorInfo(IntPtr hConsoleOutput, ref CONSOLE_CURSOR_INFO lpConsoleCursorInfo);
  [StructLayout(LayoutKind.Sequential)]
  public struct CONSOLE_CURSOR_INFO { public uint dwSize; public bool bVisible; }
}
'@
      Add-Type -TypeDefinition $src
    }
    $in  = [AddonsConsoleHelper]::GetStdHandle(-10)
    $out = [AddonsConsoleHelper]::GetStdHandle(-11)
    $mode = [uint32]0
    if([AddonsConsoleHelper]::GetConsoleMode($in, [ref]$mode)){
      $mode = $mode -band (-bnot 0x0040) -band (-bnot 0x0020)
      [void][AddonsConsoleHelper]::SetConsoleMode($in, $mode)
    }
    $cci = New-Object AddonsConsoleHelper+CONSOLE_CURSOR_INFO
    $cci.dwSize = 1
    $cci.bVisible = $false
    [void][AddonsConsoleHelper]::SetConsoleCursorInfo($out, [ref]$cci)
  }catch{}
}

# Restore QuickEdit + the cursor before exiting (also before Read-Host).
function Restore-ConsoleMode{
  try{
    if(('AddonsConsoleHelper' -as [type])){
      $in  = [AddonsConsoleHelper]::GetStdHandle(-10)
      $out = [AddonsConsoleHelper]::GetStdHandle(-11)
      $mode = [uint32]0
      if([AddonsConsoleHelper]::GetConsoleMode($in, [ref]$mode)){
        $mode = $mode -bor 0x0040 -bor 0x0020
        [void][AddonsConsoleHelper]::SetConsoleMode($in, $mode)
      }
      $cci = New-Object AddonsConsoleHelper+CONSOLE_CURSOR_INFO
      $cci.dwSize = 20
      $cci.bVisible = $true
      [void][AddonsConsoleHelper]::SetConsoleCursorInfo($out, [ref]$cci)
    }
  }catch{}
}

function Truncate-Text([string]$s,[int]$maxLen){
  if($s.Length -gt $maxLen){
    if($maxLen -le 3){ return $s.Substring(0, [Math]::Min($maxLen, $s.Length)) }
    return $s.Substring(0, $maxLen - 3) + '...'
  }
  return $s
}

# Animated spinner character shown at the head of every progress-bar row.
$script:SpinIdx = 0
function Get-SpinChar{
  $script:SpinIdx = ($script:SpinIdx + 1) % 4
  return ('-','\','|','/')[$script:SpinIdx]
}

# Blocking wait with an animated spinner on its own row (used for the long
# silent cooldowns so the console does not look frozen).
function Wait-Spin([int]$sec,[string]$msg){
  $steps = $sec * 5
  for($w = 0; $w -lt $steps; $w++){
    Start-Sleep -Milliseconds 200
    Write-Host ("`r  " + (Get-SpinChar) + " " + $msg + " (" + [int](($w + 1) / 5) + "s/" + $sec + "s)  ") -NoNewline
  }
  Write-Host ("`r" + (' ' * $ConWidth)) -NoNewline
  Write-Host ''
}

function Test-Writable($dir){
  try{
    $t = Join-Path $dir ('.wt_' + [Guid]::NewGuid().ToString('N'))
    [IO.File]::WriteAllText($t,'1') | Out-Null
    Remove-Item -LiteralPath $t -Force
    return $true
  }catch{ return $false }
}

function Show-Bar($ratio,$text){
  if($ratio -lt 0){ $ratio = 0 }
  if($ratio -gt 1){ $ratio = 1 }
  $w = 20
  $f = [int]([Math]::Round($w * $ratio))
  $bar = ([string][char]0x2588) * $f + ([string][char]0x2591) * ($w - $f)
  $line = "`r " + (Get-SpinChar) + " [" + $bar + "] " + ("{0,3}" -f [int]($ratio*100)) + "%  " + $text
  if($line.Length -gt $ConWidth){ $line = $line.Substring(0, $ConWidth - 3) + '...' }
  Write-Host ($line.PadRight($ConWidth)) -NoNewline
}

function Finish-Line{
  # Carriage-return to the line start, then overwrite the trailing
  # progress-bar row so the last status text does not linger on screen.
  Write-Host ("`r" + (' ' * $ConWidth)) -NoNewline
  Write-Host ''
}

function Show-Info($msg,$color){
  Write-Host ''
  Write-Host ('    ' + (Truncate-Text $msg ($ConWidth - 4))) -ForegroundColor $color
}

function Get-StatusCode($err){
  try{
    if($err.Exception.Response){ return [int]$err.Exception.Response.StatusCode }
  }catch{}
  return 0
}

# Build a single command line for Start-Process (quotes args containing spaces).
function Get-CurlArgLine([string[]]$argArr){
  return (($argArr | ForEach-Object { if([string]$_ -match '[ "	]'){ '"' + ([string]$_ -replace '"','\"') + '"' } else { [string]$_ } }) -join ' ')
}

# Start curl in a hidden window; optionally redirect stdout to $outFile (used
# by the speed probes to read back the -w %{speed_download} value).
function Start-CurlProc([string[]]$argArr,[string]$outFile){
  $argLine = Get-CurlArgLine $argArr
  if($outFile){
    $p = Start-Process -FilePath 'curl.exe' -ArgumentList $argLine -PassThru -WindowStyle Hidden -RedirectStandardOutput $outFile -RedirectStandardError ($outFile + '.err')
  } else {
    $p = Start-Process -FilePath 'curl.exe' -ArgumentList $argLine -PassThru -WindowStyle Hidden
  }
  return $p
}

# Read the Windows system proxy (the one browsers use). Returns $null when
# there is none. Handles 'host:port', 'http=..;https=..' and 'socks=..'.
function Get-SystemProxy{
  try{
    $ie = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
    if($ie.ProxyEnable -eq 1 -and $ie.ProxyServer){
      $s = [string]$ie.ProxyServer
      if($s -match '='){
        $m = [regex]::Match($s, '(?:https?|socks)=([^;]+)')
        if($m.Success){ $s = $m.Groups[1].Value.Trim() }
        if($s -match '^socks'){ return 'socks5h://' + ($s -replace '^socks\S*=','') }
      }
      return $s.Trim()
    }
  }catch{}
  return $null
}

# Enumerate direct IP candidates for a host: system DNS + AliDNS (223.5.5.5).
function Get-DirectIps([string]$hostName){
  $list = New-Object System.Collections.Generic.List[string]
  try{
    [Net.Dns]::GetHostAddresses($hostName) | ForEach-Object {
      if(-not $list.Contains($_.IPAddressToString)){ $list.Add($_.IPAddressToString) }
    }
  }catch{}
  try{
    $ali = & nslookup $hostName 223.5.5.5 2>$null | Select-String -Pattern '\b(\d{1,3}\.){3}\d{1,3}\b' | ForEach-Object { $_.Matches[0].Value } | Where-Object { $_ -ne '223.5.5.5' }
    foreach($a in $ali){ if(-not $list.Contains($a)){ $list.Add($a) } }
  }catch{}
  return @($list)
}

# Speed-test the given candidate channels in parallel against a REAL file
# (the biggest one being deployed, so sustained throughput is measured -
# small files give misleading results on CDN edges) and return the fastest
# channels sorted, best first (max 3). Each candidate: @{ Id; Args; Label };
# each result: @{ Id; Speed; Args; Label }.
# -Quiet suppresses all console output (used for mid-download re-probes so
# the progress bar is not broken up by the probe lines).
function Probe-Channels($candidates,[string]$probeUrl,[switch]$Quiet){
  if($null -eq $candidates -or @($candidates).Count -eq 0){ return @() }
  $tmp = Join-Path $Work 'probe'
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  $procs = @()
  $i = 0
  foreach($ch in $candidates){
    $i++
    $outFile = Join-Path $tmp ('spd_' + $i + '.txt')
    $a = @('-s','-L','--max-time','8') + $ch.Args + @('-o','NUL','-w','%{speed_download}',$probeUrl)
    $p = Start-CurlProc $a $outFile
    $procs += @{ Ch = $ch; Proc = $p; Out = $outFile }
  }
  while(@($procs | Where-Object { -not $_.Proc.HasExited }).Count -gt 0){
    if(-not $Quiet){
      Write-Host ("`r  " + (Get-SpinChar) + ' probing channels ...') -NoNewline
    }
    Start-Sleep -Milliseconds 300
  }
  if(-not $Quiet){
    Write-Host ("`r" + (' ' * 30)) -NoNewline
    Write-Host ''
  }
  Start-Sleep -Milliseconds 200
  $okList = New-Object System.Collections.Generic.List[object]
  foreach($pr in $procs){
    $spd = 0.0
    try{
      if(Test-Path -LiteralPath $pr.Out){
        $t = [IO.File]::ReadAllText($pr.Out)
        if($t -match '^(\d+(\.\d+)?)'){ $spd = [double]$Matches[1] }
      }
    }catch{}
    if($spd -gt 0){
      if(-not $Quiet){
        Write-Host ('    ' + $pr.Ch.Id.PadRight(7) + ' ' + $pr.Ch.Label.PadRight(22) + ('{0,9:N0}' -f $spd) + ' B/s') -ForegroundColor Gray
      }
      $okList.Add(@{ Id=$pr.Ch.Id; Speed=$spd; Args=$pr.Ch.Args; Label=$pr.Ch.Label }) | Out-Null
    } else {
      if(-not $Quiet){
        Write-Host ('    ' + $pr.Ch.Id.PadRight(7) + ' ' + $pr.Ch.Label.PadRight(22) + '    FAILED') -ForegroundColor DarkGray
      }
    }
  }
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
  return @($okList | Sort-Object -Property @{Expression={$_.Speed};Descending=$true} | Select-Object -First 3)
}

function Read-ChannelCache{
  try{
    if(Test-Path -LiteralPath $CacheFile){
      $j = Get-Content -LiteralPath $CacheFile -Raw | ConvertFrom-Json
      if($null -ne $j -and $null -ne $j.cdn){ return $j.cdn }
    }
  }catch{}
  return $null
}

function Write-ChannelCache($cdn){
  try{
    $obj = @{ cdn = $cdn }
    $obj | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $CacheFile -Encoding UTF8
  }catch{}
}

function Remove-ChannelCache{
  try{ if(Test-Path -LiteralPath $CacheFile){ Remove-Item -LiteralPath $CacheFile -Force -ErrorAction SilentlyContinue } }catch{}
}

# Incremental-update state: remembers which remote version each addon was
# deployed with (CurseForge fileId / GitHub archive ETag). A later run
# compares and skips everything that is already up to date. Deleting the
# state file forces a full refresh.
function Read-DeployState{
  try{
    if(Test-Path -LiteralPath $StateFile){
      $j = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
      if($null -ne $j){ return $j }
    }
  }catch{}
  return $null
}

function Write-DeployState($obj){
  try{ $obj | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $StateFile -Encoding UTF8 }catch{}
}

# HEAD a codeload archive URL and return its ETag (the commit identifier),
# or $null when the check cannot run.
function Get-CodeloadEtag($url,[string[]]$extraArgs){
  try{
    $hdrFile = Join-Path $Work ('etag_' + [Guid]::NewGuid().ToString('N').Substring(0,8) + '.txt')
    $a = @('-s','-I','-L','-D',$hdrFile,'-o','NUL','--max-time','30')
    if($extraArgs){ $a += $extraArgs }
    $a += $url
    & curl.exe @a 2>$null
    if(Test-Path -LiteralPath $hdrFile){
      $hdr = [IO.File]::ReadAllText($hdrFile)
      $m = [regex]::Match($hdr, '(?im)^\s*etag:\s*"?([^"\r\n]+)"?')
      if($m.Success){ return $m.Groups[1].Value }
    }
  }catch{}
  return $null
}

# Pick the newest file for a project from a parsed /files JSON (page 1).
# Prefers, in order: release channel files matching 1.15.x, then 1.14.x,
# then 1.13.x, then simply the newest release-channel file.
function Select-FileFromJson($j){
  if($null -eq $j -or $null -eq $j.data){ return $null }
  $files = @($j.data)
  if($files.Count -eq 0){ return $null }
  $rel = @($files | Where-Object { $_.releaseType -eq 1 })
  if($rel.Count -eq 0){ $rel = $files }
  foreach($pref in '^1\.15','^1\.14','^1\.13'){
    $hit = @($rel | Where-Object { $f = $_; @($f.gameVersions | Where-Object { $_ -match $pref }).Count -gt 0 } | Select-Object -First 1)
    if($hit.Count -gt 0){ return $hit[0] }
  }
  return ($rel | Select-Object -First 1)
}

# Fetch JSON from the official CurseForge Core API. Returns parsed JSON or
# $null. Network glitches get one quick retry.
function Invoke-CoreJson($path){
  for($attempt = 1; $attempt -le 2; $attempt++){
    try{
      return Invoke-RestMethod -Uri ($CoreBase + '/' + $path) -Headers $CoreHeaders -TimeoutSec 60
    }catch{
      $status = Get-StatusCode $_
      if($status -eq 0 -and $attempt -lt 2){ Start-Sleep -Seconds 2; continue }
      return $null
    }
  }
  return $null
}

# Fetch JSON from the CurseForge website (Schannel). Returns parsed JSON or
# $null. Network glitches get one quick retry; Cloudflare challenges do not
# retry here - the caller goes silent and comes back later.
function Invoke-CfJson($url){
  for($attempt = 1; $attempt -le 2; $attempt++){
    try{
      return Invoke-RestMethod -Uri $url -Headers $CfHeaders -TimeoutSec 60
    }catch{
      $status = Get-StatusCode $_
      if($status -eq 0 -and $attempt -lt 2){ Start-Sleep -Seconds 2; continue }
      return $null
    }
  }
  return $null
}

# Follow the CurseForge download redirect once (Schannel) and return the
# direct ForgeCDN link.
function Resolve-CdnUrl($downloadUrl){
  for($attempt = 1; $attempt -le 2; $attempt++){
    try{
      $req = [Net.HttpWebRequest]::Create($downloadUrl)
      $req.AllowAutoRedirect = $false
      $req.UserAgent = $Ua
      $req.Referer = $Referer
      $req.Accept = 'application/json'
      $req.Timeout = 60000
      $resp = $req.GetResponse()
      $loc = $resp.Headers['Location']
      $resp.Close()
      if($loc){ return $loc }
      return $downloadUrl
    }catch{
      $status = Get-StatusCode $_
      if($status -eq 0 -and $attempt -lt 2){ Start-Sleep -Seconds 2; continue }
      return $null
    }
  }
  return $null
}

# Same selection as Select-FileFromJson, but paging through newest files
# (max 200) - used as serial fallback for projects page 1 did not resolve.
function Resolve-ProjectCore($projId){
  $all = New-Object System.Collections.Generic.List[object]
  for($page = 0; $page -lt 4; $page++){
    $j = Invoke-CoreJson ('mods/' + $projId + '/files?pageSize=50&index=' + $page)
    if($null -eq $j -or $null -eq $j.data){ return $null }
    $files = @($j.data)
    if($files.Count -eq 0){ break }
    foreach($f in $files){ $all.Add($f) | Out-Null }
    $rel = @($files | Where-Object { $_.releaseType -eq 1 })
    $hit = @($rel | Where-Object { $f = $_; @($f.gameVersions | Where-Object { $_ -match '^1\.15' }).Count -gt 0 } | Select-Object -First 1)
    if($hit.Count -gt 0){ return $hit[0] }
    if($files.Count -lt 50){ break }
    Start-Sleep -Milliseconds 50
  }
  if($all.Count -eq 0){ return $null }
  $rel = @($all | Where-Object { $_.releaseType -eq 1 })
  if($rel.Count -eq 0){ $rel = $all.ToArray() }
  foreach($pref in '^1\.15','^1\.14','^1\.13'){
    $hit = @($rel | Where-Object { $f = $_; @($f.gameVersions | Where-Object { $_ -match $pref }).Count -gt 0 } | Sort-Object -Property @{Expression={$_.fileDate};Descending=$true} | Select-Object -First 1)
    if($hit.Count -gt 0){ return $hit[0] }
  }
  return ($rel | Sort-Object -Property @{Expression={$_.fileDate};Descending=$true} | Select-Object -First 1)
}

# Same selection, but using the Cloudflare-protected website API (fallback).
function Resolve-Project($projId){
  $j = Invoke-CfJson ($ApiBase + '/mods/' + $projId + '/files?pageSize=100')
  if($null -eq $j -or $null -eq $j.data){ return $null }
  $files = @($j.data)
  if($files.Count -eq 0){ return $null }
  $rel = @($files | Where-Object { $_.releaseType -eq 1 })
  if($rel.Count -eq 0){ $rel = $files }
  foreach($pref in '^1\.15','^1\.14','^1\.13'){
    $hit = $rel | Where-Object { $f = $_; @($f.gameVersions | Where-Object { $_ -match $pref }).Count -gt 0 } | Select-Object -First 1
    if($hit){ return $hit }
  }
  return ($rel | Select-Object -First 1)
}

# True when the file starts with the ZIP magic bytes 'PK'.
function Test-ZipFile($path){
  try{
    $fs = [IO.File]::OpenRead($path)
    if($fs.Length -lt 4){ $fs.Close(); return $false }
    $b = New-Object byte[] 4
    $fs.Read($b, 0, 4) | Out-Null
    $fs.Close()
    return ($b[0] -eq 0x50 -and $b[1] -eq 0x4B)
  }catch{ return $false }
}

function Invoke-CurlDownload($url,$outFile,$timeoutSec,[string[]]$extraArgs){
  $a = @('-s','-L','--fail','--retry','3','--retry-delay','2','--connect-timeout','15','--max-time',$timeoutSec,'-A',$Ua,'-e',$Referer)
  if($extraArgs){ $a += $extraArgs }
  $a += @('-o',$outFile,$url)
  & curl.exe @a
  return ($LASTEXITCODE -eq 0)
}

# ----------------------- integrity & planning helpers (v4) -------------------
# Symbols used by the plan list. ASCII only, so they render on any console
# (double-clicking the .cmd runs in a raster/legacy-code-page window where
# non-ASCII glyphs would not display). Color carries the meaning too.
$SymOk   = '+'      # up to date (md5 ok)
$SymBad  = '!'      # damaged - will re-download
$SymDl   = '*'      # will download (new or update)
$SymDel  = '-'      # no longer in list - will delete
$SymFail = 'x'      # resolve failed - left as is

# Normalise a stored CurseForge entry. Legacy entries were plain strings
# (fileId only) -> no md5/folders, so they must be re-downloaded once.
function Read-CfStateEntry($raw){
  if($null -eq $raw){ return @{ FileId=''; Md5=''; Folders=@() } }
  if($raw -is [string]){ return @{ FileId=[string]$raw; Md5=''; Folders=@() } }
  return @{
    FileId  = [string]$raw.fileId
    Md5     = [string]$raw.md5
    Folders = @(@($raw.folders) | Where-Object { $_ })
  }
}

# Same for a stored SoD entry (keyed by the addon folder name; legacy = etag string).
function Read-SodStateEntry($raw){
  if($null -eq $raw){ return @{ Etag=''; Md5=''; Folders=@() } }
  if($raw -is [string]){ return @{ Etag=[string]$raw; Md5=''; Folders=@() } }
  return @{
    Etag    = [string]$raw.etag
    Md5     = [string]$raw.md5
    Folders = @(@($raw.folders) | Where-Object { $_ })
  }
}

# Aggregate MD5 of one managed addon: every file under its recorded folders
# (relative paths included) is hashed; the concatenation is hashed again.
# Returns '' when no file could be read (missing/empty folders).
$Md5WorkerScript = {
  param($deploy,$folders)
  $h = [System.Security.Cryptography.MD5]::Create()
  $sb = New-Object System.Text.StringBuilder
  $list = New-Object System.Collections.Generic.List[string]
  try{
    foreach($fd in $folders){
      $d = Join-Path $deploy $fd
      if(Test-Path -LiteralPath $d){
        @(Get-ChildItem -LiteralPath $d -Recurse -File -ErrorAction SilentlyContinue) | ForEach-Object { $list.Add($_.FullName) }
      }
    }
    $sorted = @($list | Sort-Object)
    if($sorted.Count -eq 0){ return '' }
    foreach($p in $sorted){
      $rel = $p.Substring($deploy.Length).TrimStart('\')
      $fs = [IO.File]::OpenRead($p)
      try{ $fh = $h.ComputeHash($fs) } finally { $fs.Close() }
      [void]$sb.Append($rel).Append('|').Append([BitConverter]::ToString($fh).Replace('-','')).Append(';')
    }
    $final = $h.ComputeHash([Text.Encoding]::UTF8.GetBytes($sb.ToString()))
    return [BitConverter]::ToString($final).Replace('-','')
  }catch{
    return ''
  }finally{
    $h.Dispose()
  }
}

# Compute the aggregate md5 of a list of entries in parallel (cores - 2 runspaces).
# $items: @{ Key; Folders }. Returns a hashtable Key -> md5 ('' on failure).
function Invoke-Md5Parallel($items){
  $result = @{}
  if($items.Count -eq 0){ return $result }
  $workers = [Math]::Max(1, [Environment]::ProcessorCount - 2)
  $pool = [runspacefactory]::CreateRunspacePool(1, $workers)
  $pool.Open()
  $jobs = New-Object System.Collections.Generic.List[object]
  foreach($it in $items){
    $ps = [powershell]::Create()
    $ps.RunspacePool = $pool
    [void]$ps.AddScript($Md5WorkerScript).AddArgument($DeployDir).AddArgument([string[]]@($it.Folders))
    $jobs.Add(@{ Key=$it.Key; PS=$ps; Async=$ps.BeginInvoke() }) | Out-Null
  }
  while($jobs.Count -gt 0){
    $doneArr = @($jobs | Where-Object { $_.Async.IsCompleted })
    foreach($j in $doneArr){
      try{ $result[$j.Key] = [string]$j.PS.EndInvoke($j.Async) }catch{ $result[$j.Key] = '' }
      $j.PS.Dispose()
      $jobs.Remove($j) | Out-Null
    }
    if($jobs.Count -gt 0){ Start-Sleep -Milliseconds 150 }
  }
  $pool.Close(); $pool.Dispose()
  return $result
}

# Delete the recorded folders of one managed entry from the deploy directory.
function Remove-EntryFolders($folders){
  foreach($fd in $folders){
    $d = Join-Path $DeployDir $fd
    if($fd -and (Test-Path -LiteralPath $d)){
      Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

# ------------------------------ pre-checks ----------------------------------
Init-ConsoleMode
Write-Host ''
Write-Host $HLine -ForegroundColor Cyan
Write-Host ('   World of Warcraft Classic Era - AddOns one-click deploy') -ForegroundColor Cyan
Write-Host $HLine -ForegroundColor Cyan
Write-Host (Truncate-Text ('  Target directory : ' + $DeployDir) $ConWidth)
Write-Host ('  CurseForge addons: ' + $Projects.Count + ' projects')
Write-Host ('  Own SoD addons   : ' + $SodRepos.Count + ' repositories')
Write-Host ''

$checkDir = $ScriptDir
if(Test-Path -LiteralPath $DeployDir){ $checkDir = $DeployDir }
if(-not (Test-Writable $checkDir)){
  $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  if($principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)){
    Write-Host '  ERROR: target directory is not writable even as administrator.' -ForegroundColor Red
    Restore-ConsoleMode
    Read-Host '  Press Enter to exit' | Out-Null
    exit 1
  }
  Write-Host '  Target directory needs administrator permission - requesting elevation...' -ForegroundColor Yellow
  Restore-ConsoleMode
  Start-Process -FilePath $Self -Verb RunAs | Out-Null
  exit 0
}
New-Item -ItemType Directory -Force -Path $DeployDir | Out-Null

$wow = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^Wow' })
if($wow.Count -gt 0){
  Write-Host (Truncate-Text '  WARNING: World of Warcraft appears to be running. Files in use may fail to update.' $ConWidth) -ForegroundColor Yellow
  Write-Host '           It is recommended to close the game first.' -ForegroundColor Yellow
}

$Work = Join-Path $env:TEMP ('AddonDeploy_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $Work | Out-Null
$DlDir = Join-Path $Work 'downloads'
New-Item -ItemType Directory -Force -Path $DlDir | Out-Null

# --------------------- phase 1: resolve latest files (parallel) -------------
Write-Host ''
Write-Host ('[1/5] Resolving latest Classic Era files on CurseForge (parallel x' + $Concurrency + ') ...') -ForegroundColor Green
$resolved     = New-Object System.Collections.Generic.List[object]
$resolveFail  = New-Object System.Collections.Generic.List[string]
$coreFail     = New-Object System.Collections.Generic.List[object]

# Phase 1a: fire off one /files page-1 request per project, x$Concurrency.
$apiQueue = New-Object System.Collections.Generic.Queue[object]
foreach($p in $Projects){
  $jsonPath = Join-Path $Work ('api_' + $p.Id + '.json')
  $apiQueue.Enqueue(@{
    Name = $p.Name
    Id   = $p.Id
    Json = $jsonPath
    Url  = ($CoreBase + '/mods/' + $p.Id + '/files?pageSize=50&index=0')
  }) | Out-Null
}
$apiActive = @{}
$apiDone = 0
while($apiQueue.Count -gt 0 -or $apiActive.Count -gt 0){
  while($apiActive.Count -lt $Concurrency -and $apiQueue.Count -gt 0){
    $it = $apiQueue.Dequeue()
    $curlArgs = @('-s','--fail','--max-time','60','--retry','2','--retry-delay','2')
    if($ChProxy){ $curlArgs += @('--proxy',$ChProxy) }
    $curlArgs += @('-H',('x-api-key: ' + $CfApiKey),'-H','Accept: application/json','-o',$it.Json,$it.Url)
    $proc = Start-CurlProc $curlArgs $null
    $apiActive[$it.Name] = @{ Proc = $proc; Item = $it }
  }
  Start-Sleep -Milliseconds 300
  foreach($key in @($apiActive.Keys)){
    $a = $apiActive[$key]
    if($a.Proc.HasExited){
      $apiDone++
      Show-Bar ($apiDone / $Projects.Count) ('resolving ' + $a.Item.Name + ' (' + $apiDone + '/' + $Projects.Count + ')')
      $it = $a.Item
      $ok = ($a.Proc.ExitCode -eq 0) -and (Test-Path -LiteralPath $it.Json) -and ((Get-Item -LiteralPath $it.Json).Length -gt 10)
      $file = $null
      if($ok){
        try{
          $j = [IO.File]::ReadAllText($it.Json) | ConvertFrom-Json
          $file = Select-FileFromJson $j
        }catch{}
      }
      if($null -ne $file){
        $dlUrl  = [string]$file.downloadUrl
        $isCore = $false
        if([string]::IsNullOrEmpty($dlUrl)){
          $dlUrl  = $CoreBase + '/mods/' + $it.Id + '/files/' + $file.id + '/download'
          $isCore = $true
        }
        $resolved.Add(@{
          Name    = $it.Name
          ProjId  = $it.Id
          FileId  = $file.id
          ZipName = [string]$file.fileName
          Len     = [long]$file.fileLength
          Url     = $dlUrl
          Core    = $isCore
          DlUrl   = ''
          ZipPath = Join-Path $DlDir ([string]$file.fileName)
          Tries   = 0
        }) | Out-Null
      } else {
        $coreFail.Add($it) | Out-Null
      }
      $apiActive.Remove($key)
    }
  }
}
Finish-Line

# Phase 1b: serial fallback (paging) for the projects page 1 did not resolve.
if($coreFail.Count -gt 0){
  Show-Info ('Page 1 missed ' + $coreFail.Count + ' projects - retrying with paging ...') 'Yellow'
  $pending = $coreFail.ToArray()
  $stillFail = New-Object System.Collections.Generic.List[object]
  $i = 0
  foreach($p in $pending){
    $i++
    Show-Bar ($i / $pending.Count) ('resolving (paging) ' + $p.Name + ' (' + $i + '/' + $pending.Count + ')')
    $file = Resolve-ProjectCore $p.Id
    if($null -eq $file){
      $stillFail.Add($p) | Out-Null
    } else {
      $dlUrl  = [string]$file.downloadUrl
      $isCore = $false
      if([string]::IsNullOrEmpty($dlUrl)){
        $dlUrl  = $CoreBase + '/mods/' + $p.Id + '/files/' + $file.id + '/download'
        $isCore = $true
      }
      $resolved.Add(@{
        Name    = $p.Name
        ProjId  = $p.Id
        FileId  = $file.id
        ZipName = [string]$file.fileName
        Len     = [long]$file.fileLength
        Url     = $dlUrl
        Core    = $isCore
        DlUrl   = ''
        ZipPath = Join-Path $DlDir ([string]$file.fileName)
        Tries   = 0
      }) | Out-Null
    }
    Start-Sleep -Milliseconds 50
  }
  Finish-Line
  $pending2 = $stillFail.ToArray()
  # Fallback: projects the Core API could not serve are scraped from the
  # Cloudflare-protected website instead (slow but reliable).
  if($pending2.Count -gt 0){
    Show-Info ('Core API unavailable for ' + $pending2.Count + ' projects - falling back to website scraping ...') 'Yellow'
    for($pass = 1; $pass -le 2 -and $pending2.Count -gt 0; $pass++){
      if($pass -eq 2){
        Show-Info ('Second pass: retrying ' + $pending2.Count + ' blocked projects after a ' + $SilenceSec + 's silence ...') 'Yellow'
        Wait-Spin $SilenceSec 'cooling down (Cloudflare)'
      }
      $stillFail2 = New-Object System.Collections.Generic.List[object]
      $consecFail = 0
      $i = 0
      foreach($p in $pending2){
        $i++
        $label = 'resolving ' + $p.Name + ' (' + $i + '/' + $pending2.Count + ')'
        if($pass -eq 2){ $label += ' [retry]' }
        Show-Bar ($i / $pending2.Count) $label
        $file = Resolve-Project $p.Id
        if($null -eq $file){
          $consecFail++
          if($pass -eq 1){ $stillFail2.Add($p) | Out-Null } else { $resolveFail.Add($p.Name) | Out-Null }
          if($consecFail -eq 3 -and $i -lt $pending2.Count){
            Show-Info ('Cloudflare is challenging us - going silent for ' + $SilenceSec + 's ...') 'Yellow'
            Wait-Spin $SilenceSec 'cooling down (Cloudflare)'
            $consecFail = 0
          }
        } else {
          $consecFail = 0
          $resolved.Add(@{
            Name    = $p.Name
            ProjId  = $p.Id
            FileId  = $file.id
            ZipName = [string]$file.fileName
            Len     = [long]$file.fileLength
            Url     = $ApiBase + '/mods/' + $p.Id + '/files/' + $file.id + '/download'
            Core    = $false
            DlUrl   = ''
            ZipPath = Join-Path $DlDir ([string]$file.fileName)
            Tries   = 0
          }) | Out-Null
        }
        Start-Sleep -Milliseconds (Get-Random -Minimum 600 -Maximum 1200)
      }
      Finish-Line
      $pending2 = $stillFail2.ToArray()
    }
  }
}

# ============= integrity planning (v4): classify, verify, clean ==============
# Three outcomes after resolve:
#   download  - not deployed yet / remote version moved / state has no md5
#               (legacy state entries are re-downloaded once, md5 rebuilt)
#   verify    - remote version matches state: check local md5 (cores - 2 threads)
#   delete    - entry tracked in state but no longer in the download lists
Write-Host ''
Write-Host ('  Classifying ' + ($Projects.Count + $SodRepos.Count) + ' managed addons ...') -ForegroundColor Green
$deployState = Read-DeployState

# Remote SoD versions (codeload ETag) are resolved up front so the same
# download/verify/delete decision can be made for GitHub-sourced addons.
$sodRemote = @{}
if($SodRepos.Count -gt 0){
  $si = 0
  foreach($s in $SodRepos){
    $si++
    Show-Bar ($si / $SodRepos.Count) ('HEAD codeload ' + $s.Folder + ' (' + $si + '/' + $SodRepos.Count + ')')
    $sodRemote[$s.Folder] = Get-CodeloadEtag ('https://codeload.github.com/' + $GhUser + '/' + $s.Repo + '/zip/refs/heads/main') @()
  }
  Finish-Line
}

$currentCf  = @{}; foreach($p in $Projects){ $currentCf[$p.Name] = $true }
$currentSod = @{}; foreach($s in $SodRepos){ $currentSod[$s.Folder] = $true }

$toVerify     = New-Object System.Collections.Generic.List[object] # @{Kind;Key;Folders;Md5;Ref}
$toDownloadCf = New-Object System.Collections.Generic.List[object]
$cfDelete     = New-Object System.Collections.Generic.List[object] # @{Kind;Key;Folders}
$sodDelete    = New-Object System.Collections.Generic.List[object]
$sodDl        = @{}   # SoD folders that must be (re)downloaded
$sodEtagPlan  = @{}   # SoD folder -> remote etag to record after a fresh deploy
$cfSkipOk     = @{}   # CF names verified intact (green check)
$sodSkipOk    = @{}   # SoD folders verified intact

# ---- CurseForge entries (order of $resolved) -------------------------------
foreach($r in $resolved){
  $raw = $null
  if($deployState -and $deployState.cf){ $raw = $deployState.cf.($r.Name) }
  $e = Read-CfStateEntry $raw
  if($e.FileId -ne '' -and $e.FileId -eq ([string]$r.FileId) -and $e.Md5){
    $r.Plan = 'verify'
    $toVerify.Add(@{ Kind='cf'; Key=$r.Name; Folders=$e.Folders; Md5=$e.Md5; Ref=$r }) | Out-Null
  } else {
    $r.Plan = 'download'
    $toDownloadCf.Add($r) | Out-Null
  }
}
# CF entries tracked in state whose project left the list.
if($deployState -and $deployState.cf){
  foreach($p in $deployState.cf.PSObject.Properties){
    if(-not $currentCf.ContainsKey($p.Name)){
      $e = Read-CfStateEntry $p.Value
      $cfDelete.Add(@{ Kind='cf'; Key=$p.Name; Folders=$e.Folders }) | Out-Null
    }
  }
}

# ---- SoD entries ------------------------------------------------------------
foreach($s in $SodRepos){
  $raw = $null
  if($deployState -and $deployState.sod){ $raw = $deployState.sod.($s.Folder) }
  $e = Read-SodStateEntry $raw
  $etag = $sodRemote[$s.Folder]
  $sodEtagPlan[$s.Folder] = $etag
  if($etag -and $e.Etag -eq $etag -and $e.Md5){
    $toVerify.Add(@{ Kind='sod'; Key=$s.Folder; Folders=$e.Folders; Md5=$e.Md5; Folder=$s.Folder }) | Out-Null
  } else {
    $sodDl[$s.Folder] = $true
  }
}
if($deployState -and $deployState.sod){
  foreach($p in $deployState.sod.PSObject.Properties){
    if(-not $currentSod.ContainsKey($p.Name)){
      $e = Read-SodStateEntry $p.Value
      $sodDelete.Add(@{ Kind='sod'; Key=$p.Name; Folders=$e.Folders }) | Out-Null
    }
  }
}

# ---- integrity check of the verify set (parallel md5, cores - 2) ------------
$md5Res = @{}
if($toVerify.Count -gt 0){
  Write-Host ('  Verifying ' + $toVerify.Count + ' up-to-date addons (md5, x' + [Math]::Max(1, [Environment]::ProcessorCount - 2) + ' threads) ...') -ForegroundColor Green
  $md5Res = Invoke-Md5Parallel $toVerify
}
$damaged = New-Object System.Collections.Generic.List[object]  # @{Kind;Key;Folders}
foreach($v in $toVerify){
  $cur = ''
  if($md5Res.ContainsKey($v.Key)){ $cur = $md5Res[$v.Key] }
  if($cur -ne '' -and $cur -eq $v.Md5){
    if($v.Kind -eq 'cf'){
      $v.Ref.Plan = 'skip'
      $cfSkipOk[$v.Key] = $true
    } else {
      $sodSkipOk[$v.Key] = $true
    }
  } else {
    $damaged.Add(@{ Kind=$v.Kind; Key=$v.Key; Folders=$v.Folders }) | Out-Null
    if($v.Kind -eq 'cf'){
      $v.Ref.Plan = 'download'
      $v.Ref.Damaged = $true
      $toDownloadCf.Add($v.Ref) | Out-Null
    } else {
      $sodDl[$v.Key] = $true
    }
  }
}

# ---- plan list ---------------------------------------------------------------
$dropCf  = @{}   # state keys to remove at persist time
$dropSod = @{}
Write-Host ''
Write-Host '  Plan: (* will download, + up to date, ! damaged, x resolve failed, - delete)' -ForegroundColor Gray
# Shorten a long file name in the middle so the plan row stays on one line.
function Shorten-Mid([string]$s,[int]$max){
  if($s.Length -le $max){ return $s }
  return $s.Substring(0, [Math]::Max(8, $max - 14)) + '...' + $s.Substring($s.Length - 11)
}
function Add-PlanLine($sym,$color,$name,$state,$file){
  $p = ' '
  if($sym){ $p = $sym + ' ' }
  $line = '    ' + $p + $name.PadRight(21)
  if($file){ $line += '(' + (Shorten-Mid $file 30) + ') ' }
  $line += $state
  Write-Host (Truncate-Text $line $ConWidth) -ForegroundColor $color
}
foreach($r in $resolved){
  if($r.Plan -eq 'skip'){
    Add-PlanLine $SymOk 'Green' $r.Name 'up to date (md5 ok)' ([string]$r.ZipName)
  } elseif($r.Damaged){
    Add-PlanLine $SymBad 'Yellow' $r.Name 'damaged - re-download' ([string]$r.ZipName)
  } else {
    Add-PlanLine $SymDl 'Gray' $r.Name 'will download' ([string]$r.ZipName)
  }
}
foreach($d in $cfDelete){ Add-PlanLine $SymDel 'Red' $d.Key 'no longer in list' ''; $dropCf[$d.Key] = $true }
foreach($s in $SodRepos){
  # GitHub side has no zip name: show the codeload commit hash (first 7 chars).
  $gh = ''
  $et = $sodRemote[$s.Folder]
  if(-not $et){ $et = $sodEtagPlan[$s.Folder] }
  if($et){ $gh = $et.Substring(0, [Math]::Min(7, $et.Length)) }
  if($sodSkipOk.ContainsKey($s.Folder)){
    Add-PlanLine $SymOk 'Green' $s.Folder 'up to date (md5 ok)' $gh
  } elseif($damaged.Key -contains $s.Folder){
    Add-PlanLine $SymBad 'Yellow' $s.Folder 'damaged - re-download' $gh
  } else {
    Add-PlanLine $SymDl 'Gray' $s.Folder 'will download' $gh
  }
}
foreach($d in $sodDelete){ Add-PlanLine $SymDel 'Red' $d.Key 'no longer in list' ''; $dropSod[$d.Key] = $true }
# Entries that could not even be resolved keep their current state untouched.
foreach($f in $resolveFail){
  Add-PlanLine $SymFail 'Red' $f 'resolve failed' ''
}

# ---- execute deletes (before any download, per requirement) -----------------
$toDel = New-Object System.Collections.Generic.List[object]
foreach($d in $cfDelete){ $toDel.Add($d) | Out-Null }
foreach($d in $sodDelete){ $toDel.Add($d) | Out-Null }
foreach($d in $damaged){  $toDel.Add($d) | Out-Null }
if($toDel.Count -gt 0){
  Write-Host ('  Deleting ' + $toDel.Count + ' stale/damaged addon folder(s) ...') -ForegroundColor Gray
  foreach($d in $toDel){
    $folders = @($d.Folders)
    if($folders.Count -eq 0){ $folders = @($d.Key) }   # legacy entry: best effort by name
    Remove-EntryFolders $folders
  }
  Write-Host '  Deleted.' -ForegroundColor Gray
}

# ------------------ phase 2: select fastest download channel ---------------
Write-Host ''
Write-Host '[2/5] Selecting fastest download channel ...' -ForegroundColor Green
$ChProxy = $null
$ChIp    = $null
$ChannelPool = @()
$PoolIdx = 0

# The system proxy is a DYNAMIC dependency: the user may turn it off at any
# time while the registry entry stays behind. It is therefore NEVER cached -
# it is re-validated on every run (a dead proxy simply fails the probe).
# Only direct-IP results may be cached (CDN topology is stable within the
# TTL). Legacy proxy-mode caches are ignored.
$sysProxyNow = Get-SystemProxy
$cache   = Read-ChannelCache
$cacheValid = $false
if($null -ne $cache -and $cache.mode -eq 'ip' -and $cache.ip -and $cache.ts){
  try{
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if(($now - [int64]$cache.ts) -lt $CacheTtl){ $cacheValid = $true }
  }catch{}
}

# Probe with the BIGGEST resolved file - small files give misleading
# throughput on CDN edges (fast start, slow sustained), while the whole
# download experience depends on sustained speed.
$probeR = @($resolved | Where-Object { ([string]$_.Url).StartsWith('https://edge.forgecdn.net') } | Sort-Object -Property @{Expression={$_.Len};Descending=$true} | Select-Object -First 1)
if($probeR.Count -eq 0){ $probeR = @($resolved | Where-Object { $_.Url -ne '' } | Sort-Object -Property @{Expression={$_.Len};Descending=$true} | Select-Object -First 1) }
$pUrl = ''
$ReselectUrl = ''
if($probeR.Count -gt 0){
  $pUrl = [string]$probeR[0].Url
  if($pUrl -notmatch 'api-key='){ $pUrl += '?api-key=' + $CdnToken }
  $ReselectUrl = $pUrl
}

$best = @()
if($cacheValid -and -not $sysProxyNow){
  # No proxy + valid direct-IP cache: use it without probing.
  $ChIp = [string]$cache.ip
  Write-Host ('  Using cached channel: direct IP ' + $ChIp + ' (' + ('{0:N0}' -f [double]$cache.speed) + ' B/s)') -ForegroundColor Green
} elseif($pUrl -ne ''){
  # Probe now. The proxy is always re-tested (it may be off even though the
  # registry still lists it). With a valid IP cache only [proxy + cached IP]
  # are tested; otherwise the full IP list is enumerated.
  Write-Host '  Probing channels (8s each, parallel):' -ForegroundColor Gray
  $candidates = @()
  $idx = 0
  if($sysProxyNow){ $candidates += @{ Id='PROXY'; Args=@('--proxy',$sysProxyNow); Label=$sysProxyNow } }
  if($cacheValid){
    $candidates += @{ Id='CIP'; Args=@('--resolve',('edge.forgecdn.net:443:' + $cache.ip)); Label=('cached ' + $cache.ip) }
  } else {
    foreach($ip in (Get-DirectIps 'edge.forgecdn.net')){
      $idx++
      $candidates += @{ Id=('IP'+$idx); Args=@('--resolve',('edge.forgecdn.net:443:'+$ip)); Label=$ip }
    }
  }
  $best = @(Probe-Channels $candidates $pUrl)
  if($best.Count -gt 0){
    if($best[0].Id -eq 'PROXY'){
      $ChProxy = $best[0].Args[1]
      Write-Host ('  -> Using system proxy: ' + $ChProxy + ' (' + ('{0:N0}' -f $best[0].Speed) + ' B/s)') -ForegroundColor Green
      # Proxy results are never cached; drop any stale IP cache so a later
      # run without the proxy performs a fresh full probe.
      Remove-ChannelCache
    } else {
      if($best[0].Id -eq 'CIP'){
        $ChIp = [string]$cache.ip
      } else {
        $ChIp = ($best[0].Args[1] -split ':')[-1]
      }
      Write-Host ('  -> Using direct IP: ' + $ChIp + ' (' + ('{0:N0}' -f $best[0].Speed) + ' B/s)') -ForegroundColor Green
      $cdn = @{
        mode  = 'ip'
        ip    = $ChIp
        speed = $best[0].Speed
        ts    = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
      }
      Write-ChannelCache $cdn
    }
    # Channel pool: keep only channels in the same league as the fastest
    # one (>= 50% of its speed, at least 500 KB/s). Rotating through a
    # pool that mixes 10 MB/s and 40 KB/s channels would stall half the
    # downloads; when everything is slow (no proxy), the top channels are
    # still rotated to spread the risk.
    $fastest = [double]$best[0].Speed
    $threshold = [Math]::Max(500000.0, $fastest * 0.5)
    foreach($b in $best){
      if([double]$b.Speed -ge $threshold){ $ChannelPool += @{ Id=$b.Id; Args=$b.Args; Fails=0 } }
    }
    if($ChannelPool.Count -eq 0){ $ChannelPool += @{ Id=$best[0].Id; Args=$best[0].Args; Fails=0 } }
    $PoolIdx = 0
  } else {
    Write-Host '  All channels failed - using the default direct connection.' -ForegroundColor Yellow
    Remove-ChannelCache
  }
} else {
  Write-Host '  Nothing to probe - using the default direct connection.' -ForegroundColor Yellow
}

# Rotate through the channel pool; returns the curl args for the next
# download. Falls back to a plain direct connection when the pool is empty.
function Get-NextChannelArgs{
  if($ChannelPool.Count -eq 0){ return @() }
  $script:PoolIdx = $script:PoolIdx + 1
  $ch = $ChannelPool[($script:PoolIdx) % $ChannelPool.Count]
  if($null -eq $ch){ return @() }
  return @($ch.Args)
}

# ------------------- phase 3: locate CDN links + download -------------------
$SilenceSec = $CdnSilenceSec
Write-Host ''
Write-Host ('[3/5] Downloading from CurseForge (parallel x' + $Concurrency + ') ...') -ForegroundColor Green

# Direct ForgeCDN links from the Core API need no extra lookup.
foreach($r in $resolved){
  if($r.DlUrl -eq '' -and $r.Core -eq $false -and ([string]$r.Url).StartsWith('https://edge.forgecdn.net')){
    $r.DlUrl = $r.Url
  }
}
$cdnPending = @($resolved | Where-Object { $_.DlUrl -eq '' })
if($cdnPending.Count -gt 0){
  for($pass = 1; $pass -le 2 -and $cdnPending.Count -gt 0; $pass++){
    if($pass -eq 2){
      Show-Info ('Second pass: retrying ' + $cdnPending.Count + ' CDN links after a ' + $SilenceSec + 's silence ...') 'Yellow'
      Wait-Spin $SilenceSec 'cooling down (CDN)'
    }
    $stillFail  = New-Object System.Collections.Generic.List[object]
    $consecFail = 0
    $i = 0
    foreach($r in $cdnPending){
      $i++
      Show-Bar ($i / $cdnPending.Count) ('locating CDN link ' + $r.Name + ' (' + $i + '/' + $cdnPending.Count + ')')
      $cdn = $null
      if($r.Core -eq $true){
        try{
            $resp = Invoke-RestMethod -Uri $r.Url -Headers $CoreHeaders -TimeoutSec 60
            if($resp -is [string]){ $cdn = [string]$resp }
            elseif($null -ne $resp.data){
              if($resp.data -is [string]){ $cdn = [string]$resp.data }
              elseif($null -ne $resp.data.downloadUrl){ $cdn = [string]$resp.data.downloadUrl }
            }
          }catch{ $cdn = $null }
        if([string]::IsNullOrEmpty($cdn)){ $cdn = $null }
      } else {
        $cdn = Resolve-CdnUrl $r.Url
      }
      if($cdn){
        $r.DlUrl = $cdn
        $consecFail = 0
      } else {
        $consecFail++
        if($pass -eq 1){ $stillFail.Add($r) | Out-Null } else { $dlFailedEarly = $true }
        if($consecFail -eq 3 -and $i -lt $cdnPending.Count){
          Show-Info ('CDN lookup keeps failing - going silent for ' + $CdnSilenceSec + 's ...') 'Yellow'
          Wait-Spin $SilenceSec 'cooling down (CDN)'
          $consecFail = 0
        }
      }
      Start-Sleep -Milliseconds (Get-Random -Minimum 50 -Maximum 150)
    }
    Finish-Line
    $cdnPending = $stillFail.ToArray()
  }
} else {
  Write-Host '  All CDN links provided directly by the Core API.' -ForegroundColor Gray
}

# ForgeCDN requires the public token query parameter on direct links.
foreach($r in $resolved){
  if(([string]$r.DlUrl) -match '^https://edge\.forgecdn\.net' -and ([string]$r.DlUrl) -notmatch 'api-key='){
    $r.DlUrl = ([string]$r.DlUrl) + '?api-key=' + $CdnToken
  }
}
# Download set = entries the integrity plan marked 'download' (new / updated /
# damaged). 'skip' entries were md5-verified intact above.
$cfSkip = $cfSkipOk.Count
if($cfSkip -gt 0){
  Write-Host ('  ' + $cfSkip + ' of ' + $resolved.Count + ' CurseForge addons verified up to date (md5 ok, skipped).') -ForegroundColor Gray
}
$totalBytes = [long]0
foreach($r in $resolved){ if($r.Plan -eq 'download'){ $totalBytes += $r.Len } }
if($totalBytes -le 0){ $totalBytes = [long]1 }

$queue = New-Object System.Collections.Generic.Queue[object]
$dlFailed  = New-Object System.Collections.Generic.List[string]
foreach($r in $resolved){
  if($r.Plan -ne 'download'){ continue }
  if($r.DlUrl){
    $queue.Enqueue($r)
  } else { $dlFailed.Add($r.Name + ' (no CDN link)') | Out-Null }
}
$active    = @{}
$doneBytes = [long]0
$doneCount = 0
$gaveUp    = New-Object System.Collections.Generic.List[object]
$consecDlFail = 0
# Slow-download guard: a file averaging below $MinDlSpeed after
# $SlowCheckSec is killed and retried on another channel; after
# $ReselectThresh slow kills the CDN channels are re-probed from scratch.
$MinDlSpeed     = 50KB
$SlowCheckSec   = 10
$ReselectThresh = 3
$ReselectCooldown = 60
$slowKills      = 0
$lastReselect   = (Get-Date).AddSeconds(-999)
# Smoothed overall throughput for the progress bar.
$emaSpeed   = 0.0
$lastBytes  = [long]0
$lastSpeedT = Get-Date

while($queue.Count -gt 0 -or $active.Count -gt 0){
  while($active.Count -lt $Concurrency -and $queue.Count -gt 0){
    $it = $queue.Dequeue()
    $curlArgs = @('-s','-L','--fail','--retry','2','--retry-delay','3','--connect-timeout','30','--max-time','7200','-A',$Ua,'-o',$it.ZipPath) + (Get-NextChannelArgs) + @($it.DlUrl)
    $proc = Start-CurlProc $curlArgs $null
    $active[$it.ZipPath] = @{ Proc = $proc; Item = $it; Start = Get-Date; LastSize = [long]0; LastT = Get-Date }
    if($queue.Count -gt 0){ Start-Sleep -Milliseconds (Get-Random -Minimum 50 -Maximum 150) }
  }
  Start-Sleep -Milliseconds 400
  # Slow-download guard: kill stalled transfers and retry on another channel.
  # The check uses the RECENT increment (bytes since the last poll), not the
  # lifetime average - a file that started fast and then stalled would fool
  # an average-based check.
  foreach($key in @($active.Keys)){
    $a = $active[$key]
    if(-not $a.Proc.HasExited){
      $elapsed = ((Get-Date) - $a.Start).TotalSeconds
      if($elapsed -gt $SlowCheckSec){
        $sz = [long]0
        if(Test-Path -LiteralPath $key){ $sz = (Get-Item -LiteralPath $key).Length }
        $dt = ((Get-Date) - $a.LastT).TotalSeconds
        if($dt -ge 3){
          $inst = ($sz - $a.LastSize) / $dt
          $a.LastSize = $sz
          $a.LastT = Get-Date
          if($inst -lt $MinDlSpeed){
          $slowKills++
          # Silent restart: the item goes back into the queue on another
          # channel; the progress bar keeps running untouched.
          Stop-Process -Id $a.Proc.Id -Force -ErrorAction SilentlyContinue
          if(Test-Path -LiteralPath $key){ Remove-Item -LiteralPath $key -Force -ErrorAction SilentlyContinue }
          if($a.Item.Tries -lt 3){
            $a.Item.Tries++
            $queue.Enqueue($a.Item)
          } else {
            $gaveUp.Add($a.Item) | Out-Null
          }
          $active.Remove($key)
          if($slowKills -ge $ReselectThresh){
            $slowKills = 0
            # Cooldown: do not re-probe more than once per $ReselectCooldown
            # seconds - a flaky network would otherwise trigger re-selects
            # in a tight loop.
            if(((Get-Date) - $lastReselect).TotalSeconds -ge $ReselectCooldown){
              $lastReselect = Get-Date
              if($ReselectUrl){
                $candidates = @()
                $sp = Get-SystemProxy
                if($sp){ $candidates += @{ Id='PROXY'; Args=@('--proxy',$sp); Label=$sp } }
                $ridx = 0
                foreach($ip in (Get-DirectIps 'edge.forgecdn.net')){
                  $ridx++
                  $candidates += @{ Id=('IP'+$ridx); Args=@('--resolve',('edge.forgecdn.net:443:'+$ip)); Label=$ip }
                }
                if($candidates.Count -gt 0){
                  # Quiet probe so the progress bar is not broken up; the
                  # result is reported on a single clean line.
                  $rbest = @(Probe-Channels $candidates $ReselectUrl -Quiet)
                  $ChannelPool = @()
                  if($rbest.Count -gt 0){
                    $rfast = [double]$rbest[0].Speed
                    $rthr  = [Math]::Max(500000.0, $rfast * 0.5)
                    foreach($b in $rbest){ if([double]$b.Speed -ge $rthr){ $ChannelPool += @{ Id=$b.Id; Args=$b.Args; Fails=0 } } }
                    if($ChannelPool.Count -eq 0){ $ChannelPool += @{ Id=$rbest[0].Id; Args=$rbest[0].Args; Fails=0 } }
                    $PoolIdx = 0
                    # Clear the progress-bar row first, then report on its own line.
                    Write-Host ("`r" + (' ' * $ConWidth)) -NoNewline
                    Write-Host ''
                    if($rbest[0].Id -eq 'PROXY'){
                      Write-Host ('    Channel re-selected: proxy ' + $rbest[0].Args[1] + ' (' + ('{0:N0}' -f $rbest[0].Speed) + ' B/s)') -ForegroundColor Green
                    } else {
                      Write-Host ('    Channel re-selected: direct IP ' + (($rbest[0].Args[1] -split ':')[-1]) + ' (' + ('{0:N0}' -f $rbest[0].Speed) + ' B/s)') -ForegroundColor Green
                    }
                  } else {
                    Write-Host ("`r" + (' ' * $ConWidth)) -NoNewline
                    Write-Host ''
                    Write-Host '    Channel re-selected: none available - continuing on the default route' -ForegroundColor Yellow
                  }
                }
              }
            }
          }
        }
      }
    }
  }
  }
  foreach($key in @($active.Keys)){
    $a = $active[$key]
    if($a.Proc.HasExited){
      $code = $a.Proc.ExitCode
      $size = [long]0
      if(Test-Path -LiteralPath $key){ $size = (Get-Item -LiteralPath $key).Length }
      $ok = ($code -eq 0) -and ($size -gt 0) -and ($size -ge [Math]::Min(500, $a.Item.Len)) -and (Test-ZipFile $key)
      if($ok){
        $doneBytes += $size
        $doneCount++
        $consecDlFail = 0
      } else {
        $consecDlFail++
        if($consecDlFail -ge 3){
          # The active channel looks dead (proxy turned off, node dropped).
          # Silently drop the pool + cache and continue on the default route.
          $ChannelPool = @()
          Remove-ChannelCache
          $consecDlFail = 0
        }
        if(Test-Path -LiteralPath $key){ Remove-Item -LiteralPath $key -Force -ErrorAction SilentlyContinue }
        if($a.Item.Tries -lt 3){
          $a.Item.Tries++
          Start-Sleep -Seconds 10
          $queue.Enqueue($a.Item)
        } else {
          $gaveUp.Add($a.Item) | Out-Null
        }
      }
      $active.Remove($key)
    }
  }
  $curBytes = [long]0
  foreach($key in $active.Keys){
    if(Test-Path -LiteralPath $key){ $curBytes += (Get-Item -LiteralPath $key).Length }
  }
  $remain = $queue.Count + $active.Count
  $ratio  = ($doneBytes + $curBytes) / $totalBytes
  $mbDone = [Math]::Round(($doneBytes + $curBytes) / 1MB, 1)
  $mbAll  = [Math]::Round($totalBytes / 1MB, 1)
  # Smoothed throughput display.
  $nowBytes = $doneBytes + $curBytes
  $dt = ((Get-Date) - $lastSpeedT).TotalSeconds
  if($dt -ge 0.8){
    if($lastBytes -gt 0){
      $inst = ($nowBytes - $lastBytes) / $dt
      if($emaSpeed -eq 0){ $emaSpeed = $inst } else { $emaSpeed = ($emaSpeed * 0.7) + ($inst * 0.3) }
    }
    $lastBytes = $nowBytes
    $lastSpeedT = Get-Date
  }
  $spdTxt = '--'
  if($emaSpeed -gt 0){ $spdTxt = ('{0:N1} MB/s' -f ($emaSpeed / 1MB)) }
  $barTxt = '{0}/{1}MB @ {2} | {3}/{4} | pend {5}' -f $mbDone, $mbAll, $spdTxt, $doneCount, ($doneCount + $remain), $remain
  Show-Bar $ratio $barTxt
}
Finish-Line

# Last resort: retry the given-up files once through the plain direct path.
if($gaveUp.Count -gt 0){
  Show-Info ('Retrying ' + $gaveUp.Count + ' failed files via default route ...') 'Yellow'
  foreach($it in $gaveUp){
    $curlArgs = @('-s','-L','--fail','--retry','1','--connect-timeout','30','--max-time','7200','-A',$Ua,'-o',$it.ZipPath,$it.DlUrl)
    & curl.exe @curlArgs
    $size = [long]0
    if(Test-Path -LiteralPath $it.ZipPath){ $size = (Get-Item -LiteralPath $it.ZipPath).Length }
    if(($LASTEXITCODE -eq 0) -and ($size -gt 0) -and (Test-ZipFile $it.ZipPath)){
      $doneBytes += $size
      $doneCount++
      Write-Host ('    OK: ' + $it.Name) -ForegroundColor Green
    } else {
      $dlFailed.Add($it.Name) | Out-Null
      if(Test-Path -LiteralPath $it.ZipPath){ Remove-Item -LiteralPath $it.ZipPath -Force -ErrorAction SilentlyContinue }
    }
  }
}
if($dlFailed.Count -gt 0){
  Write-Host (Truncate-Text ('  Download FAILED: ' + (($dlFailed | ForEach-Object { ($_ -replace ' \(no CDN link\)','') }) -join ', ')) $ConWidth) -ForegroundColor Red
} else {
  Write-Host ('  All ' + $doneCount + ' zip files downloaded.') -ForegroundColor Gray
}

# ------------------------ phase 4: extract packages -------------------------
Write-Host ''
Write-Host '[4/5] Extracting addons into target directory ...' -ForegroundColor Green
$extractOk   = New-Object System.Collections.Generic.List[string]
$extractFail = New-Object System.Collections.Generic.List[string]
$zips = @($resolved | Where-Object { (Test-Path -LiteralPath $_.ZipPath) -and -not ($dlFailed -contains $_.Name) })

$tarCmd = $null
try { if(Get-Command tar.exe -ErrorAction Stop){ $tarCmd = 'tar.exe' } } catch {}
# Extraction parallelism scales with the machine: logical cores - 2 (min 1).
$cores = [Environment]::ProcessorCount
$tarWorkers = [Math]::Max(1, $cores - 2)
Write-Host ('  Extraction workers: ' + $tarWorkers + ' (CPU cores ' + $cores + ' - 2)') -ForegroundColor Gray
$tarQueue = New-Object System.Collections.Generic.Queue[object]
foreach($r in $zips){ $tarQueue.Enqueue($r) | Out-Null }
$tActive = @{}
$tDone = 0

function Complete-Extract($r,$stage){
  try{
    $tops = @(Get-ChildItem -LiteralPath $stage -Directory -ErrorAction Stop)
    if($tops.Count -eq 0){ throw 'zip contains no addon folder' }
    $moved = @()
    foreach($d in $tops){
      $target = Join-Path $DeployDir $d.Name
      if(Test-Path -LiteralPath $target){ Remove-Item -LiteralPath $target -Recurse -Force }
      Move-Item -LiteralPath $d.FullName -Destination $target -Force
      $moved += $d.Name
    }
    $r.Folders = @($moved)
    $extractOk.Add($r.Name) | Out-Null
  }catch{
    $extractFail.Add($r.Name + ' (' + $_.Exception.Message + ')') | Out-Null
  }finally{
    if(Test-Path -LiteralPath $stage){ Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
  }
}

while($tarQueue.Count -gt 0 -or $tActive.Count -gt 0){
  while($tActive.Count -lt $tarWorkers -and $tarQueue.Count -gt 0){
    $r = $tarQueue.Dequeue()
    $stage = Join-Path $Work ('stage_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    if($tarCmd){
      $argLine = Get-CurlArgLine @('-xf',$r.ZipPath,'-C',$stage)
      $proc = Start-Process -FilePath $tarCmd -ArgumentList $argLine -PassThru -WindowStyle Hidden
    } else {
      $proc = $null
    }
    $tActive[$r.Name] = @{ Proc = $proc; Item = $r; Stage = $stage; Tar = ($null -ne $proc) }
  }
  Start-Sleep -Milliseconds 300
  foreach($key in @($tActive.Keys)){
    $a = $tActive[$key]
    $done = $false
    if($a.Tar){
      if($a.Proc.HasExited){
        if($a.Proc.ExitCode -eq 0){
          $done = $true
          Complete-Extract $a.Item $a.Stage
        } else {
          # tar failed - fall back to Expand-Archive
          try{
            Expand-Archive -LiteralPath $a.Item.ZipPath -DestinationPath $a.Stage -Force
            $done = $true
            Complete-Extract $a.Item $a.Stage
          }catch{
            $extractFail.Add($a.Item.Name + ' (' + $_.Exception.Message + ')') | Out-Null
            if(Test-Path -LiteralPath $a.Stage){ Remove-Item -LiteralPath $a.Stage -Recurse -Force -ErrorAction SilentlyContinue }
          }
        }
      }
    } else {
      try{
        Expand-Archive -LiteralPath $a.Item.ZipPath -DestinationPath $a.Stage -Force
        $done = $true
        Complete-Extract $a.Item $a.Stage
      }catch{
        $extractFail.Add($a.Item.Name + ' (' + $_.Exception.Message + ')') | Out-Null
        if(Test-Path -LiteralPath $a.Stage){ Remove-Item -LiteralPath $a.Stage -Recurse -Force -ErrorAction SilentlyContinue }
      }
    }
    if($done){
      $tDone++
      Show-Bar ($tDone / $zips.Count) ('extracting ' + $a.Item.Name + ' (' + $tDone + '/' + $zips.Count + ')')
      $tActive.Remove($key)
    }
  }
}
Finish-Line

# Record CurseForge state for the next run: freshly deployed entries get
# {fileId, md5, folders}; verified-skip entries keep their stored object;
# deleted keys (no longer in the list) and damaged-then-redeployed keys are
# replaced/dropped here. Failed downloads keep their old state so they retry.
$cfState = @{}
if($deployState -and $deployState.cf){
  foreach($p in $deployState.cf.PSObject.Properties){
    if(-not $dropCf.ContainsKey($p.Name)){ $cfState[$p.Name] = $p.Value }
  }
}
$freshCf = @($resolved | Where-Object { $_.Plan -eq 'download' -and ($extractOk -contains $_.Name) -and $_.Folders })
$cfMd5 = @{}
if($freshCf.Count -gt 0){
  Write-Host ('  Computing md5 for ' + $freshCf.Count + ' newly deployed CurseForge addon(s) ...') -ForegroundColor Gray
  $cfMd5 = Invoke-Md5Parallel (@($freshCf | ForEach-Object { @{ Key=$_.Name; Folders=@($_.Folders) } }))
}
foreach($r in $freshCf){
  $md5 = ''
  if($cfMd5.ContainsKey($r.Name)){ $md5 = $cfMd5[$r.Name] }
  $cfState[$r.Name] = @{ fileId = [string]$r.FileId; md5 = $md5; folders = @($r.Folders) }
}

# ------------------------- phase 5: own SoD addons --------------------------
# The *-SoD addons are ALWAYS downloaded from GitHub (source archive zip),
# so the script works identically on any machine - no local git workspace
# is used. Sources per repo/branch, in order:
#   1. codeload.github.com/.../zip/...      (direct, no redirect - fastest)
#   2. github.com/.../archive/...zip        (302 -> codeload)
#   3. api.github.com/.../tarball/...       (tar.gz fallback)
Write-Host ''
Write-Host '[5/5] Downloading own SoD addons from GitHub ...' -ForegroundColor Green
$sodOk   = New-Object System.Collections.Generic.List[string]
$sodFail = New-Object System.Collections.Generic.List[string]
$sodSkip = 0
$sodEtag = @{}

# GitHub channel: codeload.github.com is a different host than the CurseForge
# CDN, so when a proxy is in use for CurseForge we compare proxy vs direct
# for GitHub too. Without a proxy, plain direct is used (codeload is directly
# reachable).
$GhArgs = @()
if($ChProxy -and $SodRepos.Count -gt 0){
  $ghProbeUrl = 'https://codeload.github.com/' + $GhUser + '/' + $SodRepos[0].Repo + '/zip/refs/heads/main'
  $candidates = @()
  $candidates += @{ Id='PROXY'; Args=@('--proxy',$ChProxy); Label='proxy ' + $ChProxy }
  $candidates += @{ Id='DIRECT'; Args=@(); Label='direct' }
  Write-Host '  Probing GitHub channel (8s each, parallel):' -ForegroundColor Gray
  $ghBest = @(Probe-Channels $candidates $ghProbeUrl)
  if($ghBest.Count -gt 0 -and $ghBest[0].Id -eq 'PROXY'){
    $GhArgs = @('--proxy',$ChProxy)
    Write-Host ('  -> GitHub via proxy: ' + $ChProxy + ' (' + ('{0:N0}' -f $ghBest[0].Speed) + ' B/s)') -ForegroundColor Green
  } else {
    Write-Host '  -> GitHub via direct connection.' -ForegroundColor Green
  }
} else {
  Write-Host '  GitHub via direct connection.' -ForegroundColor Gray
}

$i = 0
foreach($s in $SodRepos){
  $i++
  # Verified-intact repos (md5 ok in the integrity phase) are not downloaded.
  if($sodSkipOk.ContainsKey($s.Folder)){
    $sodOk.Add($s.Folder) | Out-Null
    $sodSkip++
    Show-Bar ($i / $SodRepos.Count) ('up to date: ' + $s.Folder + ' (' + $i + '/' + $SodRepos.Count + ')')
    continue
  }
  Show-Bar (($i - 1) / $SodRepos.Count) ('downloading ' + $s.Folder + ' (' + $i + '/' + $SodRepos.Count + ')')
  $target = Join-Path $DeployDir $s.Folder
  $done   = $false
  $dlInfo = ''
  foreach($branch in 'main','master'){
    $zip = Join-Path $DlDir ($s.Repo + '-' + $branch + '.zip')
    $urls = @(
      ('https://codeload.github.com/' + $GhUser + '/' + $s.Repo + '/zip/refs/heads/' + $branch),
      ('https://github.com/' + $GhUser + '/' + $s.Repo + '/archive/refs/heads/' + $branch + '.zip'),
      ('https://api.github.com/repos/' + $GhUser + '/' + $s.Repo + '/tarball/' + $branch)
    )
    foreach($url in $urls){
      $dlSw = [Diagnostics.Stopwatch]::StartNew()
      if(Invoke-CurlDownload $url $zip 300 $GhArgs){
        $dlSw.Stop()
        $stage = Join-Path $Work ('sod_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
        New-Item -ItemType Directory -Force -Path $stage | Out-Null
        $unpackOk = $false
        try{
          if($tarCmd){
            $argLine = Get-CurlArgLine @('-xf',$zip,'-C',$stage)
            $tp = Start-Process -FilePath $tarCmd -ArgumentList $argLine -PassThru -WindowStyle Hidden
            $null = $tp.WaitForExit(120000)
            if($tp.ExitCode -eq 0){ $unpackOk = $true }
          }
          if(-not $unpackOk){
            Expand-Archive -LiteralPath $zip -DestinationPath $stage -Force
            $unpackOk = $true
          }
        }catch{}
        if($unpackOk){
          $inner = @(Get-ChildItem -LiteralPath $stage -Directory) | Select-Object -First 1
          if($inner){
            if(Test-Path -LiteralPath $target){ Remove-Item -LiteralPath $target -Recurse -Force }
            Move-Item -LiteralPath $inner.FullName -Destination $target -Force
            $done = $true
          }
        }
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
        if($done){
          $sz = [long]0
          if(Test-Path -LiteralPath $zip){ $sz = (Get-Item -LiteralPath $zip).Length }
          $spd = 0.0
          if($dlSw.Elapsed.TotalSeconds -gt 0){ $spd = $sz / $dlSw.Elapsed.TotalSeconds }
          $dlInfo = ('{0:N1} KB @ {1:N1} KB/s' -f ($sz/1KB), ($spd/1KB))
          break
        }
      }
    }
    if($done){ break }
  }
  if($done){
    $sodOk.Add($s.Folder) | Out-Null
    $sodEtag[$s.Folder] = $sodEtagPlan[$s.Folder]
    if(-not $sodEtag[$s.Folder]){
      # HEAD failed during planning; fetch it now so the state has an etag.
      $sodEtag[$s.Folder] = Get-CodeloadEtag ('https://codeload.github.com/' + $GhUser + '/' + $s.Repo + '/zip/refs/heads/main') $GhArgs
    }
    Show-Bar ($i / $SodRepos.Count) ('OK: ' + $s.Folder + ' ' + $dlInfo + ' (' + $i + '/' + $SodRepos.Count + ')')
  } else {
    $sodFail.Add($s.Folder) | Out-Null
    Show-Bar ($i / $SodRepos.Count) ('FAILED: ' + $s.Folder + ' (' + $i + '/' + $SodRepos.Count + ')')
  }
}
Finish-Line
if($sodSkip -gt 0){
  Write-Host ('  ' + $sodSkip + ' of ' + $SodRepos.Count + ' SoD addons verified up to date (md5 ok, skipped).') -ForegroundColor Gray
}

# Persist SoD state: verified entries are kept, deleted keys are dropped and
# fresh deployments are recorded with {etag, md5, folders}.
$sodState = @{}
if($deployState -and $deployState.sod){
  foreach($p in $deployState.sod.PSObject.Properties){
    if(-not $dropSod.ContainsKey($p.Name)){ $sodState[$p.Name] = $p.Value }
  }
}
$freshSod = @($SodRepos | Where-Object { $sodDl.ContainsKey($_.Folder) -and ($sodOk -contains $_.Folder) })
$sodMd5 = @{}
if($freshSod.Count -gt 0){
  Write-Host ('  Computing md5 for ' + $freshSod.Count + ' newly deployed SoD addon(s) ...') -ForegroundColor Gray
  $sodMd5 = Invoke-Md5Parallel (@($freshSod | ForEach-Object { @{ Key=$_.Folder; Folders=@($_.Folder) } }))
}
foreach($s in $freshSod){
  $md5 = ''
  if($sodMd5.ContainsKey($s.Folder)){ $md5 = $sodMd5[$s.Folder] }
  $sodState[$s.Folder] = @{ etag = $sodEtag[$s.Folder]; md5 = $md5; folders = @($s.Folder) }
}
Write-DeployState @{ cf = $cfState; sod = $sodState }

# ------------------------------- cleanup ------------------------------------
Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue

# ------------------------------- summary ------------------------------------
Write-Host ''
Write-Host $HLine -ForegroundColor Cyan
Write-Host '  Deployment summary' -ForegroundColor Cyan
Write-Host $HLine -ForegroundColor Cyan
Write-Host ('  CurseForge OK   : ' + ($extractOk.Count + $cfSkip) + '/' + $Projects.Count) -ForegroundColor Green
if($extractFail.Count -gt 0){
  Write-Host (Truncate-Text ('  Extract FAILED  : ' + ($extractFail -join '; ')) $ConWidth) -ForegroundColor Red
}
if($resolveFail.Count -gt 0){
  Write-Host (Truncate-Text ('  Resolve FAILED  : ' + ($resolveFail -join ', ')) $ConWidth) -ForegroundColor Red
}
if($dlFailed.Count -gt 0){
  Write-Host (Truncate-Text ('  Download FAILED : ' + ($dlFailed -join ', ')) $ConWidth) -ForegroundColor Red
}
Write-Host ('  SoD addons OK   : ' + $sodOk.Count + '/' + $SodRepos.Count) -ForegroundColor Green
if($sodFail.Count -gt 0){
  Write-Host (Truncate-Text ('  SoD FAILED      : ' + ($sodFail -join ', ')) $ConWidth) -ForegroundColor Red
}
$nOk  = $cfSkipOk.Count + $sodSkipOk.Count
$nBad = $damaged.Count
$nDel = $cfDelete.Count + $sodDelete.Count
Write-Host ''
Write-Host ('  ' + $SymOk + ' up to date (md5 ok)      : ' + $nOk) -ForegroundColor Green
if($nBad -gt 0){ Write-Host ('  ' + $SymBad + ' damaged -> re-downloaded : ' + $nBad) -ForegroundColor Yellow }
if($nDel -gt 0){ Write-Host ('  ' + $SymDel + ' deleted (removed from list): ' + $nDel) -ForegroundColor Red }
Write-Host '  Downloaded zip files have been removed.' -ForegroundColor Gray
Write-Host ('  Tip: delete ' + $StateFile + ' to force a full refresh.') -ForegroundColor Gray
Write-Host ''
Restore-ConsoleMode
Read-Host '  Press Enter to exit' | Out-Null
