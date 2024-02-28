do {
    # Load the configuration
    $config = Get-Content -Path 'F:\Windows Files\Program Files\Scripts\Soulseek to Lidarr\AutoRunFrequency.json' | ConvertFrom-Json

    # Reference and execute the external script
    & 'F:\Windows Files\Program Files\Scripts\Soulseek to Lidarr\Script.ps1'

    # Wait for the specified duration before repeating
    Start-Sleep -Seconds ($config.frequencyMinutes * 60)
} while ($true)
