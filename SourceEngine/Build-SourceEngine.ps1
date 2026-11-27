[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Get-SboxEnginePath {
    $path = $env:FACEPUNCH_ENGINE
    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = [Environment]::GetEnvironmentVariable('FACEPUNCH_ENGINE', 'User')
    }

    if ([string]::IsNullOrWhiteSpace($path)) {
        $programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
        $path = Join-Path $programFilesX86 'Steam\steamapps\common\sbox'
    }

    return [IO.Path]::GetFullPath($path.Trim().Trim('"'))
}

$ProjectPath = $PSScriptRoot
$codePath = Join-Path $ProjectPath 'Code'
$sourceProject = Join-Path $codePath 'source1.csproj'
if (-not (Test-Path -LiteralPath $sourceProject)) {
    throw "Could not find the project file: $sourceProject"
}

$enginePath = Get-SboxEnginePath
$engineAssembly = Join-Path $enginePath 'bin\managed\Sandbox.Engine.dll'
if (-not (Test-Path -LiteralPath $engineAssembly)) {
    throw "FACEPUNCH_ENGINE does not point to an s&box install (missing bin\managed\Sandbox.Engine.dll): $enginePath"
}

$temporaryProject = Join-Path $codePath 'source1.local-build.csproj'
if (Test-Path -LiteralPath $temporaryProject) {
    throw "Temporary build file already exists; remove it before running this script: $temporaryProject"
}

$enginePathInProject = '../../../../../../Program Files (x86)/Steam/steamapps/common/sbox'
$enginePathForXml = [Security.SecurityElement]::Escape($enginePath.Replace('\', '/'))
$projectText = [IO.File]::ReadAllText($sourceProject)
if (-not $projectText.Contains($enginePathInProject)) {
    throw "The generated project file has changed. Reopen the project in s&box and update this script's engine path substitution."
}
$projectText = $projectText.Replace($enginePathInProject, $enginePathForXml)
[IO.File]::WriteAllText($temporaryProject, $projectText, [Text.UTF8Encoding]::new($false))

$intermediateBase = Join-Path $codePath 'obj\SourceEngineLocalBuild\'
$intermediateRelease = Join-Path $intermediateBase 'Release\'
$outputPath = Join-Path $ProjectPath '.sbox\bin\'
$builtDll = Join-Path $outputPath 'package.local.source1.dll'
$documentationFile = Join-Path $outputPath 'package.local.source1.xml'

try {
    New-Item -ItemType Directory -Force -Path $outputPath | Out-Null

    $buildArguments = @(
        'build',
        $temporaryProject,
        '--configuration', 'Release',
        "-p:BaseIntermediateOutputPath=$(Join-Path $codePath 'obj\')",
        "-p:MSBuildProjectExtensionsPath=$intermediateBase",
        "-p:IntermediateOutputPath=$intermediateRelease",
        "-p:OutputPath=$outputPath",
        "-p:DocumentationFile=$documentationFile",
        '-p:AssemblyName=package.local.source1',
        '-p:Version=0.0.101'
    )

    & dotnet @buildArguments
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet build failed with exit code $LASTEXITCODE"
    }

    if (-not (Test-Path -LiteralPath $builtDll)) {
        throw "Build succeeded but did not produce $builtDll"
    }

    $builtAssemblyName = [Reflection.AssemblyName]::GetAssemblyName($builtDll)
    if ($builtAssemblyName.Name -ne 'package.local.source1') {
        throw "Unexpected assembly name: $($builtAssemblyName.Name)"
    }

    $installFolder = Join-Path $enginePath 'mounts\SourceEngine'
    New-Item -ItemType Directory -Force -Path $installFolder | Out-Null
    $installedDll = Join-Path $installFolder 'package.local.source1.dll'

    try {
        Copy-Item -LiteralPath $builtDll -Destination $installedDll -Force
    }
    catch {
        throw "Build succeeded, but s&box denied the copy to '$installFolder'. Run PowerShell as Administrator and retry. $($_.Exception.Message)"
    }

    Write-Host ''
    Write-Host 'Build and install completed.'
    Write-Host "DLL: $installedDll"
    Write-Host "Assembly: $($builtAssemblyName.FullName)"
    Write-Host 'Package identity metadata: local.source1 (s&box engine 33.1)'
    Write-Host 'Restart s&box to load the updated mount DLL.'
}
finally {
    Remove-Item -LiteralPath $temporaryProject -Force -ErrorAction SilentlyContinue
}

