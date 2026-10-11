# Checked downloads and Git checkouts used by the isolated Windows bootstrap.
function Invoke-TTCommand([string]$Command, [string[]]$Arguments) {
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Command failed with exit code ${LASTEXITCODE}: $($Arguments -join ' ')" }
}

function Get-TTCheckout([string]$Url, [string]$Revision, [string]$Directory) {
    if (-not (Test-Path -LiteralPath $Directory)) {
        Invoke-TTCommand git @('-c', 'core.longpaths=true', 'clone', '--filter=blob:none', '--no-checkout', $Url, $Directory)
        Invoke-TTCommand git @('-C', $Directory, 'fetch', '--depth', '1', 'origin', $Revision)
        Invoke-TTCommand git @('-C', $Directory, 'checkout', '--detach', $Revision)
    }
    if (-not (Test-Path -LiteralPath (Join-Path $Directory '.git'))) {
        throw "Existing directory is not a managed Git checkout: $Directory. Choose another -CacheDirectory."
    }
    $Head = & git -C $Directory rev-parse HEAD
    if ($LASTEXITCODE -ne 0) { throw "Cannot inspect checkout: $Directory" }
    $Expected = & git -C $Directory rev-parse --verify "$Revision^{commit}"
    if ($LASTEXITCODE -ne 0 -or $Head -ne $Expected) {
        throw "Checkout is not at the tested revision ${Revision}: $Directory. Choose another -CacheDirectory."
    }
    $Changes = & git -C $Directory status --porcelain
    if ($LASTEXITCODE -ne 0 -or $Changes) {
        throw "Preserve local changes in $Directory, or choose another -CacheDirectory."
    }
}

function Expand-TTVerifiedArchive([string]$Archive, [string]$Hash, [string]$Directory) {
    if ((Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash -ne $Hash) {
        throw "Download checksum mismatch: $Archive. Remove this cached archive and retry."
    }
    Expand-Archive -LiteralPath $Archive -DestinationPath $Directory -Force
}

function Get-TTArchive([string]$Url, [string]$Hash, [string]$Archive, [string]$Directory, [string]$Executable) {
    $ProgressPreference = 'SilentlyContinue'
    $Marker = Join-Path $Directory '.archive-sha256'
    if (Test-Path -LiteralPath $Marker) {
        if ((Get-Content -LiteralPath $Marker -Raw).Trim() -ne $Hash -or
            -not (Test-Path -LiteralPath (Join-Path $Directory $Executable))) {
            throw "Incomplete or mismatched tool cache: $Directory. Choose another -CacheDirectory."
        }
        return
    }
    if (-not (Test-Path -LiteralPath $Archive)) {
        Write-Host "Downloading $Url"
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Archive
    }
    Expand-TTVerifiedArchive $Archive $Hash $Directory
    if (-not (Test-Path -LiteralPath (Join-Path $Directory $Executable))) {
        throw "Downloaded tool is missing ${Executable}: $Directory"
    }
    $Hash | Set-Content -LiteralPath $Marker -Encoding ascii
}
