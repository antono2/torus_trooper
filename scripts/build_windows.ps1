# Builds the Windows game and optionally verifies the resulting executable.
param(
    [string]$OutputPath = "torus_trooper.exe",
    [switch]$Verify
)

$ErrorActionPreference = "Stop"
$ProjectDirectory = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

function Test-GlfwLayout([string]$IncludeDirectory, [string]$LibraryDirectory) {
    return $IncludeDirectory -and $LibraryDirectory -and
        (Test-Path (Join-Path $IncludeDirectory "GLFW\glfw3.h")) -and
        (Test-Path (Join-Path $LibraryDirectory "libglfw3.a"))
}

if (-not (Get-Command v -ErrorAction SilentlyContinue)) {
    throw "The V compiler was not found on PATH."
}
if (-not (Get-Command clang -ErrorAction SilentlyContinue)) {
    throw "Clang with a Windows x64 MinGW target was not found on PATH."
}
$ClangTarget = (& clang -dumpmachine).Trim()
if ($LASTEXITCODE -ne 0 -or $ClangTarget -notmatch '^x86_64-.*(windows-gnu|mingw32)$') {
    throw "Clang must target Windows x64 MinGW; found '$ClangTarget'."
}
if (-not $env:VULKAN_SDK -or
    -not (Test-Path (Join-Path $env:VULKAN_SDK "Include\vulkan\vulkan.h")) -or
    -not (Test-Path (Join-Path $env:VULKAN_SDK "Lib\vulkan-1.lib"))) {
    throw "VULKAN_SDK must point to a Vulkan SDK containing Include\vulkan\vulkan.h and Lib\vulkan-1.lib."
}

$GlfwInclude = $env:GLFW_INCLUDE
$GlfwLibrary = $env:GLFW_LIB
if (-not (Test-GlfwLayout $GlfwInclude $GlfwLibrary)) {
    $VcpkgRoots = @(
        $env:VCPKG_ROOT,
        $env:VCPKG_INSTALLATION_ROOT,
        (Join-Path $HOME ".cache\antono2\glfw\vcpkg")
    ) | Where-Object { $_ } | Select-Object -Unique
    foreach ($VcpkgRoot in $VcpkgRoots) {
        $Candidate = Join-Path $VcpkgRoot "installed\x64-mingw-static"
        $CandidateInclude = Join-Path $Candidate "include"
        $CandidateLibrary = Join-Path $Candidate "lib"
        if (Test-GlfwLayout $CandidateInclude $CandidateLibrary) {
            $GlfwInclude = $CandidateInclude
            $GlfwLibrary = $CandidateLibrary
            break
        }
    }
}
if (-not (Test-GlfwLayout $GlfwInclude $GlfwLibrary)) {
    throw "MinGW GLFW 3 was not found. Set GLFW_INCLUDE and GLFW_LIB, or install glfw3:x64-mingw-static in VCPKG_ROOT."
}

$env:GLFW_INCLUDE = $GlfwInclude
$env:GLFW_LIB = $GlfwLibrary
if ([IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = [IO.Path]::GetFullPath($OutputPath)
} else {
    $OutputPath = [IO.Path]::GetFullPath((Join-Path $ProjectDirectory $OutputPath))
}

Push-Location $ProjectDirectory
try {
    # The generated Vulkan calls use opaque V handles where the C headers
    # expect typed pointers; both have the same Windows x64 pointer ABI.
    $CompilerFlags = @('-cc', 'clang', '-cflags', '-Wno-incompatible-pointer-types')
    if ($Verify) {
        & python scripts/test_build_tools.py
        if ($LASTEXITCODE -ne 0) { throw "Build tool tests failed." }
        & python scripts/build_shaders.py
        if ($LASTEXITCODE -ne 0) { throw "Shader compilation failed." }
        $TestFlags = $CompilerFlags + @(
            '-cflags', "-I$(Join-Path $env:VULKAN_SDK 'Include')",
            '-cflags', "-I$GlfwInclude",
            '-ldflags', "-L$(Join-Path $env:VULKAN_SDK 'Lib')",
            '-ldflags', "-L$GlfwLibrary"
        )
        $TestDirectory = Join-Path ([IO.Path]::GetTempPath()) ("torus-trooper-tests-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $TestDirectory | Out-Null
        try {
            # V3's test runner can hide Clang diagnostics on Windows.
            $TestFiles = @('torus_trooper_test.v') + @(
                Get-ChildItem font5x7, sim, runtime -Filter '*_test.v' -File | ForEach-Object { $_.FullName }
            )
            $TestIndex = 0
            foreach ($TestFile in $TestFiles) {
                $TestExecutable = Join-Path $TestDirectory "torus-test-$TestIndex.exe"
                & python scripts/check_compiler_diagnostics.py -- v @TestFlags -o $TestExecutable $TestFile
                if ($LASTEXITCODE -ne 0) { throw "Test compilation failed: $TestFile" }
                $TestProcess = Start-Process -FilePath $TestExecutable `
                    -WorkingDirectory $ProjectDirectory -WindowStyle Hidden -PassThru
                if (-not $TestProcess.WaitForExit(120000)) {
                    Stop-Process -Id $TestProcess.Id -Force
                    throw "Test timed out: $TestFile"
                }
                if ($TestProcess.ExitCode -ne 0) {
                    throw "Test failed with exit code $($TestProcess.ExitCode): $TestFile"
                }
                $TestIndex++
            }
            Write-Host "Windows V3 tests passed: $TestIndex"
        } finally {
            Get-ChildItem -LiteralPath $TestDirectory -File | Remove-Item -Force
            Remove-Item -LiteralPath $TestDirectory
        }
    }
    if ($Verify) {
        & python scripts/check_compiler_diagnostics.py -- v @CompilerFlags -o $OutputPath .
    } else {
        & v @CompilerFlags -o $OutputPath .
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Torus Trooper compilation failed."
    }
    if ($Verify) {
        foreach ($Arguments in @(
            @('--headless', '--ticks', '600', '--no-sound', '--volume', '0'),
            @('--probe', '--no-sound', '--volume', '0')
        )) {
            $Process = Start-Process -FilePath $OutputPath -ArgumentList $Arguments `
                -WorkingDirectory $ProjectDirectory -WindowStyle Hidden -PassThru
            if (-not $Process.WaitForExit(120000)) {
                Stop-Process -Id $Process.Id -Force
                throw "Torus Trooper verification timed out: $($Arguments -join ' ')"
            }
            if ($Process.ExitCode -ne 0) {
                throw "Torus Trooper verification failed with exit code $($Process.ExitCode): $($Arguments -join ' ')"
            }
        }
    }
} finally {
    Pop-Location
}

Write-Host "Built Torus Trooper: $OutputPath"
Write-Host "GLFW headers: $GlfwInclude"
Write-Host "GLFW library: $GlfwLibrary"
if ($Verify) {
    Write-Host "Windows tests, headless run, and Vulkan probe passed."
}
