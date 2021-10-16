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

  [Parameter(Mandatory=$False, HelpMessage="Generates the logging package adapters for Common.Logging.")]
  [switch]$GenerateJsnLogConfigurations,

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

."..\jsnlog.SimpleWorkingDemoGenerator\Generator\Common\Helpers.ps1"

$nugetLoggingVerbosity = $LoggingVerbosity
if ($nugetLoggingVerbosity -eq 'minimal') { $nugetLoggingVerbosity = 'quiet' } 
if ($nugetLoggingVerbosity -eq 'diagnostic') { $nugetLoggingVerbosity = 'detailed' } 

if ($UpdateVersions -And $Publish)
{
	Write-Host "To publish anything, use a Generate... option."
	Exit
}

Write-Host "Current script directory: $PSScriptRoot"

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
		TagPush "v$currentJSNLogJsVersion" 'git@github.com:mperdeck/jsnlog.js.git'

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
		TagPush "v$currentJSNLogJsVersion" 'git@github.com:mperdeck/jsnlog-nodejs.git'

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

	del C:\Dev\@NuGet\GeneratedPackages\JSNLog.*
	
	nuget locals all -clear
	
	# Restore, Build and Pack the jsnlog package
	dotnet pack --force --output C:\Dev\@NuGet\GeneratedPackages --verbosity $LoggingVerbosity --configuration Release -p:PackageVersion=$currentCoreVersion

	if ($publishing) 
	{ 
		InvokeCommand "Pushing JSNLog package $currentCoreVersion to Nuget" "& nuget push C:\Dev\@NuGet\GeneratedPackages\JSNLog.$currentCoreVersion.nupkg $apiKey -Source https://api.nuget.org/v3/index.json"
	}

	cd ..

	if ($publishing) {
		TagPush "v$currentCoreVersion" 'git@github.com:mperdeck/jsnlog.git'
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
		TagPush "$siteTag" 'git@github.com:mperdeck/jsnlogSimpleWorkingDemos.git'
	}

	cd ..
}

function Generate-Website($publishing)
{
	Write-ActionHeading "Generate Website for Core $currentCoreVersion, Framework $currentFrameworkVersion, JSNLog.js $currentJSNLogJsVersion" $publishing
	if ($WhatIf) { return }

	cd jsnlog.website\website
	
	# Copy in latest version of jsnlog.dll
	Copy-Item "C:\Dev\JSNLog\jsnlog\jsnlog\bin\Release\netstandard2.0\JSNLog.dll" ..\Dependencies

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
		TagPush "$siteTag" 'git@github.com:mperdeck/jsnlog.website.git'
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

if ($GenerateEverything -and $Publish)
{
	Write-ActionHeading('You cannot generate everything and publish as well, because Core, Framework and JSNLog.js now use different versions', $false)
	Exit
}

cd ..

if ($GenerateWebsite -or $GenerateJsnLog -or $GenerateEverything -or $UpdateVersions)
{
	ProcessTemplates $currentCoreVersion $currentFrameworkVersion $currentJSNLogJsVersion
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

if ($GenerateJsnLogConfigurations -or $GenerateEverything) 
{
	Generate-JsnlogConfigurations $Publish
}

if ($GenerateEverything) 
{
	Generate-JsnlogSimpleWorkingDemos $Publish
}

if ($GenerateWebsite -or $GenerateEverything) 
{
	Generate-Website $Publish
}

cd jsnlog.Build

Exit

		

