# =================================================
# Run this script to publish all versions of JSNLog to their environments (Nuget, Bower, etc.)
# =================================================

[CmdletBinding()]
Param(
  [Parameter(Mandatory=$False, HelpMessage="Generates everything, including JSNLog and website.")]
  [switch]$GenerateEverything,

  [Parameter(Mandatory=$False, HelpMessage="Generates the server side JSNLog package.")]
  [switch]$GenerateJsnLog,

  [Parameter(Mandatory=$False, HelpMessage="Generates the server side jsnlog.js and node.js package.")]
  [switch]$GenerateJsnLogJs,

  [Parameter(Mandatory=$False, HelpMessage="Generates the web site.")]
  [switch]$GenerateWebsite,

  [Parameter(Mandatory=$False, HelpMessage="Only goes through templated files to update __Version__.")]
  [switch]$UpdateVersions,

  [Parameter(Mandatory=$False, HelpMessage="Publishes those components that will be generated")]
  [switch]$Publish,

  [Parameter(Mandatory=$False, HelpMessage="Logging verbosity")]
  [ValidateSet('quiet','minimal','normal','detailed','diagnostic')]
  [System.String]$LoggingVerbosity = 'minimal',

  [Parameter(Mandatory=$False, HelpMessage="Only shows which actions will be taken, does not do anything")]
  [switch]$WhatIf
)

# include nuget key
."..\..\keys.ps1"

# include generator constants
."..\jsnlog.SimpleWorkingDemoGenerator\Generator\helpers\GeneratorConstants.ps1"

$nugetLoggingVerbosity = $LoggingVerbosity
if ($nugetLoggingVerbosity -eq 'minimal') { $nugetLoggingVerbosity = 'quiet' } 
if ($nugetLoggingVerbosity -eq 'diagnostic') { $nugetLoggingVerbosity = 'detailed' } 

if ($UpdateVersions -And $Publish)
{
	Write-Host "To publish anything, use a Generate... option."
	Exit
}

# ---------------
# Constants

$versionPlaceholder = "__Version__"
$frameworkVersionPlaceholder = "__FrameworkVersion__"
$JSNLogJsVersionPlaceholder = "__JSNLogJsVersion__"

Write-Host "Current script directory: $PSScriptRoot"


# ---------------
# Update version numbers

Function ApplyVersion([string]$templatePath)
{
	# Get file path without the ".template" extension  
	$filePath = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($_.FullName), [System.IO.Path]::GetFileNameWithoutExtension($_.FullName))

	# Copy template file to file with same name but without ".template"
	# Whilst coying, replace __Version__ placeholder with version, and __FrameworkVersion__ with the version of files used with .Net Framework, 
	# and __JSNLogJsVersion__ with the version of files used with JSNLog.js.
	# Must use encoding ascii. bower register (used further below) does not understand other encodings, such as utf 8.

	# $currentFrameworkVersion lives in GeneratorConstants.ps1
	(Get-Content $templatePath) | `
		Foreach-Object {$_ -replace $versionPlaceholder, $currentCoreVersion} | `
		Foreach-Object {$_ -replace $frameworkVersionPlaceholder, $currentFrameworkVersion} | `
		Foreach-Object {$_ -replace $JSNLogJsVersionPlaceholder, $currentJSNLogJsVersion} | `
		Out-File -encoding ascii $filePath

    Write-Host "Updated version in : $filePath"
}

Function GenerateConfigPackage([string]$packageName, $publishing)
{
	cd FinalPackages
	cd $packageName
	nuget pack $packageName.nuspec -OutputDirectory C:\Dev\@NuGet\GeneratedPackages
	if ($publishing) { nuget push C:\Dev\@NuGet\GeneratedPackages\$packageName.$currentFrameworkVersion.nupkg $apiKey -Source https://api.nuget.org/v3/index.json }
	cd ..
	cd ..
}

function Expand-ZIPFile($file, $destination)
{
	$shell = new-object -com shell.application
	$zip = $shell.NameSpace($file)
	foreach($item in $zip.items())
	{
		$shell.Namespace($destination).copyhere($item)
	}
}

function Write-ActionHeading($actionHeading, $publishing)
{
	Write-Host ""
	Write-Host "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
	Write-Host $actionHeading
    if ($publishing) { Write-Host "publishing" }
	Write-Host "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
}

function Write-SubActionHeading($actionHeading)
{
	Write-Host ""
	Write-Host "-----------------------------------------------------------"
	Write-Host $actionHeading
	Write-Host "-----------------------------------------------------------"
}

# Creates a tag, pushes it and pushes all branches.
# You have to merge your version branch into master before calling this.
function TagPush([string]$tagName, [string]$repoUrl)
{
	# create and push tag
	git tag $tagName
	git push $repoUrl --tags

	# push all branches
	git push $repoUrl --all
}

function Generate-JsnlogJs($publishing)
{
	Write-ActionHeading "Generate JsnlogJs $currentJSNLogJsVersion" $publishing
	if ($WhatIf) { return }

	cd jsnlog.js		

	# Compile jsnlog.ts to .js and create .min.js file. Also update all copies of jsnlog.js etc. everywhere.
	.\minify.bat

    # Copy TypeScript definitions to DefinitelyTyped project
	$jsnlogFolderPath = "C:\Dev\DefinitelyTyped\jsnlog"
	if (Test-Path -Path $jsnlogFolderPath) { Remove-Item $jsnlogFolderPath -Force -Recurse }
    New-Item $jsnlogFolderPath -type directory
	copy Definitions\jsnlog.d.ts $jsnlogFolderPath
	copy Definitions\jsnlog-tests.ts $jsnlogFolderPath

	if ($publishing) 
	{
		TagPush "v$currentJSNLogJsVersion" 'https://${githubUsername}:${githubPassword}@github.com/$githubUsername/jsnlog.js.git'

		# About Bower and Component
		#
		# Registering to Bower (with "bower register") needs to be done only once.
		# Make sure to push every new version of bower.json to your repo, and to give each
		# new version a tag. Which is what we're doing above.
		#
		# Note that Component wants you to register by editing their wiki, so cannot be done automatically
		
		# Push to NPM
		# Note that you have to register with NPM once, with the command
		# npm adduser
		# 
		# If later on NPM  does not recongise you, login again to NPM on your machine, using:
		# npm login
		
		npm publish .
	} 

	cd ..
}

function Generate-JsnlogNodeJs($publishing)
{
	Write-ActionHeading "Generate JsnlogNodeJs $currentJSNLogJsVersion" $publishing
	if ($WhatIf) { return }

	cd jsnlog-nodejs
	
	if ($publishing) 
	{
		TagPush "v$currentJSNLogJsVersion" 'https://${githubUsername}:${githubPassword}@github.com/$githubUsername/jsnlog-nodejs.git'

		# Push to NPM
		# Note that you have to register with NPM once, with the command
		# npm adduser
		
		npm publish .
	} 

	cd ..
}

function Generate-Jsnlog($publishing)
{
	# ---------------
	# JSNLog for .Net

	Write-ActionHeading "Generate Jsnlog Core $currentCoreVersion`n(framework version is no longer generated)" $publishing
	if ($WhatIf) { return }

	cd jsnlog\jsnlog

	# Upload Nuget package for .Net version

	# Use nuget pack JSNLog.nuspec instead of nuget pack JNSLog.csproj,
	# otherwise the dependencies groups get mushed into a single group-less set (!)
	# See http://stackoverflow.com/questions/25556416/nuget-dependency-framework-targeting-not-working-when-packaging-using-the-cspro

	del C:\Dev\@NuGet\GeneratedPackages\JSNLog.*
	
	if (Test-Path C:\Users\$windowsUsername\.nuget\packages\jsnlog) 
	{
		Remove-Item C:\Users\$windowsUsername\.nuget\packages\jsnlog -Force -Recurse
	}
	
	if (Test-Path C:\Users\$windowsUsername\.nuget\packages\jsnlog.aspnetcore) 
	{
		Remove-Item C:\Users\$windowsUsername\.nuget\packages\jsnlog.aspnetcore -Force -Recurse
	}
	
	# Build the jsnlog package
	# msbuild /t:pack uses the package definition inside the jsnlog.csproj file
	Write-SubActionHeading "Build the jsnlog package"
	& msbuild /t:Clean /p:Configuration=Release /verbosity:$LoggingVerbosity
	& msbuild /t:pack /p:Configuration=Release /p:PackageVersion=$currentCoreVersion /verbosity:$LoggingVerbosity

    # Build final versions of JSNLog.ClassLibrary and JSNLog.AspNetCore
#	& msbuild /t:pack /p:Configuration=Release /p:PackageId=JSNLog.ClassLibrary /p:PackageVersion=99.0.0 /p:Description="DO NOT USE. Instead simply use the JSNLog package." /verbosity:$LoggingVerbosity
#	& msbuild /t:pack /p:Configuration=Release /p:PackageId=JSNLog.AspNetCore /p:PackageVersion=99.0.0 /p:Description="DO NOT USE. Instead simply use the JSNLog package." /verbosity:$LoggingVerbosity

    Move-Item bin\release\*.nupkg C:\Dev\@NuGet\GeneratedPackages

	if ($publishing) 
	{ 
		& nuget push C:\Dev\@NuGet\GeneratedPackages\JSNLog.$currentCoreVersion.nupkg $apiKey  -Source https://api.nuget.org/v3/index.json
#		& nuget push C:\Dev\@NuGet\GeneratedPackages\JSNLog.ClassLibrary.99.0.0.nupkg $apiKey  -Source https://api.nuget.org/v3/index.json
#		& nuget push C:\Dev\@NuGet\GeneratedPackages\JSNLog.AspNetCore.99.0.0.nupkg $apiKey  -Source https://api.nuget.org/v3/index.json
	}

	cd ..

	if ($publishing) {
		TagPush "v$currentCoreVersion" 'https://${githubUsername}:${githubPassword}@github.com/$githubUsername/jsnlog.git'
	}

	cd ..
}

function Generate-JsnlogConfigurations($publishing)
{
	# JSNLog itself and jsnlog.js must be processed before processing jsnlog.configurations,
	# because configurations relies on files compiled in the earlier steps.

	Write-ActionHeading "Generate JsnlogConfigurations $currentFrameworkVersion" $publishing
	if ($WhatIf) { return }

	cd jsnlog.configurations

	& .\generate.ps1

	GenerateConfigPackage "JSNLog.NLog" $publishing
	GenerateConfigPackage "JSNLog.Log4Net" $publishing
	GenerateConfigPackage "JSNLog.Elmah" $publishing
	GenerateConfigPackage "JSNLog.CommonLogging" $publishing
	GenerateConfigPackage "JSNLog.Serilog" $publishing

	if ($publishing) 
	{ 
		Write-Host "Common.Logging packages are no longer published, because fixed at version 2.30.0. Only get build to generate packages in local nuget package dir."

		# git commit -a -m "$version"
				
		# Push to Github		
		# git branch $version
		# git push https://${githubUsername}:${githubPassword}@github.com/$githubUsername/jsnlog.configurations.git --all
	}

	cd ..
}

function HeadingForSites($publishing)
{
	$heading = "Generate JsnlogSimpleWorkingDemos for Core $currentCoreVersion, Framework $currentFrameworkVersion, JSNLog.js $currentJSNLogJsVersion"
	if ($publishing)
	{
		$heading += "`n("
	}

}

function SiteTag()
{
	return "Core$currentCoreVersion-Framework$currentFrameworkVersion-JSNLog.js$currentJSNLogJsVersion";
}

function Generate-JsnlogSimpleWorkingDemos($publishing)
{
	# ---------------
	# jsnlogSimpleWorkingDemos

	Write-ActionHeading "Generate JsnlogSimpleWorkingDemos for Core $currentCoreVersion, Framework $currentFrameworkVersion, JSNLog.js $currentJSNLogJsVersion" $publishing
	if ($WhatIf) { return }

	cd jsnlogSimpleWorkingDemos

	if ($publishing) 
	{ 
		$siteTag = SiteTag
		TagPush "$siteTag" 'https://${githubUsername}:${githubPassword}@github.com/$githubUsername/jsnlogSimpleWorkingDemos.git'
	}

	cd ..
}

function Generate Website($publishing)
{
	Write-ActionHeading "Generate Website for Core $currentCoreVersion, Framework $currentFrameworkVersion, JSNLog.js $currentJSNLogJsVersion" $publishing
	if ($WhatIf) { return }

	cd jsnlog.website\website
	
	# Copy in latest version of jsnlog.dll
	Copy-Item "C:\Dev\JSNLog\jsnlog\\jsnlog\bin\Release\net452\JSNLog.dll" ..\Dependencies

    # Backup the existing site in the %temp% dir
	$websiteFolderPath = "E:\Web sites\jsnlog"
	if (Test-Path -Path $websiteFolderPath) { Copy-Item $websiteFolderPath $env:temp\jsnlog.$(get-date -f yyyyMMddTHHmmss) -Recurse }

	# C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin
	# has to be in the path for powershell to find msbuild
	#
	# This publishes the Website project, using the publish profile "jsnlog".
	# This publishes to 
	# E:\Web sites\jsnlog
	msbuild WebSite.csproj /p:DeployOnBuild=true /p:PublishProfile=jsnlog /p:VisualStudioVersion=15.0 /p:Configuration=Release /verbosity:$LoggingVerbosity

	if ($publishing) 
	{ 
		# Assumes there is a job "jsnlog web site" defined in goodsync,
		# which uploads the files E:\Web sites\jsnlog to the web server at ftp://ftp.jsnlog.com/httpdocs
		#
		# Make sure that the goodsync program is installed, and its .exe added to the
		# path environment setting
		goodsync-v9 /exit-ifok sync "jsnlog web site" 
	}

	cd ..

	if ($publishing) 
	{ 
		$siteTag = SiteTag
		TagPush "$siteTag" 'https://${githubUsername}:${githubPassword}@github.com/$githubUsername/jsnlog.website.git'
	}

	cd ..
}

function Remove-CachedVersions()
{
	Write-ActionHeading "Removed cached versions" $FALSE
	if ($WhatIf) { return }

	Remove-Item -recurse C:\Dev\@NuGet\GeneratedPackages\JSNLog.*
	Remove-Item $env:LOCALAPPDATA\NuGet\Cache\*.nupkg
	
	if (Test-Path C:\Users\$windowsUsername\.dnx\packages\JSNLog) {
		Remove-Item -recurse C:\Users\$windowsUsername\.dnx\packages\JSNLog
	}
}

function ProcessTemplates()
{
	Write-ActionHeading "Process templates" $FALSE
	if ($WhatIf) { return }

	# Visit all files in current directory and its sub directories that end in ".template", and call ApplyVersion on them.
	# Some directories with node_modules have names that are too long to deal with for PowerShell. You can't filter them out in the get-childitem, because the
	# filter itself throws the "too long path" exception. So catch the exceptions in an $err variable and then process them.
	get-childitem '.' -File -recurse -force -ErrorAction SilentlyContinue -ErrorVariable err | ?{($_.extension -eq ".template")} | ForEach-Object { ApplyVersion $_.FullName }
	foreach ($errorRecord in $err)
	{
		if (!($errorRecord.Exception -is [System.IO.PathTooLongException]))
		{
			Write-Error -ErrorRecord $errorRecord
		}
	}
}

if ($GenerateEverything -and $Publish)
{
	Write-ActionHeading('You cannot generate everything and publish as well, because Core, Framework and JSNLog.js now use different versions', $false)
	Exit
}

cd ..

if ($GenerateEverything -or $Publish)
{
	Write-ActionHeading('You cannot generate everything and publish as well, because Core, Framework and JSNLog.js now use different versions', $false)
	Exit
}

if ($GenerateWebsite -or $GenerateJsnLog -or $GenerateEverything -or $UpdateVersions)
{
	ProcessTemplates
}

if ($GenerateJsnLog -or $GenerateEverything) 
{
	Remove-CachedVersions
}

if ($GenerateJsnLogJs -or $GenerateEverything) 
{
	Generate-JsnlogJs $Publish
	Generate-JsnlogNodeJs $Publish
}

if ($GenerateJsnLog -or $GenerateEverything) 
{
	Generate-Jsnlog $Publish
}

if ($GenerateEverything) 
{
	Generate-JsnlogConfigurations $Publish
	Generate-JsnlogSimpleWorkingDemos $Publish
}

if ($GenerateWebsite -or $GenerateEverything) 
{
	Generate-Website $Publish
}

cd jsnlog.Build

Exit

		

