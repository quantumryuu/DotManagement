function Remove-Dot {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$SourcePath,

        [switch]$Force
    )

    $homePath = [Environment]::GetFolderPath('UserProfile')
    $dotfilesPath = Join-Path $homePath 'dotfiles'
    $configPath = Join-Path $dotfilesPath 'dotfiles.config.json'

    if (-not (Test-Path $configPath)) {
        Write-Output "❌ Config file not found. Run Init-Dots first." -ForegroundColor Red
        return
    }

    try {
        $SourceFull = (Resolve-Path $SourcePath).Path
    }
    catch {
        Write-Output "❌ Source path '$SourcePath' does not exist." -ForegroundColor Red
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
        Write-Output "❌ Failed to parse config JSON. $_" -ForegroundColor Red
        return
    }

    if (-not $config.Files) {
        Write-Output "❌ No files tracked in config." -ForegroundColor Red
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
        Write-Output "❌ '$relativePath' is not tracked in dotfiles config." -ForegroundColor Red
        return
    }

    $dotfilePath = Join-Path $dotfilesPath $relativePath

    # Check if dotfile exists in repo
    if (-not (Test-Path $dotfilePath)) {
        Write-Output "❌ Dotfile not found in repo at '$dotfilePath'." -ForegroundColor Red
        return
    }

    # Check original path existence
    $sourceExists = Test-Path $SourceFull -PathType Any

    if (-not $sourceExists) {
        Write-Output "⚠️ Original path '$SourceFull' does not exist."
        if (-not $Force) {
            Write-Output "Aborting. Use -Force to override." -ForegroundColor Yellow
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
            Write-Output "⚠️ The original path exists and is NOT a symlink. Removing it could cause data loss."
            if (-not $Force) {
                Write-Output "Aborting. Use -Force to override." -ForegroundColor Yellow
                return
            }
            else {
                Write-Output "⚠️ -Force supplied. Proceeding to remove original file/folder."
            }
        }
    }

    # Confirm destructive action
    if (-not $Force) {
        $confirm = Read-Host "Are you sure you want to remove the symlink and restore the original file? (Y/N)"
        if ($confirm -notin @('Y','y')) {
            Write-Output "Operation cancelled by user."
            return
        }
    }

    # Remove symlink or file at original location
    try {
        Remove-Item -LiteralPath $SourceFull -Force -Recurse
        Write-Output "✅ Removed existing item at '$SourceFull'."
    }
    catch {
        Write-Output "❌ Failed to remove item at '$SourceFull'. $_" -ForegroundColor Red
        return
    }

    # Ensure original folder exists before moving back
    $origFolder = Split-Path -Parent $SourceFull
    if (-not (Test-Path $origFolder)) {
        try {
            New-Item -ItemType Directory -Path $origFolder -Force | Out-Null
            Write-Output "✅ Created folder '$origFolder'."
        }
        catch {
            Write-Output "❌ Failed to create folder '$origFolder'. $_" -ForegroundColor Red
            return
        }
    }

    # Move dotfile back to original location
    try {
        Move-Item -Path $dotfilePath -Destination $SourceFull -Force
        Write-Output "✅ Moved dotfile back to original location: '$SourceFull'."
    }
    catch {
        Write-Output "❌ Failed to move dotfile back. $_" -ForegroundColor Red
        return
    }

    # Remove from config
    $config.Files.Remove($relativePath)

    # Save config
    try {
        $config | ConvertTo-Json -Depth 5 | Set-Content -Path $configPath -Encoding UTF8
        Write-Output "✅ Updated config and removed entry for '$relativePath'."
    }
    catch {
        Write-Output "❌ Failed to save config JSON. $_" -ForegroundColor Red
        return
    }
}
