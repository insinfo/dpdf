# Fetch the pinned ITI corpus into ignored test cache. No machine trust store is changed.
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$cacheRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot '.dart_tool/iti_assets'))
$manifestPath = Join-Path $projectRoot 'test/pki/iti_corpus_manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
[IO.Directory]::CreateDirectory($cacheRoot) | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem

foreach ($archive in $manifest.archives) {
    $zipPath = Join-Path $cacheRoot ($archive.name + '.zip')
    if (-not (Test-Path -LiteralPath $zipPath)) {
        Invoke-WebRequest -Uri $archive.url -OutFile $zipPath
    }
    $actual = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA512).Hash.ToLowerInvariant()
    if ($actual -ne $archive.sha512 -or (Get-Item -LiteralPath $zipPath).Length -ne $archive.size) {
        throw "Archive differs from the reviewed snapshot: $($archive.name). Review the upstream update before changing the manifest."
    }
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $entries = @($zip.Entries | Where-Object { $_.Name -ne '' })
        if ($entries.Count -ne $archive.files.Count) { throw 'Archive file count differs from manifest.' }
        foreach ($expected in $archive.files) {
            $relative = $expected.path.Substring($archive.name.Length + 1)
            $matches = @($entries | Where-Object { $_.FullName -eq $relative })
            if ($matches.Count -ne 1) { throw "Missing or repeated ZIP member: $relative" }
            $entry = $matches[0]
            if ($entry.Length -ne $expected.size) { throw "Unexpected member size: $relative" }
            $destination = [IO.Path]::GetFullPath((Join-Path $cacheRoot $expected.path))
            $prefix = $cacheRoot + [IO.Path]::DirectorySeparatorChar
            if (-not $destination.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Archive destination is outside the test cache.'
            }
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
            $inputStream = $entry.Open()
            $memory = [IO.MemoryStream]::new()
            try {
                $inputStream.CopyTo($memory)
                $bytes = $memory.ToArray()
                $sha = [Security.Cryptography.SHA256]::Create()
                try { $digest = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant() }
                finally { $sha.Dispose() }
                if ($digest -ne $expected.sha256) { throw "Member hash differs: $relative" }
                [IO.File]::WriteAllBytes($destination, $bytes)
            } finally { $inputStream.Dispose(); $memory.Dispose() }
        }
    } finally { $zip.Dispose() }
    Write-Output ("Verified {0}: {1} files" -f $archive.name, $archive.files.Count)
}
Write-Output 'Run: dart test test/pki/iti_official_corpus_test.dart'
