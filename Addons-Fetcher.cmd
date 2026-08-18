@echo off
title Addons-Fetcher - WoW Classic Era AddOns One-Click Deploy
chcp 65001 >nul
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$env:DEPLOY_SELF='%~f0'; $env:DEPLOY_DIR='%~dp0'; $c=[IO.File]::ReadAllText('%~f0',[Text.Encoding]::UTF8); $m=([char]10).ToString()+'#PS'+'START'; $i=$c.IndexOf($m); if($i -lt 0){ Write-Host 'Script marker not found.'; exit 1 }; Invoke-Expression ($c.Substring($i+$m.Length))"
exit /b %ERRORLEVEL%
#PSSTART
# ============================================================================
#  WoW Classic Era - AddOns one-click deployment script
#  - Downloads all CurseForge addons listed below (latest Classic Era file)
#  - Copies the *-SoD addons from the local git workspace (GitHub fallback)
#  - Extracts everything into the 'Addons' subfolder next to THIS script
#    (put this script into the 'Interface' folder and run it there)
#  - Deletes all downloaded zip files when finished
#  Notes:
#  - Metadata lookups use the official CurseForge Core API
#    (api.curseforge.com) with the API key of the locally installed
#    CurseForge app. This endpoint is fast and not behind Cloudflare.
#  - If the Core API is unavailable, the script falls back to scraping
#    www.curseforge.com with the Windows native Schannel HTTP stack,
#    which passes Cloudflare far more reliably than curl. When
#    Cloudflare starts challenging, the script goes silent for several
#    minutes and then retries the failed items.
#  - Bulk downloads go straight to the ForgeCDN mirror, which is not
#    challenge-protected.
# ============================================================================
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$Self      = $env:DEPLOY_SELF
$ScriptDir = ($env:DEPLOY_DIR).TrimEnd('\')
$DeployDir  = Join-Path $ScriptDir 'Addons'

# ----------------------------- configuration --------------------------------
$Ua          = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'
$Referer     = 'https://www.curseforge.com/wow/addons'
$ApiBase     = 'https://www.curseforge.com/api/v1'
$CoreBase    = 'https://api.curseforge.com/v1'
$CfApiKey    = '$2a$10$bL4bIL5pUWqfcO7KQtnMReakwtfHbNKh6v1uTpKlzhwoueEJQnPnm'
$RepoRoot    = (Join-Path $env:USERPROFILE 'WorkSpace\Github')
$GhUser      = 'Addons-SoD'
$Concurrency = 3
$SilenceSec  = 420
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
  @{ Name = 'alaTradeSkill';            Id = 380889  }
)

# Own SoD addons from git repositories (repo name -> addon folder name)
$SodRepos = @(
  @{ Repo = 'BFGadgets-SoD';        Folder = 'BFGadgets'       },
  @{ Repo = 'BiaoGe-SoD';           Folder = 'BiaoGe'          },
  @{ Repo = 'RepairHelper-SoD';     Folder = 'RepairHelper'    },
  @{ Repo = 'SellerHelper-SoD';     Folder = 'SellerHelper'    },
  @{ Repo = 'TheBurningTrade-SoD';  Folder = 'TheBurningTrade' },
  @{ Repo = 'WhisperPop-SoD';       Folder = 'WhisperPop'      }
)

# Not from CurseForge - left untouched on disk
$External = @('_DebugLog','bloodOfHeros','GatherMate2_Data','LoonBestInSlot','MYStats','Ranker','RuneReminder','TalentEmuX')
# ------------------------------- helpers ------------------------------------
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
  $w = 30
  $f = [int]([Math]::Round($w * $ratio))
  $bar = ([string][char]0x2588) * $f + ([string][char]0x2591) * ($w - $f)
  $line = "`r  [" + $bar + "] " + ("{0,3}" -f [int]($ratio*100)) + "%  " + $text
  if($line.Length -gt 110){ $line = $line.Substring(0,110) }
  Write-Host ($line.PadRight(110)) -NoNewline
}

function Finish-Line{ Write-Host '' }

function Show-Info($msg,$color){
  Write-Host ''
  Write-Host ('    ' + $msg) -ForegroundColor $color
}

function Get-StatusCode($err){
  try{
    if($err.Exception.Response){ return [int]$err.Exception.Response.StatusCode }
  }catch{}
  return 0
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
# direct ForgeCDN link, which curl can fetch without being challenged.
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

# Pick the newest Classic Era release for a project via the Core API.
# Pages through the newest files (max 200) and prefers, in order:
# release channel files matching 1.15.x, then 1.14.x, then 1.13.x,
# then simply the newest release-channel file.
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
    Start-Sleep -Milliseconds 200
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

function Invoke-CurlDownload($url,$outFile,$timeoutSec){
  & curl.exe -s -L --fail --retry 3 --retry-delay 2 --connect-timeout 30 --max-time $timeoutSec -A $Ua -e $Referer -o $outFile $url
  return ($LASTEXITCODE -eq 0)
}

# ------------------------------ pre-checks ----------------------------------
Write-Host ''
Write-Host '================================================================' -ForegroundColor Cyan
Write-Host '   World of Warcraft Classic Era - AddOns one-click deploy'      -ForegroundColor Cyan
Write-Host '================================================================' -ForegroundColor Cyan
Write-Host ('  Target directory : ' + $DeployDir)
Write-Host ('  CurseForge addons: ' + $Projects.Count + ' projects')
Write-Host ('  Own SoD addons   : ' + $SodRepos.Count + ' repositories')
Write-Host ('  External (skip)  : ' + ($External -join ', '))
Write-Host ''

$checkDir = $ScriptDir
if(Test-Path -LiteralPath $DeployDir){ $checkDir = $DeployDir }
if(-not (Test-Writable $checkDir)){
  $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  if($principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)){
    Write-Host '  ERROR: target directory is not writable even as administrator.' -ForegroundColor Red
    Read-Host '  Press Enter to exit' | Out-Null
    exit 1
  }
  Write-Host '  Target directory needs administrator permission - requesting elevation...' -ForegroundColor Yellow
  Start-Process -FilePath $Self -Verb RunAs | Out-Null
  exit 0
}
New-Item -ItemType Directory -Force -Path $DeployDir | Out-Null

$wow = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^Wow' })
if($wow.Count -gt 0){
  Write-Host '  WARNING: World of Warcraft appears to be running. Files in use may fail to update.' -ForegroundColor Yellow
  Write-Host '           It is recommended to close the game first.' -ForegroundColor Yellow
}

$Work = Join-Path $env:TEMP ('AddonDeploy_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $Work | Out-Null
$DlDir = Join-Path $Work 'downloads'
New-Item -ItemType Directory -Force -Path $DlDir | Out-Null
# --------------------- phase 1: resolve latest files ------------------------
Write-Host ''
Write-Host '[1/4] Resolving latest Classic Era files on CurseForge ...' -ForegroundColor Green
$resolved     = New-Object System.Collections.Generic.List[object]
$resolveFail  = New-Object System.Collections.Generic.List[string]
$coreFail     = New-Object System.Collections.Generic.List[object]

$i = 0
foreach($p in $Projects){
  $i++
  Show-Bar ($i / $Projects.Count) ('resolving ' + $p.Name + ' (' + $i + '/' + $Projects.Count + ')')
  $file = Resolve-ProjectCore $p.Id
  if($null -eq $file){
    $coreFail.Add($p) | Out-Null
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
  Start-Sleep -Milliseconds 200
}
Finish-Line

# Fallback: projects the Core API could not serve are scraped from the
# Cloudflare-protected website instead (slow but reliable).
if($coreFail.Count -gt 0){
  Show-Info ('Core API unavailable for ' + $coreFail.Count + ' projects - falling back to website scraping ...') 'Yellow'
  $pending = $coreFail.ToArray()
  for($pass = 1; $pass -le 2 -and $pending.Count -gt 0; $pass++){
    if($pass -eq 2){
      Show-Info ('Second pass: retrying ' + $pending.Count + ' blocked projects after a ' + $SilenceSec + 's silence ...') 'Yellow'
      Start-Sleep -Seconds $SilenceSec
    }
    $stillFail  = New-Object System.Collections.Generic.List[object]
    $consecFail = 0
    $batch      = $pending
    $i = 0
    foreach($p in $batch){
      $i++
      $label = 'resolving ' + $p.Name + ' (' + $i + '/' + $batch.Count + ')'
      if($pass -eq 2){ $label += ' [retry]' }
      Show-Bar ($i / $batch.Count) $label
      $file = Resolve-Project $p.Id
      if($null -eq $file){
        $consecFail++
        if($pass -eq 1){ $stillFail.Add($p) | Out-Null } else { $resolveFail.Add($p.Name) | Out-Null }
        if($consecFail -eq 3 -and $i -lt $batch.Count){
          Show-Info ('Cloudflare is challenging us - going silent for ' + $SilenceSec + 's ...') 'Yellow'
          Start-Sleep -Seconds $SilenceSec
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
      Start-Sleep -Milliseconds (Get-Random -Minimum 1200 -Maximum 2600)
    }
    Finish-Line
    $pending = $stillFail.ToArray()
  }
}

Write-Host ('  Resolved ' + $resolved.Count + '/' + $Projects.Count + ' projects:') -ForegroundColor Gray
foreach($r in $resolved){
  Write-Host ('    - ' + $r.Name.PadRight(24) + $r.ZipName) -ForegroundColor Gray
}
if($resolveFail.Count -gt 0){
  Write-Host ('  FAILED to resolve: ' + ($resolveFail -join ', ')) -ForegroundColor Red
}

# ------------------- phase 2: locate CDN links + download -------------------
Write-Host ''
Write-Host ('[2/4] Downloading from CurseForge (parallel x' + $Concurrency + ') ...') -ForegroundColor Green

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
      Start-Sleep -Seconds $SilenceSec
    }
    $stillFail  = New-Object System.Collections.Generic.List[object]
    $consecFail = 0
    $i = 0
    foreach($r in $cdnPending){
      $i++
      Show-Bar ($i / $cdnPending.Count) ('locating CDN link ' + $r.Name + ' (' + $i + '/' + $cdnPending.Count + ')')
      $cdn = $null
      if($r.Core -eq $true){
        try{ $cdn = [string](Invoke-RestMethod -Uri $r.Url -Headers $CoreHeaders -TimeoutSec 60) }catch{ $cdn = $null }
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
          Show-Info ('CDN lookup keeps failing - going silent for ' + $SilenceSec + 's ...') 'Yellow'
          Start-Sleep -Seconds $SilenceSec
          $consecFail = 0
        }
      }
      Start-Sleep -Milliseconds (Get-Random -Minimum 300 -Maximum 800)
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
$totalBytes = [long]0
foreach($r in $resolved){ $totalBytes += $r.Len }
if($totalBytes -le 0){ $totalBytes = [long]1 }

$queue = New-Object System.Collections.Generic.Queue[object]
$dlFailed  = New-Object System.Collections.Generic.List[string]
foreach($r in $resolved){
  if($r.DlUrl){ $queue.Enqueue($r) } else { $dlFailed.Add($r.Name + ' (no CDN link)') | Out-Null }
}
$active    = @{}
$doneBytes = [long]0
$doneCount = 0

while($queue.Count -gt 0 -or $active.Count -gt 0){
  while($active.Count -lt $Concurrency -and $queue.Count -gt 0){
    $it = $queue.Dequeue()
    $curlArgs = @('-s','-L','--fail','--retry','2','--retry-delay','3','--connect-timeout','30','--max-time','7200','-A',$Ua,'-o',$it.ZipPath,$it.DlUrl)
    $argLine = (($curlArgs | ForEach-Object { if([string]$_ -match '[ "	]'){ '"' + ([string]$_ -replace '"','\"') + '"' } else { [string]$_ } }) -join ' ')
    $proc = Start-Process -FilePath 'curl.exe' -ArgumentList $argLine -PassThru -WindowStyle Hidden
    $active[$it.ZipPath] = @{ Proc = $proc; Item = $it }
    if($queue.Count -gt 0){ Start-Sleep -Milliseconds (Get-Random -Minimum 1000 -Maximum 2000) }
  }
  Start-Sleep -Milliseconds 700
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
      } else {
        if(Test-Path -LiteralPath $key){ Remove-Item -LiteralPath $key -Force -ErrorAction SilentlyContinue }
        if($a.Item.Tries -lt 3){
          $a.Item.Tries++
          Show-Info ($a.Item.Name + ': download attempt ' + $a.Item.Tries + ' failed - waiting 10s before retry') 'Yellow'
          Start-Sleep -Seconds 10
          $queue.Enqueue($a.Item)
        } else {
          $dlFailed.Add($a.Item.Name) | Out-Null
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
  Show-Bar $ratio ('downloading ' + $mbDone + '/' + $mbAll + ' MB | done ' + $doneCount + '/' + ($doneCount + $remain) + ' | pending ' + $remain)
}
Finish-Line
if($dlFailed.Count -gt 0){
  Write-Host ('  Download FAILED: ' + (($dlFailed | ForEach-Object { ($_ -replace ' \(no CDN link\)','') }) -join ', ')) -ForegroundColor Red
} else {
  Write-Host ('  All ' + $doneCount + ' zip files downloaded.') -ForegroundColor Gray
}

# ------------------------ phase 3: extract packages -------------------------
Write-Host ''
Write-Host '[3/4] Extracting addons into target directory ...' -ForegroundColor Green
$extractOk   = New-Object System.Collections.Generic.List[string]
$extractFail = New-Object System.Collections.Generic.List[string]
$zips = @($resolved | Where-Object { (Test-Path -LiteralPath $_.ZipPath) -and -not ($dlFailed -contains $_.Name) })
$i = 0
foreach($r in $zips){
  $i++
  Show-Bar ($i / $zips.Count) ('extracting ' + $r.Name + ' (' + $i + '/' + $zips.Count + ')')
  $stage = Join-Path $Work ('stage_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
  try{
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    Expand-Archive -LiteralPath $r.ZipPath -DestinationPath $stage -Force
    $tops = @(Get-ChildItem -LiteralPath $stage -Directory)
    if($tops.Count -eq 0){ throw 'zip contains no addon folder' }
    foreach($d in $tops){
      $target = Join-Path $DeployDir $d.Name
      if(Test-Path -LiteralPath $target){ Remove-Item -LiteralPath $target -Recurse -Force }
      Move-Item -LiteralPath $d.FullName -Destination $target -Force
    }
    $extractOk.Add($r.Name) | Out-Null
  }catch{
    $extractFail.Add($r.Name + ' (' + $_.Exception.Message + ')') | Out-Null
  }finally{
    if(Test-Path -LiteralPath $stage){ Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
  }
}
Finish-Line
# ------------------------- phase 4: own SoD addons --------------------------
Write-Host ''
Write-Host '[4/4] Deploying own SoD addons from git workspace ...' -ForegroundColor Green
$sodOk   = New-Object System.Collections.Generic.List[string]
$sodFail = New-Object System.Collections.Generic.List[string]
$i = 0
foreach($s in $SodRepos){
  $i++
  Show-Bar ($i / $SodRepos.Count) ('deploying ' + $s.Folder + ' (' + $i + '/' + $SodRepos.Count + ')')
  $target = Join-Path $DeployDir $s.Folder
  $src    = Join-Path $RepoRoot $s.Repo
  $done   = $false
  if(Test-Path -LiteralPath $src){
    try{
      if(Test-Path -LiteralPath $target){ Remove-Item -LiteralPath $target -Recurse -Force }
      New-Item -ItemType Directory -Force -Path $target | Out-Null
      & robocopy $src $target /E /XD .git .vscode .github /XF .gitignore /NFL /NDL /NJH /NJS /NP | Out-Null
      if($LASTEXITCODE -lt 8){ $done = $true }
    }catch{}
  }
  if(-not $done){
    $ghOk = $false
    foreach($branch in 'main','master'){
      $zip = Join-Path $DlDir ($s.Repo + '-' + $branch + '.zip')
      $url = 'https://github.com/' + $GhUser + '/' + $s.Repo + '/archive/refs/heads/' + $branch + '.zip'
      if(Invoke-CurlDownload $url $zip 600){
        $stage = Join-Path $Work ('sod_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
        try{
          Expand-Archive -LiteralPath $zip -DestinationPath $stage -Force
          $inner = @(Get-ChildItem -LiteralPath $stage -Directory) | Select-Object -First 1
          if($inner){
            if(Test-Path -LiteralPath $target){ Remove-Item -LiteralPath $target -Recurse -Force }
            Move-Item -LiteralPath $inner.FullName -Destination $target -Force
            $ghOk = $true
          }
        }catch{}
        if(Test-Path -LiteralPath $stage){ Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
        if($ghOk){ break }
      }
    }
    if($ghOk){ $done = $true }
  }
  if($done){ $sodOk.Add($s.Folder) | Out-Null } else { $sodFail.Add($s.Folder) | Out-Null }
}
Finish-Line

# ------------------------------- cleanup ------------------------------------
Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue

# ------------------------------- summary ------------------------------------
Write-Host ''
Write-Host '================================================================' -ForegroundColor Cyan
Write-Host '  Deployment summary' -ForegroundColor Cyan
Write-Host '================================================================' -ForegroundColor Cyan
Write-Host ('  CurseForge OK   : ' + $extractOk.Count + '/' + $Projects.Count) -ForegroundColor Green
if($extractFail.Count -gt 0){
  Write-Host ('  Extract FAILED  : ' + ($extractFail -join '; ')) -ForegroundColor Red
}
if($resolveFail.Count -gt 0){
  Write-Host ('  Resolve FAILED  : ' + ($resolveFail -join ', ')) -ForegroundColor Red
}
if($dlFailed.Count -gt 0){
  Write-Host ('  Download FAILED : ' + ($dlFailed -join ', ')) -ForegroundColor Red
}
Write-Host ('  SoD addons OK   : ' + $sodOk.Count + '/' + $SodRepos.Count) -ForegroundColor Green
if($sodFail.Count -gt 0){
  Write-Host ('  SoD FAILED      : ' + ($sodFail -join ', ')) -ForegroundColor Red
}
Write-Host ('  Kept untouched  : ' + ($External -join ', ')) -ForegroundColor Gray
Write-Host '  Downloaded zip files have been removed.' -ForegroundColor Gray
Write-Host ''
Read-Host '  Press Enter to exit' | Out-Null
