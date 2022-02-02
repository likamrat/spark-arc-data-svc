az group create --name Spark-Arc-Data-Svc --location "East US"
az deployment group create \
--resource-group Spark-Arc-Data-Svc \
--name spark \
--template-uri https://raw.githubusercontent.com/likamrat/spark-arc-data-svc/main/azuredeploy.json \
--parameters azuredeploy.parameters.lior.json
