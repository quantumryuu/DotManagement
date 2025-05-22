function Remove-Dot {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$SourcePath,

        [switch]$Force
    )
    # Ensure the script is run as Administrator
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
                [Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "❌ This script must be run as Administrator to create symlinks." -ForegroundColor Red
        return
    }
    $homePath = [Environment]::GetFolderPath('UserProfile')
    $dotfilesPath = Join-Path $homePath 'dotfiles'
    $configPath = Join-Path $dotfilesPath 'dotfiles.config.json'

    if (-not (Test-Path $configPath)) {
        Write-Host "❌ Config file not found. Run Init-Dots first." -ForegroundColor Red
        return
    }

    try {
        $SourceFull = (Resolve-Path $SourcePath).Path
    }
    catch {
        Write-Host "❌ Source path '$SourcePath' does not exist." -ForegroundColor Red
        return
    }

    if ($SourceFull.StartsWith($homePath)) {
        $relativePath = $SourceFull.Substring($homePath.Length).TrimStart('\', '/')
    }
    else {
        $relativePath = Split-Path -Leaf $SourceFull
    }

    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Host "❌ Failed to parse config JSON. $_" -ForegroundColor Red
        return
    }

    if (-not $config.Files) {
        Write-Host "❌ No files tracked in config." -ForegroundColor Red
        return
    }
    elseif ($config.Files -is [PSCustomObject]) {
        $tempHash = @{}
        foreach ($prop in $config.Files.PSObject.Properties) {
            $tempHash[$prop.Name] = $prop.Value
        }
        $config.Files = $tempHash
    }

    if (-not $config.Files.ContainsKey($relativePath)) {
        Write-Host "❌ '$relativePath' is not tracked in dotfiles config." -ForegroundColor Red
        return
    }

    $dotfilePath = Join-Path $dotfilesPath $relativePath

    # Check if dotfile exists in repo
    if (-not (Test-Path $dotfilePath)) {
        Write-Host "❌ Dotfile not found in repo at '$dotfilePath'." -ForegroundColor Red
        return
    }

    # Check original path existence
    $sourceExists = Test-Path $SourceFull -PathType Any

    if (-not $sourceExists) {
        Write-Host "⚠️ Original path '$SourceFull' does not exist." -ForegroundColor Yellow
        if (-not $Force) {
            Write-Host "Aborting. Use -Force to override." -ForegroundColor Red 
            return
        }
    }
    else {
        $item = Get-Item -LiteralPath $SourceFull -Force

        $isSymlink = $false
        try {
            $isSymlink = $item.Attributes.ToString().Contains("ReparsePoint")
        }
        catch {
            # Some filesystem types might cause errors, assume false
            $isSymlink = $false
        }

        if (-not $isSymlink) {
            Write-Host "⚠️ The original path exists and is NOT a symlink. Removing it could cause data loss." -ForegroundColor Yellow
            if (-not $Force) {
                Write-Host "Aborting. Use -Force to override." -ForegroundColor Yellow
                return
            }
            else {
                Write-Host "⚠️ -Force supplied. Proceeding to remove original file/folder." -ForegroundColor Yellow
            }
        }
    }

    # Confirm destructive action
    if (-not $Force) {
        $confirm = Read-Host "Are you sure you want to remove the symlink and restore the original file? (Y/N)"
        if ($confirm -notin @('Y', 'y')) {
            Write-Host "Operation cancelled by user." -ForegroundColor Yellow
            return
        }
    }

    # Remove symlink or file at original location
    try {
        Remove-Item -LiteralPath $SourceFull -Force -Recurse
        Write-Host "✅ Removed existing item at '$SourceFull'." -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Failed to remove item at '$SourceFull'. $_" -ForegroundColor Red
        return
    }

    # Ensure original folder exists before moving back
    $origFolder = Split-Path -Parent $SourceFull
    if (-not (Test-Path $origFolder)) {
        try {
            New-Item -ItemType Directory -Path $origFolder -Force | Out-Null
            Write-Host "✅ Created folder '$origFolder'." -ForegroundColor Green
        }
        catch {
            Write-Host "❌ Failed to create folder '$origFolder'. $_" -ForegroundColor Red
            return
        }
    }

    # Move dotfile back to original location
    try {
        Move-Item -Path $dotfilePath -Destination $SourceFull -Force
        Write-Host "✅ Moved dotfile back to original location: '$SourceFull'." -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Failed to move dotfile back. $_" -ForegroundColor Red
        return
    }

    # Remove from config
    $config.Files.Remove($relativePath)

    # Save config
    try {
        $config | ConvertTo-Json -Depth 5 | Set-Content -Path $configPath -Encoding UTF8
        Write-Host "✅ Updated config and removed entry for '$relativePath'." -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Failed to save config JSON. $_" -ForegroundColor Red
        return
    }
}
