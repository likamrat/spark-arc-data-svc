# Create path
Write-Output "Create deployment path"
$tempDir = "C:\Temp"
New-Item -Path $tempDir -ItemType directory -Force

Start-Transcript "C:\Temp\Tools.log"

$ErrorActionPreference = 'SilentlyContinue'

# Uninstall Internet Explorer
Disable-WindowsOptionalFeature -FeatureName Internet-Explorer-Optional-amd64 -Online -NoRestart

# Disabling IE Enhanced Security Configuration
Write-Host "Disabling IE Enhanced Security Configuration"
function Disable-ieESC {
    $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
    $UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
    Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0
    Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0
    Stop-Process -Name Explorer
    Write-Host "IE Enhanced Security Configuration (ESC) has been disabled." -ForegroundColor Green
}
Disable-ieESC

# Extending C:\ partition to the maximum size
Write-Host "Extending C:\ partition to the maximum size"
Resize-Partition -DriveLetter C -Size $(Get-PartitionSupportedSize -DriveLetter C).SizeMax

# Downloading GitHub artifacts for DataServicesLogonScript.ps1
Invoke-WebRequest "https://github.com/ErikEJ/SqlQueryStress/releases/download/102/SqlQueryStress.zip" -OutFile "C:\Temp\SqlQueryStress.zip"
Invoke-WebRequest "https://raw.githubusercontent.com/likamrat/spark-arc-data-svc/main/artifacts/jumpstart_wallpaper.png" -OutFile "C:\Temp\wallpaper.png"

# Installing tools
workflow ClientTools_01
        {
            $chocolateyAppList = 'azure-cli,az.powershell,kubernetes-cli,vcredist140,microsoft-edge,azcopy10,vscode,putty.install,kubernetes-helm,grep,ssms,dotnetcore-3.1-sdk,pgadmin4,git'
            #Run commands in parallel.
            Parallel 
                {
                    InlineScript {
                        param (
                            [string]$chocolateyAppList
                        )
                        if ([string]::IsNullOrWhiteSpace($using:chocolateyAppList) -eq $false)
                        {
                            try{
                                choco config get cacheLocation
                            }catch{
                                Write-Output "Chocolatey not detected, trying to install now"
                                iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
                            }
                        }
                        if ([string]::IsNullOrWhiteSpace($using:chocolateyAppList) -eq $false){   
                            Write-Host "Chocolatey Apps Specified"  
                            
                            $appsToInstall = $using:chocolateyAppList -split "," | foreach { "$($_.Trim())" }
                        
                            foreach ($app in $appsToInstall)
                            {
                                Write-Host "Installing $app"
                                & choco install $app /y -Force| Write-Output
                            }
                        }                        
                    }
                    Invoke-WebRequest "https://azuredatastudio-update.azurewebsites.net/latest/win32-x64-archive/stable" -OutFile "C:\Temp\azuredatastudio.zip"
                    Invoke-WebRequest "https://aka.ms/azdata-msi" -OutFile "C:\Temp\AZDataCLI.msi"
                }
        }

ClientTools_01 | Format-Table

workflow ClientTools_02
        {
            #Run commands in parallel.
            Parallel
            {
                InlineScript {
                    Expand-Archive C:\Temp\azuredatastudio.zip -DestinationPath 'C:\Program Files\Azure Data Studio'
                    Start-Process msiexec.exe -Wait -ArgumentList '/I C:\Temp\AZDataCLI.msi /quiet'
                }
            }
        }
        
ClientTools_02 | Format-Table 

New-Item -path alias:kubectl -value 'C:\ProgramData\chocolatey\lib\kubernetes-cli\tools\kubernetes\client\bin\kubectl.exe'
New-Item -path alias:azdata -value 'C:\Program Files (x86)\Microsoft SDKs\Azdata\CLI\wbin\azdata.cmd'

# Install Azure Data Studio extensions
Write-Host "`n"
Write-Host "Installing Azure Data Studio Extensions"
Write-Host "`n"
$Env:argument1="--install-extension"
$Env:argument2="Microsoft.arc"
$Env:argument3="microsoft.azuredatastudio-postgresql"
& "C:\Program Files\Azure Data Studio\bin\azuredatastudio.cmd" $Env:argument1 $Env:argument2
& "C:\Program Files\Azure Data Studio\bin\azuredatastudio.cmd" $Env:argument1 $Env:argument3

# Create Azure Data Studio desktop shortcut
Write-Host "`n"
Write-Host "Creating Azure Data Studio Desktop shortcut"
Write-Host "`n"
$TargetFile = "C:\Program Files\Azure Data Studio\azuredatastudio.exe"
$ShortcutFile = "C:\Users\$Env:USERNAME\Desktop\Azure Data Studio.lnk"
$WScriptShell = New-Object -ComObject WScript.Shell
$Shortcut = $WScriptShell.CreateShortcut($ShortcutFile)
$Shortcut.TargetPath = $TargetFile
$Shortcut.Save()

# Unzip SqlQueryStress
Expand-Archive -Path C:\Temp\SqlQueryStress.zip -DestinationPath C:\Temp\SqlQueryStress

# Create SQLQueryStress desktop shortcut
Write-Host "`n"
Write-Host "Creating SQLQueryStress Desktop shortcut"
Write-Host "`n"
$TargetFile = "C:\Temp\SqlQueryStress\SqlQueryStress.exe"
$ShortcutFile = "C:\Users\$Env:USERNAME\Desktop\SqlQueryStress.lnk"
$WScriptShell = New-Object -ComObject WScript.Shell
$Shortcut = $WScriptShell.CreateShortcut($ShortcutFile)
$Shortcut.TargetPath = $TargetFile
$Shortcut.Save()

# Registering Azure Arc providers
Write-Host "Registering Azure Arc providers, hold tight..."
Write-Host "`n"
az provider register --namespace Microsoft.Kubernetes --wait
az provider register --namespace Microsoft.KubernetesConfiguration --wait
az provider register --namespace Microsoft.ExtendedLocation --wait
az provider register --namespace Microsoft.AzureArcData --wait

az provider show --namespace Microsoft.Kubernetes -o table
Write-Host "`n"
az provider show --namespace Microsoft.KubernetesConfiguration -o table
Write-Host "`n"
az provider show --namespace Microsoft.ExtendedLocation -o table
Write-Host "`n"
az provider show --namespace Microsoft.AzureArcData -o table
Write-Host "`n"

# Installing Azure Arc CLI extensions
Write-Host "Installing Azure Arc CLI extensions"
Write-Host "`n"
az config set extension.use_dynamic_install=yes_without_prompt
az extension add --name "connectedk8s" -y
az extension add --name "k8s-extension" -y
az extension add --name "customlocation" -y
az extension add --name "arcdata" -y

Write-Host "`n"
az -v

# Changing to Client VM wallpaper
$imgPath="C:\Temp\wallpaper.png"
$code = @' 
using System.Runtime.InteropServices; 
namespace Win32{ 
    
     public class Wallpaper{ 
        [DllImport("user32.dll", CharSet=CharSet.Auto)] 
         static extern int SystemParametersInfo (int uAction , int uParam , string lpvParam , int fuWinIni) ; 
         
         public static void SetWallpaper(string thePath){ 
            SystemParametersInfo(20,0,thePath,3); 
         }
    }
 } 
'@

add-type $code 
[Win32.Wallpaper]::SetWallpaper($imgPath)

# Removing the LogonScript Scheduled Task so it won't run on next reboot
Unregister-ScheduledTask -TaskName "DataServicesLogonScript" -Confirm:$false
Start-Sleep -Seconds 5

Stop-Process -Name powershell -Force

Stop-Transcript