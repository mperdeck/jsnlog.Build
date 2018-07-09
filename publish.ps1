# =================================================
# Run this script to publish all versions of JSNLog to their environments (Nuget, Bower, etc.)
# =================================================

[CmdletBinding()]
Param(
  [Parameter(Mandatory=$True,Position=1, HelpMessage="Version number of new version. Format: <Major Version>.<Minor Version>.<Bug Fix>.<Build Number>[-prerelease]")]
  [string]$version,

  [Parameter(Mandatory=$False, HelpMessage="Generates everything, including JSNLog and website.")]
  [switch]$GenerateEverything,

  [Parameter(Mandatory=$False, HelpMessage="Generates the server side JSNLog package.")]
  [switch]$GenerateJsnLog,

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

$nugetLoggingVerbosity = $LoggingVerbosity
if ($nugetLoggingVerbosity -eq 'minimal') { $nugetLoggingVerbosity = 'quiet' } 
if ($nugetLoggingVerbosity -eq 'diagnostic') { $nugetLoggingVerbosity = 'detailed' } 

if ($version -like '-')
{
	# Using a prerelease version
	if ($GenerateWebsite)
	{
		Write-Host "The web site should not be published with a prerelease version to avoid confusion with the latest normal version."
		Exit
	}
}

if ($UpdateVersions -And $Publish)
{
	Write-Host "To publish anything, use a Generate... option."
	Exit
}

# ---------------
# Constants

$versionPlaceholder = "__Version__"

Write-Host "Current script directory: $PSScriptRoot"


# ---------------
# Update version numbers

Function ApplyVersion([string]$templatePath)
{
	# Get file path without the ".template" extension  
	$filePath = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($_.FullName), [System.IO.Path]::GetFileNameWithoutExtension($_.FullName))

	# Copy template file to file with same name but without ".template"
	# Whilst coying, replace __Version__ placeholder with version
	# Must use encoding ascii. bower register (used further below) does not understand other encodings, such as utf 8.
	(Get-Content $templatePath) | Foreach-Object {$_ -replace $versionPlaceholder, $version} | Out-File -encoding ascii $filePath

    Write-Host "Updated version in : $filePath"
}

Function GenerateConfigPackage([string]$packageName, $publishing)
{
	cd FinalPackages
	cd $packageName
	nuget pack $packageName.nuspec -OutputDirectory C:\Dev\@NuGet\GeneratedPackages
	if ($publishing) { nuget push C:\Dev\@NuGet\GeneratedPackages\$packageName.$version.nupkg $apiKey -Source https://api.nuget.org/v3/index.json }
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

function Generate-JsnlogJs($publishing)
{
	Write-ActionHeading "Generate-JsnlogJs" $publishing
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
		# Commit any changes and deletions (but not additions), such as to the minified file
		git commit -a -m "$version"
				
		# Push to Github		
		git tag v$version
		git push https://${githubUsername}:${githubPassword}@github.com/$githubUsername/jsnlog.js.git --tags

		git branch $version
		git push https://${githubUsername}:${githubPassword}@github.com/$githubUsername/jsnlog.js.git --all

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
		
		npm publish .
	} 

	cd ..
}

function Generate-JsnlogNodeJs($publishing)
{
	Write-ActionHeading "Generate-JsnlogNodeJs" $publishing
	if ($WhatIf) { return }

	cd jsnlog-nodejs
	
	if ($publishing) 
	{
		# Commit any changes and deletions (but not additions), such as to the minified file
		git commit -a -m "$version"
				
		# Push to Github		
		git tag v$version
		git push https://${githubUsername}:${githubPassword}@github.com/$githubUsername/jsnlog-nodejs.git --tags

		git branch $version
		git push https://${githubUsername}:${githubPassword}@github.com/$githubUsername/jsnlog-nodejs.git --all

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

	Write-ActionHeading "Generate-Jsnlog" $publishing
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
	& msbuild /t:pack /p:Configuration=Release /p:PackageVersion=$version /verbosity:$LoggingVerbosity
    Move-Item bin\release\*.nupkg C:\Dev\@NuGet\GeneratedPackages

	if ($publishing) 
	{ 
		& nuget push C:\Dev\@NuGet\GeneratedPackages\JSNLog.$version.nupkg $apiKey  -Source https://api.nuget.org/v3/index.json
	}

	cd ..

	if ($publishing) {
		# Commit any changes and deletions (but not additions) to Github
		git commit -a -m "$version"
				
		# Push to Github		
		git tag v$version
		git push https://${githubUsername}:${githubPassword}@github.com/$githubUsername/jsnlog.git --tags

		git branch $version
		git push https://${githubUsername}:${githubPassword}@github.com/$githubUsername/jsnlog.git --all
	}

	cd ..
}

function Generate-JsnlogConfigurations($publishing)
{
	# JSNLog itself and jsnlog.js must be processed before processing jsnlog.configurations,
	# because configurations relies on files compiled in the earlier steps.

	Write-ActionHeading "Generate-JsnlogConfigurations" $publishing
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
		# Commit any changes and deletions (but not additions) to Github

		git commit -a -m "$version"
				
		# Push to Github		
		git branch $version
		git push https://${githubUsername}:${githubPassword}@github.com/$githubUsername/jsnlog.configurations.git --all
	}

	cd ..
}

function Generate-JsnlogSimpleWorkingDemos($publishing)
{
	# ---------------
	# jsnlogSimpleWorkingDemos

	Write-ActionHeading "Generate-JsnlogSimpleWorkingDemos" $publishing
	if ($WhatIf) { return }

	cd jsnlogSimpleWorkingDemos

	if ($publishing) 
	{ 
		# Commit any changes and deletions (but not additions) to Github

		git commit -a -m "$version"
				
		# Push to Github		
		git branch $version
		git push https://${githubUsername}:${githubPassword}@github.com/$githubUsername/jsnlogSimpleWorkingDemos.git --all
	}

	cd ..
}

function Generate-Website($publishing)
{
	Write-ActionHeading "Generate-Website" $publishing
	if ($WhatIf) { return }

	cd jsnlog.website\website
	
	# Copy in latest version of jsnlog.dll
	Copy-Item "C:\Dev\JSNLog\jsnlog\\jsnlog\bin\Release\net452\JSNLog.dll" ..\Dependencies

    # Backup the existing site in the %temp% dir
    Copy-Item "G:\Web sites\jsnlog" $env:temp\jsnlog.$(get-date -f yyyyMMddTHHmmss) -Recurse

	# C:\Program Files (x86)\MSBuild\14.0\Bin
	# has to be in the path for powershell to find msbuild
	#
	# This publishes the Website project, using the publish profile "jsnlog".
	# This publishes to 
	# C:\Web sites\jsnlog
	msbuild WebSite.csproj /p:DeployOnBuild=true /p:PublishProfile=jsnlog /p:VisualStudioVersion=15.0 /p:Configuration=Release /verbosity:$LoggingVerbosity

	if ($publishing) 
	{ 
		# Assumes there is a job "jsnlog web site" defined in goodsync,
		# which uploads the files C:\Web sites\jsnlog to the web server at ftp://ftp.jsnlog.com/httpdocs
		#
		# Make sure that the goodsync program is installed, and its .exe added to the
		# path environment setting
		goodsync-v9 /exit-ifok sync "jsnlog web site" 
	}

	cd ..

	if ($publishing) 
	{ 
		# Commit any changes and deletions (but not additions) to Github
		git commit -a -m "$version"
				
		# Push to Github		
		git tag v$version
		git push https://${githubUsername}:${githubPassword}@github.com/$githubUsername/jsnlog.website.git --tags

		git branch $version
		git push https://${githubUsername}:${githubPassword}@github.com/$githubUsername/jsnlog.website.git --all
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

cd ..

if ($GenerateWebsite -or $GenerateJsnLog -or $GenerateEverything -or $UpdateVersions)
{
	ProcessTemplates
}

if ($GenerateJsnLog -or $GenerateEverything) 
{
	Remove-CachedVersions
}

if ($GenerateEverything) 
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

		

