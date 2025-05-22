function Add-Dot {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$SourcePath
    )
    # Ensure the script is run as Administrator
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
                [Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "❌ This script must be run as Administrator to create symlinks." -ForegroundColor Red
        return
    }
    # Get robust current user home path
    $homePath = [Environment]::GetFolderPath('UserProfile')
    $dotfilesPath = Join-Path $homePath 'dotfiles'
    $configPath = Join-Path $dotfilesPath 'dotfiles.config.json'

    if (-not (Test-Path $dotfilesPath)) {
        Write-Host "❌ Dotfiles repo folder not found. Please run Get-Dot first." -ForegroundColor Red
        return
    }

    if (-not (Test-Path $SourcePath)) {
        Write-Host "❌ Source path '$SourcePath' does not exist." -ForegroundColor Red
        return
    }

    # Resolve full path of the source file/folder
    $SourceFull = (Resolve-Path $SourcePath).Path

    # Determine relative path inside dotfiles repo and link path with $HOME if applicable
    if ($SourceFull.StartsWith($homePath)) {
        # Relative path inside user's home folder
        $relativePath = $SourceFull.Substring($homePath.Length).TrimStart('\', '/')
        $destPath = Join-Path $dotfilesPath $relativePath
        $linkPath = Join-Path '$HOME' $relativePath
    }
    # else {
    # Outside home: flatten filename inside dotfiles root
    $relativePath = Split-Path -Leaf $SourceFull
    $destPath = Join-Path $dotfilesPath $relativePath
    $linkPath = $SourceFull

    # Check if the link path already exists in config and on disk as a symlink or file
    if (Test-Path $SourceFull) {
        # Load config JSON
        $config = @{}
        if (Test-Path $configPath) {
            try {
                $config = Get-Content $configPath -Raw | ConvertFrom-Json
            }
            catch {
                Write-Host "❌ Failed to parse config JSON. $_" -ForegroundColor Red
                return
            }
        }

        # Convert Files PSCustomObject to hashtable if necessary
        if (-not $config.Files) {
            $config.Files = @{}
        }
        elseif ($config.Files -is [PSCustomObject]) {
            $tempHash = @{}
            foreach ($prop in $config.Files.PSObject.Properties) {
                $tempHash[$prop.Name] = $prop.Value
            }
            $config.Files = $tempHash
        }

        if ($config.Files.ContainsKey($relativePath)) {
            Write-Host "⚠️ The file/folder '$relativePath' already exists in dotfiles config." -ForegroundColor Yellow
            Write-Host "Please use Remove-Dots to remove it before adding again." -ForegroundColor Yellow
            return
        }
    }

    # Ensure destination directory exists
    $destDir = Split-Path $destPath
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    # If destination exists, ask to overwrite
    if (Test-Path $destPath) {
        Write-Host "⚠️ '$relativePath' already exists in dotfiles repo. Overwrite? (Y/N)" -ForegroundColor Yellow
        $response = Read-Host
        if ($response -notin @('Y', 'y')) {
            Write-Host "Operation cancelled by user." -ForegroundColor Red
            return
        }
        Remove-Item -Recurse -Force $destPath
    }

    # Move the file/folder into dotfiles repo
    try {
        Move-Item -Path $SourceFull -Destination $destPath -Force
    }
    catch {
        Write-Host "❌ Failed to move '$SourceFull' to dotfiles repo. $_" -ForegroundColor Red
        return
    }

    # Remove any existing item at source (should be gone after move, but just in case)
    if (Test-Path $SourceFull) {
        Remove-Item -Recurse -Force $SourceFull
    }

    # Create parent folder of source path if missing (rare)
    $sourceParent = Split-Path $SourceFull
    if (-not (Test-Path $sourceParent)) {
        New-Item -ItemType Directory -Path $sourceParent -Force | Out-Null
    }

    # Create symlink (directory or file) at original location
    $item = Get-Item $destPath
    try {
        if ($item.PSIsContainer) {
            # Directory symlink
            New-Item -ItemType SymbolicLink -Path $SourceFull -Target $destPath -Force | Out-Null
        }
        else {
            # File symlink
            New-Item -ItemType SymbolicLink -Path $SourceFull -Target $destPath -Force | Out-Null
        }
    }
    catch {
        Write-Host "❌ Failed to create symlink. $_" -ForegroundColor Red
        return
    }

    Write-Host "✅ Moved '$SourceFull' to dotfiles repo and linked back at original location." -ForegroundColor Green

    # Reload config if not loaded
    if (-not $config) {
        $config = @{}
        if (Test-Path $configPath) {
            try {
                $config = Get-Content $configPath -Raw | ConvertFrom-Json
            }
            catch {
                Write-Host "❌ Failed to parse config JSON. $_" -ForegroundColor Red
                return
            }
        }
    }

    # Ensure Files property exists and is a hashtable
    if (-not $config.Files) {
        $config.Files = @{}
    }
    elseif ($config.Files -is [PSCustomObject]) {
        $tempHash = @{}
        foreach ($prop in $config.Files.PSObject.Properties) {
            $tempHash[$prop.Name] = $prop.Value
        }
        $config.Files = $tempHash
    }

    # Add new mapping (relativePath => linkPath)
    $config.Files[$relativePath] = $linkPath

    # Save updated config
    try {
        $config | ConvertTo-Json -Depth 5 | Set-Content $configPath -Encoding UTF8
    }
    catch {
        Write-Host "❌ Failed to save config JSON. $_" -ForegroundColor Red
        return
    }

    Write-Host "✅ Updated config file with new mapping." -ForegroundColor Green
}