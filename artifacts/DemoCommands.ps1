# Azure Arc-enabled Data Services demo - SPARK - direct, SQL MI, PG 

## variables for Azure location, extension and namespace
$ENV:subscription=""
$ENV:resourceGroup=""
$ENV:location=""
$ENV:clusterName=""
$ENV:adsExtensionName="" 
$ENV:namespace=""
$ENV:clName=""
$ENV:dcName=""
$ENV:storageProfileName=""

## variables for Metrics and Monitoring dashboard credentials
$ENV:AZDATA_LOGSUI_USERNAME="arcadmin"
$ENV:AZDATA_LOGSUI_PASSWORD="P@ssw0rd"
$ENV:AZDATA_METRICSUI_USERNAME="arcadmin"
$ENV:AZDATA_METRICSUI_PASSWORD="P@ssw0rd"

## Log in to Azure 
az login

## Set context to K8s cluster 
az aks get-credentials --resource-group $ENV:resourceGroup --name $ENV:clusterName

## View nodes
kubectl get nodes

## View namespaces
kubectl get namespaces 

## Connect K8s cluster to Arc for direct mode 
az connectedk8s connect --name $ENV:clusterName --resource-group $ENV:resourceGroup --location $ENV:location
# Can take some time

## Create Arc data services extension 
az k8s-extension create --cluster-name $ENV:clusterName --resource-group $ENV:resourceGroup --name $ENV:adsExtensionName --cluster-type connectedClusters --extension-type microsoft.arcdataservices --auto-upgrade false --scope cluster --release-namespace $ENV:namespace --config Microsoft.CustomLocation.ServiceAccount=sa-arc-bootstrapper

## Retrieve the managed identity and grant roles 
$Env:MSI_OBJECT_ID=(az k8s-extension show --resource-group $ENV:resourceGroup  --cluster-name $ENV:clusterName --cluster-type connectedClusters --name $ENV:adsExtensionName | convertFrom-json).identity.principalId

## Assign roles to the managed identity
az role assignment create --assignee $Env:MSI_OBJECT_ID --role "Contributor" --scope "/subscriptions/$ENV:subscription/resourceGroups/$ENV:resourceGroup"
az role assignment create --assignee $Env:MSI_OBJECT_ID --role "Monitoring Metrics Publisher" --scope "/subscriptions/$ENV:subscription/resourceGroups/$ENV:resourceGroup"

## Create a custom location
$ENV:hostClusterId=(az connectedk8s show --resource-group $ENV:resourceGroup --name $ENV:clusterName --query id -o tsv)
$ENV:extensionId=(az k8s-extension show --resource-group $ENV:resourceGroup --cluster-name $ENV:clusterName --cluster-type connectedClusters --name $ENV:adsExtensionName --query id -o tsv)
az customlocation create --resource-group $ENV:resourceGroup --name $ENV:clName --namespace $ENV:namespace --host-resource-id $ENV:hostClusterId --cluster-extension-ids $ENV:extensionId
# Can take some time

## View custom location 
az customlocation list -o table

## Create data controller 
az arcdata dc create --name $ENV:dcName --resource-group $ENV:resourceGroup --location $ENV:location --connectivity-mode direct --profile-name $ENV:storageProfileName  --auto-upload-logs true --auto-upload-metrics true --custom-location $ENV:clName
# Can take some time 

# In VS Code, open new pwsh terminal to run the kubectl
#### Monitor 
kubectl get namespaces

#### Get pods 
kubectl get pods --namespace $ENV:namespace -o wide -w

#### Get services 
kubectl get services --namespace $ENV:namespace

#### Open Lens and view the pods and logs

#### Go to portal, view resource group 



## Create Arc-enabled SQL Managed Instance 
$ENV:gpinstance = "mi-gp"
$ENV:bcinstance = "mi-bc"

## View the options available 
az sql mi-arc create --help

### General Purpose 
az sql mi-arc create --name $ENV:gpinstance --resource-group $ENV:resourceGroup  --location $ENV:location --subscription $ENV:subscription  --custom-location $ENV:clName --tier GeneralPurpose --dev 

### Business Critical 
az sql mi-arc create --name $ENV:bcinstance --resource-group $ENV:resourceGroup  --location $ENV:location --subscription $ENV:subscription  --custom-location $ENV:clName --tier BusinessCritical --replicas 3 --dev  

#### Monitor 

#### Get pods 
kubectl get pods --namespace $ENV:namespace -w

#### Get services 
kubectl get services --namespace $ENV:namespace

## Check it out! Get endpoint to connect. 
az sql mi-arc list --k8s-namespace $ENV:namespace --use-k8s

#### Go to ADS - connect to the MI. Also connect data controller to show Kibana and Grafana. 



## MI HA 

### General purpose - HA is provided by K8s 
#### Verify HA 
kubectl get pods --namespace $ENV:namespace
$pod = ""
### Delete pod  
kubectl delete pod $pod --namespace $ENV:namespace
kubectl get pods --namespace $ENV:namespace

### Business criticial - HA is an AG
#### Get primary endpoint 
az sql mi-arc list --k8s-namespace $ENV:namespace --use-k8s 
#### Get both primary and secondary endpoints
az sql mi-arc show --name $ENV:bcinstance --k8s-namespace $ENV:namespace --use-k8s 
####  Connect and view in ADS; database is read-only. 
####  Connect and view in SSMS, with the added benefit of seeing the AG info there. 

### Verify HA 
### Determine status (primary or secondary) of pod 
$ENV:sqlpod="mi-bc-0"
$ENV:sqlname=$ENV:sqlpod.Substring(0,$ENV:sqlpod.length-2)
kubectl get pod $ENV:sqlpod -n $ENV:namespace -o jsonpath="{.metadata.labels.role\.ag\.mssql\.microsoft\.com/$ENV:sqlname-$ENV:sqlname}"

####  Delete primary 
kubectl delete pod $ENV:sqlpod --namespace $ENV:namespace 
kubectl get pods --namespace $ENV:namespace 
#### Note that the pod that was just deleted is re-creating. 

### Determine status of pod 
$ENV:sqlpod="mi-bc-0"
$ENV:sqlname=$ENV:sqlpod.Substring(0,$ENV:sqlpod.length-2)
kubectl get pod $ENV:sqlpod -n $ENV:namespace -o jsonpath="{.metadata.labels.role\.ag\.mssql\.microsoft\.com/$ENV:sqlname-$ENV:sqlname}"
#### And that pod is secondary. 



## Restore AdvWorks 
kubectl get pods --namespace $ENV:namespace
$pod = ""
kubectl exec $pod -n $ENV:namespace -c arc-sqlmi -- wget https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks2019.bak -O /var/opt/mssql/data/AdventureWorks2019.bak
kubectl exec $pod -n $ENV:namespace -c arc-sqlmi -- /opt/mssql-tools/bin/sqlcmd -S localhost -U $admincredentials.UserName -P $admincredentials.Password -Q "RESTORE DATABASE AdventureWorks2019 FROM  DISK = N'/var/opt/mssql/data/AdventureWorks2019.bak' WITH MOVE 'AdventureWorks2017' TO '/var/opt/mssql/data/AdventureWorks2019.mdf', MOVE 'AdventureWorks2017_Log' TO '/var/opt/mssql/data/AdventureWorks2019_Log.ldf'"

## Go to ADS to connect and query 



## Create PostgreSQL Hyperscale server - to deploy in direct mode, use the portal 
## To deploy in indirect mode, use CLI
$pgserver = "pg"

### Get endpoints 
az postgres arc-server endpoint list --name $pgserver --k8s-namespace $ENV:namespace --use-k8s

kubectl get postgresqls/$pgserver --namespace $ENV:namespace

#### Can connect with psql, pgadmin, or any other PostgreSQL tool  



## Clean up resources 

### Delete MI 
az sql mi-arc delete --name $ENV:bcinstance --resource-group $ENV:resourceGroup
az sql mi-arc delete --name $ENV:gpinstance --resource-group $ENV:resourceGroup

### Delete PG 
### Delete from portal 

### Delete data controller 
az arcdata dc delete --name $dataController --k8s-namespace $ENV:namespace


kubectl get nodes
kubectl get namespaces
kubectl get pods --namespace $ENV:namespace
kubectl get services --namespace $ENV:namespace
