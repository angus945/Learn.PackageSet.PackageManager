[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("validate", "materialize", "use-development", "use-distribution")]
    [string]$Command = "validate",

    [Parameter(Position = 1)]
    [string]$Identity
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ManifestPath = Join-Path $RepoRoot "package-set.json"

function Fail([string]$Message) {
    throw "[PackageSet] $Message"
}

function Invoke-Git([string[]]$Arguments, [string]$WorkingDirectory = $RepoRoot) {
    $output = & git -C $WorkingDirectory @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        Fail ("git {0} failed: {1}" -f ($Arguments -join " "), ($output -join [Environment]::NewLine))
    }
    return @($output)
}

function Read-Manifest {
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        Fail "Missing manifest: $ManifestPath"
    }
    return Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
}

function Resolve-TargetRoot($Manifest) {
    $configured = [string]$Manifest.target.unityProjectRelativePath
    if ([string]::IsNullOrWhiteSpace($configured)) {
        Fail "target.unityProjectRelativePath is required."
    }
    $path = Join-Path $RepoRoot $configured
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        Fail "Unity target root does not exist: $path"
    }
    return (Resolve-Path -LiteralPath $path).Path
}

function Get-Entries($Manifest) {
    $entries = @($Manifest.entries)
    if (-not [string]::IsNullOrWhiteSpace($Identity)) {
        $entries = @($entries | Where-Object { $_.identity -eq $Identity })
        if ($entries.Count -eq 0) {
            Fail "Unknown entry identity: $Identity"
        }
    }
    return $entries
}

function Get-SourcePath($Entry) {
    $relative = [string]$Entry.sourcePath
    if ([string]::IsNullOrWhiteSpace($relative)) {
        Fail "$($Entry.identity): sourcePath is required."
    }
    return Join-Path $RepoRoot $relative
}

function Get-ProjectionPath($Manifest, $Entry, [string]$TargetRoot) {
    $root = [string]$Manifest.managedProjectionRoot
    $leaf = [string]$Entry.projectionName
    if ([string]::IsNullOrWhiteSpace($root)) { Fail "managedProjectionRoot is required." }
    if ([string]::IsNullOrWhiteSpace($leaf)) { Fail "$($Entry.identity): projectionName is required." }

    $managedRoot = [System.IO.Path]::GetFullPath((Join-Path $TargetRoot $root))
    $projection = [System.IO.Path]::GetFullPath((Join-Path $managedRoot $leaf))
    $prefix = $managedRoot.TrimEnd([char]92, [char]47) + [System.IO.Path]::DirectorySeparatorChar

    if (-not $projection.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        Fail "$($Entry.identity): projection escapes managed root: $projection"
    }
    return $projection
}

function Get-SubmoduleStatus([string]$SourceRelativePath) {
    $lines = Invoke-Git @("submodule", "status", "--", $SourceRelativePath)
    if ($lines.Count -ne 1) { Fail "Expected one submodule status line for $SourceRelativePath." }
    $line = [string]$lines[0]
    if ($line.Length -lt 41) { Fail "Unexpected submodule status for $SourceRelativePath: $line" }
    return @{ Prefix = $line.Substring(0, 1); Revision = $line.Substring(1, 40); Raw = $line }
}

function Assert-EntryValid($Manifest, $Entry, [string]$TargetRoot, [switch]$RequireClean) {
    $identity = [string]$Entry.identity
    $sourceRelative = [string]$Entry.sourcePath
    $sourcePath = Get-SourcePath $Entry
    $projectionPath = Get-ProjectionPath $Manifest $Entry $TargetRoot

    if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
        Fail "$identity: source checkout is missing: $sourcePath"
    }

    $status = Get-SubmoduleStatus $sourceRelative
    switch ($status.Prefix) {
        " " { }
        "-" { Fail "$identity: submodule is declared but not initialized." }
        "+" { Fail "$identity: submodule checkout does not match the PackageSet gitlink." }
        "U" { Fail "$identity: submodule gitlink is conflicted." }
        default { Fail "$identity: unsupported submodule status $($status.Prefix)." }
    }

    $head = ((Invoke-Git @("rev-parse", "HEAD") $sourcePath)[0]).Trim()
    if ($head -ne $status.Revision) {
        Fail "$identity: checkout HEAD $head does not match gitlink $($status.Revision)."
    }

    if ($RequireClean) {
        $dirty = Invoke-Git @("status", "--porcelain") $sourcePath
        if ($dirty.Count -gt 0) {
            Fail "$identity: source working tree is dirty. Commit or revert changes before materialization."
        }
    }

    return @{ Identity = $identity; SourcePath = $sourcePath; ProjectionPath = $projectionPath; Revision = $status.Revision }
}

function Remove-Projection([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        & cmd /c rmdir "$Path"
        if ($LASTEXITCODE -ne 0) { Fail "Failed to remove junction: $Path" }
        return
    }
    Remove-Item -LiteralPath $Path -Recurse -Force
}

function Copy-SourceProjection([string]$SourcePath, [string]$ProjectionPath) {
    $temp = "$ProjectionPath.__packageset_tmp"
    Remove-Projection $temp
    New-Item -ItemType Directory -Path $temp -Force | Out-Null

    & robocopy $SourcePath $temp /MIR /XD .git /XF .git .packageset-provenance.json /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { Fail "robocopy failed with exit code $LASTEXITCODE." }

    Remove-Projection $ProjectionPath
    Move-Item -LiteralPath $temp -Destination $ProjectionPath
}

function Write-Provenance($Entry, $Validated) {
    $sourceUrl = ((Invoke-Git @("remote", "get-url", "origin") $Validated.SourcePath)[0]).Trim()
    $provenance = [ordered]@{
        schemaVersion = 1
        identity = [string]$Entry.identity
        packageSet = "PackageSet.Learn.PackageManager"
        sourceRepository = $sourceUrl
        sourceRevision = $Validated.Revision
        projectionKind = "UnityAssets"
    }
    $json = $provenance | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath (Join-Path $Validated.ProjectionPath ".packageset-provenance.json") -Value $json -Encoding UTF8
}

function Materialize($Manifest, $Entry, [string]$TargetRoot) {
    $validated = Assert-EntryValid $Manifest $Entry $TargetRoot -RequireClean
    $parent = Split-Path -Parent $validated.ProjectionPath
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Copy-SourceProjection $validated.SourcePath $validated.ProjectionPath
    Write-Provenance $Entry $validated
    Write-Host "[PackageSet] Materialized $($validated.Identity) @ $($validated.Revision)"
}

function Use-Development($Manifest, $Entry, [string]$TargetRoot) {
    $validated = Assert-EntryValid $Manifest $Entry $TargetRoot
    $parent = Split-Path -Parent $validated.ProjectionPath
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Remove-Projection $validated.ProjectionPath
    & cmd /c mklink /J "$($validated.ProjectionPath)" "$($validated.SourcePath)" | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "$($validated.Identity): failed to create development junction." }
    Write-Host "[PackageSet] Development source active: $($validated.Identity)"
}

$manifest = Read-Manifest
$targetRoot = Resolve-TargetRoot $manifest
$entries = Get-Entries $manifest

if ($entries.Count -eq 0) {
    Write-Host "[PackageSet] Manifest is valid but contains no managed entries yet."
    Write-Host "Add the first private repository as a submodule under Sources/, then add one manifest entry."
    exit 0
}

switch ($Command) {
    "validate" {
        foreach ($entry in $entries) {
            $validated = Assert-EntryValid $manifest $entry $targetRoot
            Write-Host "[PackageSet] Valid: $($validated.Identity) @ $($validated.Revision)"
        }
    }
    "materialize" { foreach ($entry in $entries) { Materialize $manifest $entry $targetRoot } }
    "use-development" { foreach ($entry in $entries) { Use-Development $manifest $entry $targetRoot } }
    "use-distribution" { foreach ($entry in $entries) { Materialize $manifest $entry $targetRoot } }
}
