# Prepares the tested Windows V3/MinGW toolchain in an isolated cache and builds the game.
[CmdletBinding()]
param(
    [string]$CacheDirectory = '',
    [string]$SdkDirectory = '',
    [string]$OutputPath = 'torus_trooper.exe',
    [switch]$Check,
    [switch]$PrepareOnly,
    [switch]$Verify
)
$ErrorActionPreference = 'Stop'
if (-not [Environment]::Is64BitProcess) { throw 'Use 64-bit PowerShell.' }
if ($Check -and ($PrepareOnly -or $Verify)) { throw '-Check cannot be combined with -PrepareOnly or -Verify.' }
$ProjectDirectory = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'windows_setup_tools.ps1')
$PinFile = Join-Path $PSScriptRoot 'windows-toolchain.json'
$Pins = Get-Content -LiteralPath $PinFile -Raw | ConvertFrom-Json
foreach ($Command in @('git', 'cmake')) {
    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        throw "Install $Command and add it to PATH, then rerun setup."
    }
}
if (-not $SdkDirectory) {
    $SdkDirectory = $env:VULKAN_SDK
    foreach ($Scope in @('User', 'Machine')) {
        if ($SdkDirectory) { break }
        $SdkDirectory = [Environment]::GetEnvironmentVariable('VULKAN_SDK', $Scope)
    }
}
if (-not $SdkDirectory -or -not (Test-Path -LiteralPath (Join-Path $SdkDirectory 'Lib\vulkan-1.lib'))) {
    throw 'Install the LunarG Vulkan SDK, or pass -SdkDirectory with an SDK containing Lib\vulkan-1.lib.'
}
$SdkDirectory = [IO.Path]::GetFullPath($SdkDirectory)
if ($Verify) {
    foreach ($Command in @('python', 'glslangValidator', 'spirv-val')) {
        if (-not (Get-Command $Command -ErrorAction SilentlyContinue) -and
            -not (Test-Path -LiteralPath (Join-Path $SdkDirectory "Bin\$Command.exe"))) {
            throw "Verification requires $Command. Install Python 3 and the Vulkan SDK shader tools."
        }
    }
    $SavedErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $PythonVersion = & python --version 2>&1
        $PythonExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = $SavedErrorAction }
    if ($PythonExit -ne 0 -or "$PythonVersion" -notmatch '^Python 3\.') {
        throw 'Verification requires a working Python 3 executable on PATH; the Microsoft Store alias is insufficient.'
    }
}
if ($Check) {
    Write-Host "Build prerequisites found. Setup will prepare pinned V3, MinGW Clang, Ninja, GLFW and V modules."
    Write-Host 'A Vulkan-capable graphics driver is required to run the graphical game.'
    return
}
if (-not $CacheDirectory) {
    $CacheKey = (Get-FileHash -LiteralPath $PinFile -Algorithm SHA256).Hash.Substring(0, 12).ToLowerInvariant()
    $CacheDirectory = Join-Path $env:LOCALAPPDATA "antono2\torus-trooper\windows\$CacheKey"
}
$CacheDirectory = [IO.Path]::GetFullPath($CacheDirectory)
New-Item -ItemType Directory -Force -Path $CacheDirectory | Out-Null
Get-WindowsSetupArchive $Pins.clang_url $Pins.clang_sha256 (Join-Path $CacheDirectory 'clang.zip') (Join-Path $CacheDirectory 'clang') "$($Pins.clang_directory)\bin\clang.exe"
Get-WindowsSetupArchive $Pins.ninja_url $Pins.ninja_sha256 (Join-Path $CacheDirectory 'ninja.zip') (Join-Path $CacheDirectory 'ninja') 'ninja.exe'
$ClangBin = Join-Path $CacheDirectory "clang\$($Pins.clang_directory)\bin"
$env:Path = "$ClangBin;$(Join-Path $CacheDirectory 'ninja');$(Join-Path $SdkDirectory 'Bin');$env:Path"
$VDirectory = Join-Path $CacheDirectory 'v'
Get-WindowsSetupCheckout 'https://github.com/vlang/v.git' $Pins.v $VDirectory
Get-WindowsSetupCheckout 'https://github.com/vlang/vc.git' $Pins.vc (Join-Path $VDirectory 'vc')
$VExecutable = Join-Path $VDirectory 'v.exe'
if (-not (Test-Path -LiteralPath $VExecutable)) {
    $SavedCFlags = $env:CFLAGS
    Push-Location $VDirectory
    try {
        $env:CFLAGS = '-Wno-incompatible-pointer-types -Wno-incompatible-function-pointer-types'
        Invoke-WindowsSetupCommand (Join-Path $VDirectory 'makev.bat') @('-clang', '--local')
    } finally {
        $env:CFLAGS = $SavedCFlags
        Pop-Location
    }
}
$env:Path = "$VDirectory;$env:Path"
$HeadersDirectory = Join-Path $CacheDirectory 'Vulkan-Headers'
$VolkDirectory = Join-Path $CacheDirectory 'volk'
Get-WindowsSetupCheckout 'https://github.com/KhronosGroup/Vulkan-Headers.git' $Pins.headers $HeadersDirectory
Get-WindowsSetupCheckout 'https://github.com/zeux/volk.git' $Pins.volk $VolkDirectory
$IsolatedSdk = Join-Path $CacheDirectory 'sdk'
New-Item -ItemType Directory -Force -Path (Join-Path $IsolatedSdk 'Include\volk'), (Join-Path $IsolatedSdk 'Lib') | Out-Null
Copy-Item -LiteralPath (Join-Path $HeadersDirectory 'include\vulkan'), (Join-Path $HeadersDirectory 'include\vk_video') -Destination (Join-Path $IsolatedSdk 'Include') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $VolkDirectory 'volk.h'), (Join-Path $VolkDirectory 'volk.c') -Destination (Join-Path $IsolatedSdk 'Include\volk') -Force
Copy-Item -LiteralPath (Join-Path $SdkDirectory 'Lib\vulkan-1.lib') -Destination (Join-Path $IsolatedSdk 'Lib') -Force
$env:VULKAN_SDK = $IsolatedSdk

$ModuleKey = (Get-FileHash -LiteralPath (Join-Path $ProjectDirectory 'v.mod') -Algorithm SHA256).Hash.Substring(0, 12).ToLowerInvariant()
$env:VMODULES = Join-Path $CacheDirectory "modules-$ModuleKey"
function Install-TTModules([string]$ManifestDirectory) {
    $Manifest = Get-Content -LiteralPath (Join-Path $ManifestDirectory 'v.mod') -Raw
    foreach ($Match in [regex]::Matches($Manifest, "'antono2\.([a-z0-9_]+)@([^']+)'")) {
        $Name = $Match.Groups[1].Value
        $Tag = $Match.Groups[2].Value
        $Directory = Join-Path $env:VMODULES "antono2\$Name"
        $Repository = if ($Name -eq 'vkmemalloc') { 'vulkan_memory_allocator' } else { $Name }
        Get-WindowsSetupCheckout "https://github.com/antono2/$Repository.git" $Tag $Directory
        if ($script:ModuleTags.ContainsKey($Name)) {
            if ($script:ModuleTags[$Name] -ne $Tag) { throw "Conflicting dependency pins for $Name" }
            continue
        }
        $script:ModuleTags[$Name] = $Tag
        Install-TTModules $Directory
    }
}
$script:ModuleTags = @{}
Install-TTModules $ProjectDirectory
$env:V_MACOS_V3_NO_FALLBACK = '1'
Push-Location $ProjectDirectory
try { Invoke-WindowsSetupCommand $VExecutable @('run', 'scripts/check_installed_deps.vsh') } finally { Pop-Location }

$GlfwDirectory = Join-Path $CacheDirectory 'glfw'
$GlfwBuild = Join-Path $CacheDirectory 'glfw-build'
$GlfwInstall = Join-Path $CacheDirectory 'glfw-install'
Get-WindowsSetupCheckout 'https://github.com/glfw/glfw.git' $Pins.glfw $GlfwDirectory
Invoke-WindowsSetupCommand cmake @('-S', $GlfwDirectory, '-B', $GlfwBuild, '-G', 'Ninja', '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_C_COMPILER=clang', "-DCMAKE_INSTALL_PREFIX=$GlfwInstall", '-DBUILD_SHARED_LIBS=OFF', '-DGLFW_BUILD_EXAMPLES=OFF', '-DGLFW_BUILD_TESTS=OFF', '-DGLFW_BUILD_DOCS=OFF')
Invoke-WindowsSetupCommand cmake @('--build', $GlfwBuild, '--parallel')
Invoke-WindowsSetupCommand cmake @('--install', $GlfwBuild)
$env:GLFW_INCLUDE = Join-Path $GlfwInstall 'include'
$env:GLFW_LIB = Join-Path $GlfwInstall 'lib'
Write-Host "Prepared Windows toolchain: $CacheDirectory"
if ($PrepareOnly) { return }
& (Join-Path $PSScriptRoot 'build_windows.ps1') -OutputPath $OutputPath -Verify:$Verify
