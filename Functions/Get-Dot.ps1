function Get-Dot {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Repo,

        [switch]$Force
    )

    $homePath = [Environment]::GetFolderPath('UserProfile')
    $dotfilesPath = Join-Path $homePath 'dotfiles'
    $configPath = Join-Path $dotfilesPath 'dotfiles.config.json'
    $backupFolder = Join-Path $dotfilesPath 'backups'

    # Determine full repo URL
    $repoUrl = if ($Repo -match '^https?://|^git@') { $Repo } else { "https://github.com/$Repo/dotfiles.git" }

    # Remove existing dotfiles folder if -Force is specified
    if ($Force -and (Test-Path $dotfilesPath)) {
        Write-Output "🗑️ Removing existing dotfiles folder at $dotfilesPath due to -Force switch..."
        try {
            Remove-Item -Path $dotfilesPath -Recurse -Force -ErrorAction Stop
            Write-Output "✅ Removed existing dotfiles folder."
        } catch {
            Write-Output "❌ Failed to remove dotfiles folder. $_"
            return
        }
    }

    # Fail if dotfiles folder exists and -Force was not provided
    if (Test-Path $dotfilesPath) {
        Write-Output "❌ Dotfiles folder already exists. Use -Force to overwrite it."
        return
    }

    # Clone repo
    Write-Output "📥 Cloning $repoUrl into $dotfilesPath..."
    git clone $repoUrl $dotfilesPath
    if ($LASTEXITCODE -ne 0) {
        Write-Output "❌ Git clone failed."
        return
    }

    # Load config
    if (-not (Test-Path $configPath)) {
        Write-Output "❌ Config file not found at $configPath."
        return
    }

    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
    } catch {
        Write-Output "❌ Failed to parse config JSON. $_"
        return
    }

    if (-not $config.Files) {
        Write-Output "⚠️ No files mapped in config."
        return
    }

    # Ensure hash format
    if ($config.Files -is [PSCustomObject]) {
        $tempHash = @{}
        foreach ($prop in $config.Files.PSObject.Properties) {
            $tempHash[$prop.Name] = $prop.Value
        }
        $config.Files = $tempHash
    }

    # Prepare backup structure
    if (-not (Test-Path $backupFolder)) {
        New-Item -Path $backupFolder -ItemType Directory -Force | Out-Null
    }
    $backupZip = Join-Path $backupFolder ("backup_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".zip")
    $backupStaging = Join-Path $backupFolder "staging"
    New-Item -Path $backupStaging -ItemType Directory -Force | Out-Null

    # Process each mapping
    foreach ($relativePath in $config.Files.Keys) {
        $linkPath = $config.Files[$relativePath]
        $dotfileFullPath = Join-Path $dotfilesPath $relativePath

        $linkPathResolved = if ($linkPath -like '$HOME*') {
            Join-Path $homePath $linkPath.Substring(5).TrimStart('\', '/')
        } else {
            $linkPath
        }

        # Backup and remove existing non-symlink items
        if (Test-Path $linkPathResolved) {
            $existingItem = Get-Item $linkPathResolved -Force
            $isSymlink = $existingItem.Attributes.ToString().Contains("ReparsePoint")

            if (-not $isSymlink) {
                $backupDest = Join-Path $backupStaging ([IO.Path]::GetFileName($linkPathResolved))
                try {
                    Copy-Item $linkPathResolved -Destination $backupDest -Recurse -Force
                    Write-Output "📦 Backed up $linkPathResolved"
                } catch {
                    Write-Output "❌ Failed to backup $linkPathResolved"
                    continue
                }
            }
            Remove-Item $linkPathResolved -Force -Recurse
        } else {
            $parentDir = Split-Path -Parent $linkPathResolved
            if (-not (Test-Path $parentDir)) {
                New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
            }
        }

        # Create symlink
        try {
            New-Item -ItemType SymbolicLink -Path $linkPathResolved -Target $dotfileFullPath -Force | Out-Null
            Write-Output "✅ Linked '$linkPathResolved' -> '$dotfileFullPath'"
        } catch {
            Write-Output "❌ Failed to link '$linkPathResolved'. $_"
        }
    }

    # Archive backup if needed
    if ((Get-ChildItem $backupStaging).Count -gt 0) {
        Compress-Archive -Path "$backupStaging\*" -DestinationPath $backupZip -Force
        Remove-Item $backupStaging -Recurse -Force
        Write-Output "📦 Backup saved to $backupZip"
    } else {
        Remove-Item $backupStaging -Recurse -Force
        Write-Output "🧹 No backups needed."
    }
}
