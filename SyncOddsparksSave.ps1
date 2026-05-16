#requires -version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string] $World,
    [Parameter(Mandatory=$true)] [string] $Player,
    [Parameter(Mandatory=$true)] [string] $FolderUrl,

    # Recommended: downloaded OAuth Desktop app JSON from Google Cloud.
    [string] $ClientJson = "",

    # Alternative to ClientJson.
    [string] $ClientId = "",
    [string] $ClientSecret = "",

    [ValidateSet("auto", "status", "pull", "push", "login", "logout")] [string] $Mode = "auto",
    [string] $LocalDir = (Join-Path $env:LOCALAPPDATA "Oddsparks\Full\Savegames"),
    [string] $BackupDir = (Join-Path $env:LOCALAPPDATA "Oddsparks\Full\SavegamesBackups"),
    [int] $RedirectPort = 53682,
    [switch] $DryRun
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptVersion = "oauth-simple-v2"
$DriveFolderMime = "application/vnd.google-apps.folder"
$DriveScope = "https://www.googleapis.com/auth/drive"
$TokenUri = "https://oauth2.googleapis.com/token"
$AuthUri = "https://accounts.google.com/o/oauth2/v2/auth"

function Info([string] $Text) { Write-Host "[INFO] $Text" }
function Warn([string] $Text) { Write-Host "[WARN] $Text" -ForegroundColor Yellow }
function Fail([string] $Text) { Write-Host "[ERR ] $Text" -ForegroundColor Red }

function Prop($Obj, [string] $Name) {
    if ($null -eq $Obj) { return $null }
    if ($Obj.PSObject.Properties.Name -contains $Name) { return $Obj.$Name }
    return $null
}

function Url([string] $Text) { return [System.Uri]::EscapeDataString($Text) }

function FormBody([hashtable] $Pairs) {
    return (($Pairs.GetEnumerator() | ForEach-Object { "$(Url ([string]$_.Key))=$(Url ([string]$_.Value))" }) -join "&")
}

function ShaText([string] $Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return (([BitConverter]::ToString($sha.ComputeHash($bytes))) -replace "-", "").ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function ShaFile([string] $Path) { return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() }

function B64Url([byte[]] $Bytes) { return ([Convert]::ToBase64String($Bytes)).TrimEnd("=").Replace("+", "-").Replace("/", "_") }

function RandomB64Url([int] $BytesCount) {
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $bytes = New-Object byte[] $BytesCount
        $rng.GetBytes($bytes)
        return B64Url $bytes
    }
    finally { $rng.Dispose() }
}

function CodeChallenge([string] $Verifier) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return B64Url ($sha.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($Verifier))) }
    finally { $sha.Dispose() }
}

function ErrorText($Exception) {
    $msg = $Exception.Message
    if ($Exception.PSObject.Properties.Name -contains "Response") {
        $resp = $Exception.Response
        if ($null -ne $resp) {
            try {
                $stream = $resp.GetResponseStream()
                if ($null -ne $stream) {
                    $reader = New-Object System.IO.StreamReader($stream)
                    $body = $reader.ReadToEnd()
                    if (-not [string]::IsNullOrWhiteSpace($body)) { return "$msg`n$body" }
                }
            } catch { }
        }
    }
    return $msg
}

function ExtractFolderId([string] $Value) {
    if ($Value -match "/folders/([^/?#]+)") { return $Matches[1] }
    if ($Value -match "[?&]id=([^&#]+)") { return $Matches[1] }
    if ($Value -match "^[A-Za-z0-9_-]{10,}$") { return $Value }
    throw "Cannot extract Google Drive folder id from FolderUrl."
}

function LoadOAuthClient {
    $jsonPath = $ClientJson
    if ([string]::IsNullOrWhiteSpace($jsonPath)) {
        $defaultJson = Join-Path $PSScriptRoot "client_secret.json"
        if (Test-Path -LiteralPath $defaultJson) { $jsonPath = $defaultJson }
    }

    $id = $ClientId
    $secret = $ClientSecret

    if (-not [string]::IsNullOrWhiteSpace($jsonPath)) {
        if (-not (Test-Path -LiteralPath $jsonPath)) { throw "ClientJson not found: $jsonPath" }
        $cfg = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
        $installed = Prop $cfg "installed"
        if ($null -eq $installed) { $installed = Prop $cfg "web" }
        if ($null -eq $installed) { throw "ClientJson must contain 'installed' OAuth client data." }
        $id = [string](Prop $installed "client_id")
        $secret = [string](Prop $installed "client_secret")
    }

    if ([string]::IsNullOrWhiteSpace($id)) { throw "Provide -ClientJson or -ClientId." }

    $script:OAuthClientId = $id
    $script:OAuthClientSecret = $secret
    if ([string]::IsNullOrWhiteSpace($script:OAuthClientSecret)) {
        Warn "No ClientSecret supplied. If Google returns 400 invalid_client, pass -ClientSecret or use -ClientJson."
    }
}

function TokenPath {
    $dir = Join-Path $env:APPDATA "OddsparksSync"
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $hash = (ShaText $script:OAuthClientId).Substring(0, 12)
    return (Join-Path $dir "google-token-$hash.json")
}

function SaveToken($Obj) {
    $enc = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($script:TokenPath, ($Obj | ConvertTo-Json -Depth 10), $enc)
}

function ReadToken {
    if (-not (Test-Path -LiteralPath $script:TokenPath)) { return $null }
    return (Get-Content -LiteralPath $script:TokenPath -Raw | ConvertFrom-Json)
}

function TokenRequest([hashtable] $Body) {
    $Body["client_id"] = $script:OAuthClientId
    if (-not [string]::IsNullOrWhiteSpace($script:OAuthClientSecret)) { $Body["client_secret"] = $script:OAuthClientSecret }
    try {
        return Invoke-RestMethod -Method Post -Uri $TokenUri -ContentType "application/x-www-form-urlencoded" -Body (FormBody $Body)
    }
    catch { throw "OAuth token request failed:`n$(ErrorText $_.Exception)" }
}

function GoogleLogin {
    Info "Opening browser for Google login. Token cache: $script:TokenPath"

    $listenerPrefix = "http://127.0.0.1:$RedirectPort/"
    $redirectUri = "http://127.0.0.1:$RedirectPort"
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add($listenerPrefix)
    $listener.Start()

    try {
        $verifier = RandomB64Url 48
        $state = RandomB64Url 24
        $pairs = @{
            client_id = $script:OAuthClientId
            redirect_uri = $redirectUri
            response_type = "code"
            scope = $DriveScope
            access_type = "offline"
            prompt = "consent"
            code_challenge = (CodeChallenge $verifier)
            code_challenge_method = "S256"
            state = $state
        }
        $authUrl = $AuthUri + "?" + (FormBody $pairs)
        Start-Process $authUrl | Out-Null

        $ctx = $listener.GetContext()
        $code = $ctx.Request.QueryString["code"]
        $errorCode = $ctx.Request.QueryString["error"]
        $returnedState = $ctx.Request.QueryString["state"]

        $html = "<html><body><h3>Oddsparks Sync login complete.</h3><p>You can close this tab.</p></body></html>"
        $bytes = [Text.Encoding]::UTF8.GetBytes($html)
        $ctx.Response.ContentType = "text/html; charset=utf-8"
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $ctx.Response.Close()

        if (-not [string]::IsNullOrWhiteSpace($errorCode)) { throw "Google OAuth error: $errorCode" }
        if ($returnedState -ne $state) { throw "Google OAuth state mismatch." }
        if ([string]::IsNullOrWhiteSpace($code)) { throw "Google OAuth did not return authorization code." }

        $token = TokenRequest @{
            code = $code
            code_verifier = $verifier
            redirect_uri = $redirectUri
            grant_type = "authorization_code"
        }

        if ([string]::IsNullOrWhiteSpace([string](Prop $token "refresh_token"))) {
            throw "No refresh_token returned. Run -Mode logout and -Mode login, or remove app consent in Google Account."
        }

        SaveToken ([ordered]@{
            access_token = $token.access_token
            refresh_token = $token.refresh_token
            expires_at = (Get-Date).ToUniversalTime().AddSeconds([int]$token.expires_in - 60).ToString("o")
            token_type = (Prop $token "token_type")
            scope = (Prop $token "scope")
        })
        Info "Google login saved."
    }
    finally {
        if ($listener.IsListening) { $listener.Stop() }
        $listener.Close()
    }
}

function AccessToken {
    $t = ReadToken
    if ($null -eq $t) { GoogleLogin; $t = ReadToken }

    $access = [string](Prop $t "access_token")
    $expires = [string](Prop $t "expires_at")
    if (-not [string]::IsNullOrWhiteSpace($access) -and -not [string]::IsNullOrWhiteSpace($expires)) {
        if (([datetime]::Parse($expires)).ToUniversalTime() -gt (Get-Date).ToUniversalTime().AddMinutes(2)) { return $access }
    }

    $refresh = [string](Prop $t "refresh_token")
    if ([string]::IsNullOrWhiteSpace($refresh)) { GoogleLogin; $t = ReadToken; $refresh = [string](Prop $t "refresh_token") }

    $new = TokenRequest @{ refresh_token = $refresh; grant_type = "refresh_token" }
    SaveToken ([ordered]@{
        access_token = $new.access_token
        refresh_token = $refresh
        expires_at = (Get-Date).ToUniversalTime().AddSeconds([int]$new.expires_in - 60).ToString("o")
        token_type = (Prop $new "token_type")
        scope = (Prop $new "scope")
    })
    return $new.access_token
}

function DriveJson([string] $Method, [string] $Uri, $Body = $null) {
    $headers = @{ Authorization = "Bearer $(AccessToken)" }
    try {
        if ($null -eq $Body) { return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers }
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -ContentType "application/json; charset=UTF-8" -Body ($Body | ConvertTo-Json -Depth 20 -Compress)
    }
    catch { throw "Google Drive request failed:`n$(ErrorText $_.Exception)" }
}

function Children([string] $ParentId) {
    $out = @()
    $page = $null
    do {
        $q = "'$ParentId' in parents and trashed = false"
        $fields = "nextPageToken, files(id,name,mimeType,modifiedTime,size)"
        $uri = "https://www.googleapis.com/drive/v3/files?q=$(Url $q)&fields=$(Url $fields)&pageSize=1000&supportsAllDrives=true&includeItemsFromAllDrives=true"
        if (-not [string]::IsNullOrWhiteSpace($page)) { $uri += "&pageToken=$(Url $page)" }
        $r = DriveJson "Get" $uri
        $files = Prop $r "files"
        if ($files) { $out += @($files) }
        $page = [string](Prop $r "nextPageToken")
    } while (-not [string]::IsNullOrWhiteSpace($page))
    return @($out)
}

function ChildFolder([string] $ParentId, [string] $Name) {
    $items = @(Children $ParentId | Where-Object { $_.name -eq $Name -and $_.mimeType -eq $DriveFolderMime })
    if ($items.Count -eq 0) { return $null }
    return $items[0]
}

function NewFolder([string] $ParentId, [string] $Name) {
    DriveJson "Post" "https://www.googleapis.com/drive/v3/files?supportsAllDrives=true&fields=id,name" @{ name = $Name; mimeType = $DriveFolderMime; parents = @($ParentId) }
}

function WorldFolder([bool] $Create) {
    $saves = ChildFolder $script:RootFolderId "saves"
    if ($null -eq $saves) {
        if (-not $Create) { return $null }
        Info "Creating Drive folder: saves"
        $saves = NewFolder $script:RootFolderId "saves"
    }
    $wf = ChildFolder $saves.id $World
    if ($null -eq $wf) {
        if (-not $Create) { return $null }
        Info "Creating Drive folder: $World"
        $wf = NewFolder $saves.id $World
    }
    return $wf
}

function DownloadFile([string] $FileId, [string] $OutFile) {
    try {
        Invoke-WebRequest -Method Get -Uri "https://www.googleapis.com/drive/v3/files/${FileId}?alt=media&supportsAllDrives=true" -Headers @{ Authorization = "Bearer $(AccessToken)" } -OutFile $OutFile -UseBasicParsing | Out-Null
    }
    catch { throw "Google Drive download failed:`n$(ErrorText $_.Exception)" }
}

function UploadFile([string] $ParentId, [string] $LocalPath, [string] $Name) {
    $file = Get-Item -LiteralPath $LocalPath
    $headers = @{ Authorization = "Bearer $(AccessToken)"; "X-Upload-Content-Type" = "application/octet-stream"; "X-Upload-Content-Length" = [string]$file.Length }
    $meta = @{ name = $Name; parents = @($ParentId) } | ConvertTo-Json -Compress
    try {
        $init = Invoke-WebRequest -Method Post -Uri "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&supportsAllDrives=true&fields=id,name" -Headers $headers -ContentType "application/json; charset=UTF-8" -Body $meta -UseBasicParsing
        $uploadUrl = [string]($init.Headers["Location"])
        if ([string]::IsNullOrWhiteSpace($uploadUrl)) { throw "No resumable upload URL returned." }
        return Invoke-RestMethod -Method Put -Uri $uploadUrl -InFile $LocalPath -ContentType "application/octet-stream"
    }
    catch { throw "Google Drive upload failed:`n$(ErrorText $_.Exception)" }
}

function LocalSync {
    if (-not (Test-Path -LiteralPath $LocalDir)) { return $null }
    $files = @(Get-ChildItem -LiteralPath $LocalDir -Filter "${World}_sync__*.json" -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    if ($files.Count -eq 0) { return $null }
    return [pscustomobject]@{ Path = $files[0].FullName; Name = $files[0].Name; Sync = (Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json) }
}

function LocalSaveExists {
    return ((Test-Path -LiteralPath (Join-Path $LocalDir "$World.sav")) -and (Test-Path -LiteralPath (Join-Path $LocalDir "${World}_meta.sav")))
}

function LocalMatches($Ls) {
    if ($null -eq $Ls -or -not (LocalSaveExists)) { return $false }
    return ($Ls.Sync.files.save_file.sha256 -eq (ShaFile (Join-Path $LocalDir "$World.sav")) -and $Ls.Sync.files.meta_file.sha256 -eq (ShaFile (Join-Path $LocalDir "${World}_meta.sav")))
}

function ReadRemoteJson($File) {
    $tmp = [IO.Path]::GetTempFileName()
    try { DownloadFile $File.id $tmp; return (Get-Content -LiteralPath $tmp -Raw | ConvertFrom-Json) }
    finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

function RemoteLatest {
    $wf = WorldFolder $false
    if ($null -eq $wf) { return $null }
    $folders = @(Children $wf.id | Where-Object { $_.mimeType -eq $DriveFolderMime -and $_.name -match "^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}__" } | Sort-Object Name -Descending)
    if ($folders.Count -eq 0) { return $null }
    $snap = $folders[0]
    $ch = @(Children $snap.id)
    $syncFiles = @($ch | Where-Object { $_.name -like "${World}_sync__*.json" } | Sort-Object Name -Descending)
    if ($syncFiles.Count -eq 0) { throw "Latest remote snapshot has no sync JSON: $($snap.name)" }
    return [pscustomobject]@{ WorldFolder = $wf; Folder = $snap; Children = $ch; SyncFile = $syncFiles[0]; Sync = (ReadRemoteJson $syncFiles[0]) }
}

function ChildFile($Children, [string] $Name) {
    $x = @($Children | Where-Object { $_.name -eq $Name })
    if ($x.Count -eq 0) { return $null }
    return $x[0]
}

function Backup([string] $Label) {
    if (-not (Test-Path -LiteralPath $LocalDir)) { return }
    $files = @(Get-ChildItem -LiteralPath $LocalDir -File -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) { return }
    $stamp = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
    $safeLabel = ($Label -replace "[^A-Za-z0-9._-]", "_")
    $zipPath = Join-Path $BackupDir "${stamp}__${safeLabel}.zip"
    Info "Backup: $zipPath"
    if ($DryRun) { return }
    if (-not (Test-Path -LiteralPath $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
    Compress-Archive -LiteralPath ($files | ForEach-Object { $_.FullName }) -DestinationPath $zipPath -CompressionLevel Optimal
}

function Pull($R) {
    if ($null -eq $R) { throw "No remote snapshot to pull." }
    $save = ChildFile $R.Children "$World.sav"
    $meta = ChildFile $R.Children "${World}_meta.sav"
    if ($null -eq $save -or $null -eq $meta) { throw "Remote snapshot is incomplete." }
    Info "Decision: PULL $($R.Folder.name)"
    Backup "pull"
    if ($DryRun) { return }
    if (-not (Test-Path -LiteralPath $LocalDir)) { New-Item -ItemType Directory -Path $LocalDir | Out-Null }
    DownloadFile $save.id (Join-Path $LocalDir "$World.sav")
    DownloadFile $meta.id (Join-Path $LocalDir "${World}_meta.sav")
    DownloadFile $R.SyncFile.id (Join-Path $LocalDir $R.SyncFile.name)
    Info "Pull complete."
}

function Push($Ls, $R) {
    if (-not (LocalSaveExists)) { throw "Local save or meta file is missing." }
    $savePath = Join-Path $LocalDir "$World.sav"
    $metaPath = Join-Path $LocalDir "${World}_meta.sav"
    $now = Get-Date
    $safePlayer = ($Player -replace "[^A-Za-z0-9._-]", "_")
    $folder = $now.ToString("yyyy-MM-dd_HH-mm-ss") + "__" + $safePlayer
    $syncName = "${World}_sync__$folder.json"
    $source = $null
    if ($null -ne $Ls) { $source = $Ls.Sync.snapshot.folder_name }

    $sync = [ordered]@{
        schema_version = 2
        world = [ordered]@{ name = $World }
        files = [ordered]@{
            save_file = [ordered]@{ name = "$World.sav"; sha256 = (ShaFile $savePath) }
            meta_file = [ordered]@{ name = "${World}_meta.sav"; sha256 = (ShaFile $metaPath) }
            sync_file = [ordered]@{ name = $syncName }
        }
        snapshot = [ordered]@{ folder_name = $folder; created_at = $now.ToString("yyyy-MM-ddTHH:mm:sszzz"); created_by = $Player }
        source_snapshot = [ordered]@{ folder_name = $source }
    }

    Info "Decision: PUSH $folder"
    Backup "push"
    if ($DryRun) { return }

    $wf = WorldFolder $true
    if ($null -ne (ChildFolder $wf.id $folder)) { throw "Snapshot folder already exists. Run again in one second." }
    $sf = NewFolder $wf.id $folder
    $tmp = Join-Path ([IO.Path]::GetTempPath()) $syncName
    try {
        $enc = New-Object Text.UTF8Encoding($true)
        [IO.File]::WriteAllText($tmp, ($sync | ConvertTo-Json -Depth 20), $enc)
        UploadFile $sf.id $savePath "$World.sav" | Out-Null
        UploadFile $sf.id $metaPath "${World}_meta.sav" | Out-Null
        UploadFile $sf.id $tmp $syncName | Out-Null
        Copy-Item -LiteralPath $tmp -Destination (Join-Path $LocalDir $syncName) -Force
        Info "Push complete."
    }
    finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

function Decision($Ls, $R) {
    $le = LocalSaveExists
    $re = ($null -ne $R)
    $lm = LocalMatches $Ls
    if (-not $le -and -not $re) { return "none" }
    if (-not $le -and $re) { return "pull" }
    if ($le -and -not $re) { return "push" }
    if ($null -eq $Ls) {
        if ($R.Sync.files.save_file.sha256 -eq (ShaFile (Join-Path $LocalDir "$World.sav")) -and $R.Sync.files.meta_file.sha256 -eq (ShaFile (Join-Path $LocalDir "${World}_meta.sav"))) { return "pull" }
        return "conflict"
    }
    if ($Ls.Sync.snapshot.folder_name -eq $R.Sync.snapshot.folder_name) {
        if ($lm) { return "none" }
        return "push"
    }
    if ($lm) { return "pull" }
    return "conflict"
}

function Status($Ls, $R, [string] $D) {
    Write-Host ""
    Write-Host "Oddsparks sync $ScriptVersion"
    Write-Host "World:      $World"
    Write-Host "Player:     $Player"
    Write-Host "LocalDir:   $LocalDir"
    Write-Host "RootFolder: $script:RootFolderId"
    Write-Host "TokenFile:  $script:TokenPath"
    Write-Host "Mode:       $Mode"
    Write-Host "DryRun:     $DryRun"
    if (LocalSaveExists) { Write-Host "Local save: yes" } else { Write-Host "Local save: no" }
    if ($null -ne $Ls) { Write-Host "Local sync: $($Ls.Sync.snapshot.folder_name)" } else { Write-Host "Local sync: none" }
    if ($null -ne $R) { Write-Host "Remote:     $($R.Sync.snapshot.folder_name)" } else { Write-Host "Remote:     none" }
    Write-Host "Decision:   $D"
    Write-Host ""
}

try {
    Info "Script: $ScriptVersion"
    LoadOAuthClient
    $script:TokenPath = TokenPath
    $script:RootFolderId = ExtractFolderId $FolderUrl

    if ($Mode -eq "logout") {
        if (Test-Path -LiteralPath $script:TokenPath) { Remove-Item -LiteralPath $script:TokenPath -Force }
        Info "Local Google token removed: $script:TokenPath"
        exit 0
    }
    if ($Mode -eq "login") { GoogleLogin; exit 0 }

    AccessToken | Out-Null
    $ls = LocalSync
    $rs = RemoteLatest
    $d = Decision $ls $rs

    if ($Mode -eq "status") { Status $ls $rs $d; exit 0 }
    if ($Mode -eq "pull") { Pull $rs; exit 0 }
    if ($Mode -eq "push") { Push $ls $rs; exit 0 }

    if ($d -eq "none") { Status $ls $rs $d; Info "Nothing to synchronize."; exit 0 }
    if ($d -eq "pull") { Pull $rs; exit 0 }
    if ($d -eq "push") { Push $ls $rs; exit 0 }

    Status $ls $rs $d
    Fail "Conflict: local save changed, but Google Drive also has a newer snapshot. Use -Mode pull or -Mode push manually."
    exit 2
}
catch {
    Fail $_.Exception.Message
    exit 1
}
