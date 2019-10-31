$artifactsFolderName = "artifacts"
$localizationFolderName = "Localization"

$cultures = New-Object Collections.Generic.List[String]

$pkgExtension = "nupkg"
$pkgNamePrefix = "OrchardCore.Translations."
$pkgVersion = $env:nugetVersion
$pkgDescription = "Orchard Core translation for '{0}' culture"

$pkgSpecExtension = "nuspec"
$pkgPropsExtension = "props"
$pkgBuildFolderName = "buildTransitive"
$pkgSpecTemplate = "_template.$pkgSpecExtension"
$pkgPropsTemplate = "_template.$pkgPropsExtension"

function createNuGetPackage([string]$pkgName, [string]$culture)
{
    echo "Copying content files .."

    $pkgId = "$pkgName.$pkgVersion"
    $pkgFolderPath = [IO.Path]::Combine($artifactsFolderName, $pkgId)   

    $pkgContentFolderPath = [IO.Path]::Combine($pkgFolderPath, "content")
    New-Item -Path $pkgContentFolderPath -ItemType "Directory" | Out-Null
    
    $pkgCultureFolderPath = [IO.Path]::Combine($pkgContentFolderPath, $localizationFolderName, $culture)
    $cultureFolder = [IO.Path]::Combine($localizationFolderName, $culture)
    Copy-Item -Path $cultureFolder -Destination $pkgCultureFolderPath -Recurse
    
    echo "Copying '$pkgName.$pkgPropsExtension' ..."

    $pkgBuildFolderPath = [IO.Path]::Combine($pkgFolderPath, $pkgBuildFolderName)
    New-Item -Path $pkgBuildFolderPath -ItemType "Directory" | Out-Null
    
    $pkgPropsFileName = "$pkgName.$pkgPropsExtension"
    $pkgPropsFilePath = [IO.Path]::Combine($pkgBuildFolderPath, $pkgPropsFileName)
    Copy-Item -Path $pkgPropsTemplate -Destination $pkgPropsFilePath

    buildNuGetPackageSpec $pkgName $culture
    
    $pkgSpecFileName = "$pkgName.$pkgSpecExtension"
    $pkgSpecFilePath = [IO.Path]::Combine($pkgFolderPath, $pkgSpecFileName)
    .\nuget pack $pkgSpecFilePath | Out-Null
  
    $pkgTempFilePath = "$pkgId.$pkgExtension"
    $pkgFilePath = "$pkgFolderPath.$pkgExtension"
    Move-Item -Path $pkgTempFilePath -Destination $pkgFilePath
    Remove-Item -Path $pkgFolderPath -Recurse
}

function createNuGetMetaPackage()
{
    $pkgName = $pkgNamePrefix + "All"
    $pkgId = "$pkgName.$pkgVersion"

    echo "Creating '$pkgId.$pkgExtension' ..."

    buildNuGetMetaPackageSpec $pkgName
    
    $pkgSpecFileName = "$pkgName.$pkgSpecExtension"
    $pkgSpecFilePath = [IO.Path]::Combine($artifactsFolderName, $pkgSpecFileName)
    .\nuget pack $pkgSpecFilePath | Out-Null
  
    $pkgFolderPath = [IO.Path]::Combine($artifactsFolderName, $pkgId)
    $pkgFilePath = "$pkgFolderPath.$pkgExtension"
    $pkgTempFilePath = "$pkgId.$pkgExtension"
    Move-Item -Path $pkgTempFilePath -Destination $pkgFilePath
}

function buildNuGetPackageSpec($pkgName, $culture)
{
    echo "Building '$pkgName.$pkgSpecExtension' .."

    $pkgSpecDocument = [xml](Get-Content -Path $pkgSpecTemplate)
    $metadata = $pkgSpecDocument.package.metadata
    $metadata.id = $pkgName
    $metadata.version = $pkgVersion
    $metadata.description = [String]::Format($pkgDescription, $culture)
    
    $pkgId = $pkgNamePrefix + $culture
    $pkgFolderPath = [IO.Path]::Combine($artifactsFolderName, "$pkgId.$pkgVersion")
    $pkgSpecFilePath = [IO.Path]::Combine($PWD, $pkgFolderPath, "$pkgId.$pkgSpecExtension")
    $pkgSpecDocument.Save($pkgSpecFilePath)
}

function buildNuGetMetaPackageSpec($pkgName)
{
    echo "Building '$pkgName.$pkgSpecExtension' ..."

    $pkgSpecDocument = [xml](Get-Content -Path $pkgSpecTemplate)
    $metadata = $pkgSpecDocument.package.metadata
    $metadata.id = $pkgName
    $metadata.version = $pkgVersion
    $metadata.description = "Orchard Core translation for all supported cultures"

    $dependencies = $pkgSpecDocument.CreateElement("dependencies")
    $dependencies.RemoveAllAttributes()
    
    foreach($culture in $cultures)
    {
        $dependency = $pkgSpecDocument.CreateElement("dependency")
        $dependency.SetAttribute("id", $pkgNamePrefix + $culture)
        $dependency.SetAttribute("version", $pkgVersion)
        $dependencies.AppendChild($dependency) | Out-Null
    }

    $metadata.AppendChild($dependencies) | Out-Null

    $pkgId = $pkgNamePrefix + "All"
    $pkgSpecFilePath = [IO.Path]::Combine($PWD, $artifactsFolderName, "$pkgId.$pkgSpecExtension")
    $pkgSpecDocument.Save($pkgSpecFilePath)
}

function isEmptyTranslation($culture)
{
    $currentTranslationsFolder = [IO.Path]::Combine($localizationFolderName, $culture)
    $defaultTranslations = Get-ChildItem $localizationFolderName -File   
    $currentTranslations = Get-ChildItem $currentTranslationsFolder -File
    $nonTranslatedFiles = 0
    $contentDiff = 14;
    $minNonTranslatedFiles = 31

    foreach($defaultTranslation in $defaultTranslations)
    {
        foreach($currentTranslation in $currentTranslations)
        {
            if([IO.Path]::GetFileNameWithoutExtension($defaultTranslation.Name) -ne [IO.Path]::GetFileNameWithoutExtension($currentTranslation.Name))
            {
                continue;
            }
            
            $diff = Compare-Object -ReferenceObject $(Get-Content $defaultTranslation.FullName) -DifferenceObject  $(Get-Content $currentTranslation.FullName) | Select -Property InputObject
            
            if($diff.InputObject.Length -eq $contentDiff)
            {
                ++$nonTranslatedFiles;
            }
        }
    }  

    return $nonTranslatedFiles -ige $minNonTranslatedFiles
}

echo "Start generating translations NuGet packages"
echo ""

foreach($cultureFolder in $(Get-ChildItem $localizationFolderName -Directory))
{
    $culture = $cultureFolder.Name
    $pkgName = $pkgNamePrefix + $culture
    $pkgId = "$pkgName.$pkgVersion"
    $cultures.Add($culture)
    
    echo "Creating '$pkgId.$pkgExtension' ..."

    if([bool](isEmptyTranslation($culture)))
    {
        echo "Skipping '$pkgid.$pkgextension' because it's empty"
    }
    else
    {
        createNuGetPackage $pkgname $culture
    }

    echo ""
}

echo "Creating translations meta package ..."
createNuGetMetaPackage

echo ""
echo "Translations NuGet packages created successfully!!"
