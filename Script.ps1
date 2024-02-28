Add-Type -Path "F:\Windows Files\Program Files\Scripts\Soulseek to Lidarr\taglib-sharp.dll" #Path That conatins this script

$sourcePath = 'F:\Download\Soulseek\complete NEW\complete'#  Soulseek complete download directory
$targetBasePath = 'F:\Media\Audio\Music\Music - Managed (Lidarr)'#  the directory that holds your genre folders for lidarr
$holdingPath = 'F:\Media\Audio\Music\Holding\Soulseek Waiting Lidarr Import' #holding directory for unmatched artists
$logPath = 'F:\Windows Files\Program Files\Scripts\Soulseek to Lidarr\music-organizer-log.txt'# path to this script


$apiKey = "Your API Key"
$lidarrHost = "http://localhost:8686"
$headers = @{ "X-Api-Key" = $apiKey }

$extensions = 'mp3', 'wav', 'aac', 'flac', 'm4a', 'alac', 'ogg', 'wma', 'aif', 'aiff', 'ape', 'dsf', 'dff', 'midi', 'mid', 'opus'

function Write-Log {
    Param ([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logPath -Value "[$timestamp] $message"
}



function Lookup-ArtistID {
    param ([string]$artistName)
    $encodedArtistName = [uri]::EscapeDataString($artistName)
    $response = Invoke-RestMethod -Uri "$lidarrHost/api/v1/artist/lookup?term=$encodedArtistName" -Method Get -Headers $headers
    if ($response.Count -gt 0) {
        $artistId = $response[0].id
        Write-Log "Artist ID found for '$artistName': $artistId"
        return $artistId
    } else {
        Write-Log "No artist found with the name '$artistName'."
        return $null
    }
}

function Retag-Files {
    param ([string]$artistId)
    $uri = "$lidarrHost/api/v1/retag?artistId=${artistId}"
    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
        foreach ($item in $response) {
            $path = $item.path
            $file = [TagLib.File]::Create($path)
            foreach ($change in $item.changes) {
                $propertyName = $change.field -replace ' ', ''
                $newValue = $change.newValue
                if ($file.Tag.PSObject.Properties.Name -contains $propertyName) {
                    $file.Tag.$propertyName = $newValue
                }
            }
            $parentDirectory = Split-Path -Path $artistPath -Parent
            $genre = (Split-Path -Path $parentDirectory -Leaf)
            $file.Tag.Genres = @($genre)
            $file.Save()
            Write-Host "Successfully updated tags for file: $path"
        }
    } catch {
        Write-Error "Failed to fetch retag information or update tags: $_"
    }
}

function Process-Files {
    param ([string]$artistId)
    $uri = "$Lidarrhost/api/v1/rename?artistId=${artistId}"
    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
        foreach ($item in $response) {
            $existingPath = $item.existingPath
            $newPath = $item.newPath
            $newDir = [System.IO.Path]::GetDirectoryName($newPath)
            if (-not (Test-Path -Path $newDir)) {
                New-Item -ItemType Directory -Path $newDir -Force | Out-Null
                Write-Host "Created directory: $newDir"
            }
            Move-Item -Path $existingPath -Destination $newPath -Force
            Write-Host "Successfully moved and renamed file to: $newPath"
        }
    } catch {
        Write-Error "Failed to fetch rename information or process files: $_"
    }
}

function Trigger-LidarrRescan {
    param ([string]$path)
    $body = @{
        name = "RescanFolders"
        folders = @($path)
    } | ConvertTo-Json
    $response = Invoke-RestMethod -Uri "$lidarrHost/api/v1/command" -Method Post -Headers $headers -Body $body -ContentType "application/json"
    $commandId = $response.id
    do {
        Start-Sleep -Seconds 5
        $commandStatusResponse = Invoke-RestMethod -Uri "$lidarrHost/api/v1/command/$commandId" -Method Get -Headers $headers
    } while ($commandStatusResponse.status -ne "completed")
    Write-Log "Lidarr rescan completed for $path"
}

$dryRun = $false

$files = Get-ChildItem -Path $sourcePath -Recurse | Where-Object { $_.Extension -replace '\.', '' -in $extensions }
$groupedFiles = $files | Group-Object { [TagLib.File]::Create($_.FullName).Tag.FirstPerformer }

foreach ($group in $groupedFiles) {
    $artist = $group.Name
    $artistDirectory = Get-ChildItem -Path $targetBasePath -Directory -Recurse | Where-Object { $_.Name -eq $artist } | Select-Object -First 1
    $isInHoldingPath = $false
    if ($artistDirectory) {
        $artistPath = $artistDirectory.FullName
    } else {
        $artistPath = Join-Path -Path $holdingPath -ChildPath $artist
        $isInHoldingPath = $true
        if (-not $dryRun) { $null = New-Item -Path $artistPath -ItemType Directory -Force }
        Write-Log "Fallback created artist directory: $artistPath"
    }
    foreach ($file in $group.Group) {
        try {
            $tagFile = [TagLib.File]::Create($file.FullName)
            $album = $tagFile.Tag.Album
            if (-not $album) {
                Write-Log "Skipping file due to missing album tag: $($file.FullName)"
                continue
            }
            $albumDirectory = Join-Path -Path $artistPath -ChildPath $album
            if (-not (Test-Path -Path $albumDirectory)) {
                if (-not $dryRun) { $null = New-Item -Path $albumDirectory -ItemType Directory -Force }
                Write-Log "Created album directory: $albumDirectory"
            }
            $destination = Join-Path -Path $albumDirectory -ChildPath $file.Name
            if (-not $dryRun) {
                Move-Item -Path $file.FullName -Destination $destination -Force
                Write-Log "Moved file from $($file.FullName) to $destination"
            }
        } catch {
            Write-Log "Error processing file $($file.FullName): $_"
        }
    }

    Trigger-LidarrRescan -path $artistPath

    $artistId = Lookup-ArtistID -artistName $artist

    Process-Files -artistId $artistId

    Retag-Files -artistId $artistId

    Trigger-LidarrRescan -path $artistPath
}

Write-Host "Operation completed. Please check the log file at $logPath for details."
