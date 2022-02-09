Start-Transcript -Path C:\Temp\DataServicesLogonScript.log

# Write-Host "Installing SQL Server and PowerShell Module"
# Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
# If(-not(Get-InstalledModule SQLServer -ErrorAction silentlycontinue)){
#     Install-Module SQLServer -Confirm:$False -Force
# }

# Deployment environment variables
$connectedClusterName = "Arc-Data-AKS"

Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False

# Login as service principal
az login --service-principal --username $env:spnClientId --password $env:spnClientSecret --tenant $env:spnTenantId

# Set default subscription to run commands against
# "subscriptionId" value comes from clientVM.json ARM template, based on which 
# subscription user deployed ARM template to. This is needed in case Service 
# Principal has access to multiple subscriptions, which can break the automation logic
az account set --subscription $env:subscriptionId

Write-Host "Installing Azure Data Studio Extensions"
Write-Host "`n"

$env:argument1="--install-extension"
$env:argument2="Microsoft.arc"
$env:argument3="microsoft.azuredatastudio-postgresql"

& "C:\Program Files\Azure Data Studio\bin\azuredatastudio.cmd" $env:argument1 $env:argument2
& "C:\Program Files\Azure Data Studio\bin\azuredatastudio.cmd" $env:argument1 $env:argument3

Write-Host "Creating Azure Data Studio Desktop shortcut"
Write-Host "`n"
$TargetFile = "C:\Program Files\Azure Data Studio\azuredatastudio.exe"
$ShortcutFile = "C:\Users\$env:adminUsername\Desktop\Azure Data Studio.lnk"
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

# Getting AKS cluster credentials kubeconfig file
Write-Host "Getting AKS cluster credentials"
Write-Host "`n"
az aks get-credentials --resource-group $env:resourceGroup `
                       --name $env:clusterName --admin

Write-Host "Checking kubernetes nodes"
Write-Host "`n"
kubectl get nodes
Write-Host "`n"

# Onboarding the AKS cluster as an Azure Arc enabled Kubernetes cluster
Write-Host "Onboarding the cluster as an Azure Arc enabled Kubernetes cluster"
Write-Host "`n"

# Monitor pods across arc namespace
$kubectlMonShell = Start-Process -PassThru PowerShell {for (0 -lt 1) {kubectl get pod -n arc; Start-Sleep -Seconds 5; Clear-Host }}

# Localize kubeconfig
$env:KUBECONTEXT = kubectl config current-context
$env:KUBECONFIG = "C:\Users\$env:adminUsername\.kube\config"

# Create Kubernetes - Azure Arc Cluster
az connectedk8s connect --name $connectedClusterName `
                        --resource-group $env:resourceGroup `
                        --location $env:azureLocation `
                        --tags 'Project=jumpstart_azure_arc_data_services' `
                        --kube-config $env:KUBECONFIG `
                        --kube-context $env:KUBECONTEXT

Start-Sleep -Seconds 10

# Create Azure Arc enabled Data Services extension
az k8s-extension create --name arc-data-services `
                        --extension-type microsoft.arcdataservices `
                        --cluster-type connectedClusters `
                        --cluster-name $connectedClusterName `
                        --resource-group $env:resourceGroup `
                        --auto-upgrade false `
                        --scope cluster `
                        --release-namespace arc `
                        --config Microsoft.CustomLocation.ServiceAccount=sa-arc-bootstrapper

Do {
    Write-Host "Waiting for bootstrapper pod, hold tight..."
    Start-Sleep -Seconds 20
    $podStatus = $(if(kubectl get pods -n arc | Select-String "bootstrapper" | Select-String "Running" -Quiet){"Ready!"}Else{"Nope"})
    } while ($podStatus -eq "Nope")

$connectedClusterId = az connectedk8s show --name $connectedClusterName --resource-group $env:resourceGroup --query id -o tsv

$extensionId = az k8s-extension show --name arc-data-services `
                                     --cluster-type connectedClusters `
                                     --cluster-name $connectedClusterName ` --resource-group $env:resourceGroup `
                                     --query id -o tsv

Start-Sleep -Seconds 20

# Create Custom Location
az customlocation create --name 'jumpstart-cl' `
                         --resource-group $env:resourceGroup `
                         --namespace arc `
                         --host-resource-id $connectedClusterId `
                         --cluster-extension-ids $extensionId `
                         --kubeconfig $env:KUBECONFIG

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

# Kill the open PowerShell monitoring kubectl get pods
Stop-Process -Id $kubectlMonShell.Id

# Removing the LogonScript Scheduled Task so it won't run on next reboot
Unregister-ScheduledTask -TaskName "DataServicesLogonScript" -Confirm:$false
Start-Sleep -Seconds 5

Stop-Process -Name powershell -Force

Stop-Transcript