# 88API-image-gen multi-client installer (Windows PowerShell).
#
# Links the shared skill into every detected AI client and copies the Hermes
# desktop panel when Hermes is present. The core script generate.mjs is never
# copied; all clients run it from this repository checkout.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File install.ps1
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Target claude
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Uninstall
#
# Targets: claude | cursor | hermes | agents | all (default: all)

[CmdletBinding()]
param(
    [ValidateSet("claude", "cursor", "hermes", "agents", "all")]
    [string]$Target = "all",
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Split-Path -Parent $MyInvocation.MyCommand.Path)).Path
$SkillSource = Join-Path $RepoRoot "skills\88api-image-gen"
$PanelSource = Join-Path $RepoRoot "hermes-desktop-plugin\plugin.js"
$SkillName = "88api-image-gen"
$HomeDir = $env:USERPROFILE

function Write-Ok   { param([string]$Message) Write-Host "  [ok] $Message" }
function Write-Skip { param([string]$Message) Write-Host "  [skip] $Message" }

function Test-Want {
    param([string]$Name)
    return ($Target -eq "all") -or ($Target -eq $Name)
}

function Link-Skill {
    param([string]$DestDir, [string]$Label)
    New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
    $linkPath = Join-Path $DestDir $SkillName
    if (Test-Path $linkPath) {
        $item = Get-Item $linkPath -Force
        if ($item.LinkType -and ($item.Target -eq $SkillSource)) {
            Write-Ok "$Label`: already linked ($linkPath)"
            return
        }
        Write-Host "  $Label`: $linkPath exists and is not our link; leaving it untouched"
        return
    }
    # Directory junctions work without developer mode or elevation, unlike symlinks.
    New-Item -ItemType Junction -Path $linkPath -Value $SkillSource | Out-Null
    Write-Ok "$Label`: linked $linkPath -> $SkillSource"
}

function Unlink-Skill {
    param([string]$DestDir, [string]$Label)
    $linkPath = Join-Path $DestDir $SkillName
    if (Test-Path $linkPath) {
        $item = Get-Item $linkPath -Force
        if ($item.LinkType -and ($item.Target -eq $SkillSource)) {
            Remove-Item $linkPath -Force -Recurse
            Write-Ok "$Label`: removed $linkPath"
            return
        }
    }
    Write-Skip "$Label`: nothing to remove"
}

function Install-HermesPanel {
    $destDir = Join-Path $HomeDir ".hermes\desktop-plugins\$SkillName"
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    Copy-Item $PanelSource (Join-Path $destDir "plugin.js") -Force
    Write-Ok "hermes desktop panel: copied to $destDir (run 'Reload desktop plugins' from Ctrl-K)"
}

function Uninstall-HermesPanel {
    $destDir = Join-Path $HomeDir ".hermes\desktop-plugins\$SkillName"
    if (Test-Path $destDir) {
        Remove-Item $destDir -Force -Recurse
        Write-Ok "hermes desktop panel: removed $destDir"
    } else {
        Write-Skip "hermes desktop panel: nothing to remove"
    }
}

Write-Host "88API-image-gen installer"
Write-Host "repository: $RepoRoot"

if ($Uninstall) {
    if (Test-Want "claude") { Unlink-Skill (Join-Path $HomeDir ".claude\skills") "claude" }
    if (Test-Want "cursor") { Unlink-Skill (Join-Path $HomeDir ".cursor\skills") "cursor" }
    if (Test-Want "agents") { Unlink-Skill (Join-Path $HomeDir ".agents\skills") "agents" }
    if (Test-Want "hermes") {
        Unlink-Skill (Join-Path $HomeDir ".hermes\skills") "hermes"
        Uninstall-HermesPanel
    }
    Write-Host "done."
    exit 0
}

# Prerequisite checks
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCmd) {
    Write-Host "WARNING: node not found. Install Node.js 18+ before using the plugin."
} else {
    $nodeVersion = (& node --version) -replace "^v", ""
    $nodeMajor = [int]($nodeVersion.Split(".")[0])
    if ($nodeMajor -lt 18) {
        Write-Host "WARNING: node v$nodeVersion detected; Node.js 18+ is required (20+ recommended)."
    } else {
        Write-Ok "node v$nodeVersion"
    }
}
Write-Ok "resize backend: Windows PowerShell / System.Drawing"

$detectedAny = $false

if (Test-Want "claude") {
    if (Test-Path (Join-Path $HomeDir ".claude")) {
        $detectedAny = $true
        Link-Skill (Join-Path $HomeDir ".claude\skills") "claude"
        Write-Host "  claude: tip - you can also use '/plugin marketplace add DaYePython/88API-image-gen'"
    } else {
        Write-Skip "claude: ~/.claude not found"
    }
}

if (Test-Want "cursor") {
    if (Test-Path (Join-Path $HomeDir ".cursor")) {
        $detectedAny = $true
        Link-Skill (Join-Path $HomeDir ".cursor\skills") "cursor"
    } else {
        Write-Skip "cursor: ~/.cursor not found"
    }
}

if (Test-Want "agents") {
    $detectedAny = $true
    Link-Skill (Join-Path $HomeDir ".agents\skills") "agents (shared)"
}

if (Test-Want "hermes") {
    if (Test-Path (Join-Path $HomeDir ".hermes")) {
        $detectedAny = $true
        Link-Skill (Join-Path $HomeDir ".hermes\skills") "hermes"
        Install-HermesPanel
    } else {
        Write-Skip "hermes: ~/.hermes not found"
    }
}

if (-not $detectedAny) {
    Write-Host "No supported client directory detected. Install Claude Code, Cursor, or Hermes first,"
    Write-Host "or link manually: New-Item -ItemType Junction -Path <client-skills-dir>\$SkillName -Value `"$SkillSource`""
}

Write-Host ""
Write-Host "Next step: configure your 88API image-generation group key:"
Write-Host "  node `"$RepoRoot\plugins\88api-image-gen\scripts\generate.mjs`" --set-key `"<YOUR_88API_IMAGE_GROUP_KEY>`""
Write-Host "  node `"$RepoRoot\plugins\88api-image-gen\scripts\generate.mjs`" --get-config"
