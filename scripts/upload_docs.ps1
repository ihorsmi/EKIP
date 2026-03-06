\
    param(
      [string]$ApiBase = "http://localhost:8000",
      [string]$DocDir = ".\data\sample_docs"
    )

    Write-Host "Uploading docs from: $DocDir -> $ApiBase/upload"
    Get-ChildItem -Path $DocDir -File | ForEach-Object {
      Write-Host (" - " + $_.Name)
      curl.exe -sS -F ("file=@" + $_.FullName) ($ApiBase + "/upload") | Out-String | Write-Host
    }
    Write-Host "Done."
