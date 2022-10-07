# デプロイ先のリージョン名を定義する
region="japaneast"
resourceGroupName=$1

# リソースグループを作成する
az group create --location $region --resource-group $resourceGroupName

# Azureリソースをデプロイする
az deployment group create --resource-group $resourceGroupName --template-file "deploy.bicep" --parameters @parameters.json

# セットアップに必要な情報を収集する
subscriptionId=`az account show --query "id" --output tsv`
outputs=($(az deployment group show --name 'deploy' --resource-group $resourceGroupName --query 'properties.outputs.*.value' --output tsv))
cognitiveSearchName=`echo ${outputs[0]}` # 末尾に \r が付いてくるので削除する
cosmosDBAccountName=`echo ${outputs[1]}` # 末尾に \r が付いてくるので削除する
cosmosDBDatabaseName=`echo ${outputs[2]}` # 末尾に \r が付いてくるので削除する
cosmosDBContainerName=${outputs[3]}
apiKey=`az search admin-key show --service-name $cognitiveSearchName --resource-group $resourceGroupName --query 'primaryKey' --output tsv`

# Cosmos DB へアイテムを登録する
cd datasource
dotnet run --account-name $cosmosDBAccountName --db-name $cosmosDBDatabaseName --container-name $cosmosDBContainerName --json-file-path "../jsons/items.json"
cd ..

# データソースを作成する
curl -X POST https://$cognitiveSearchName.search.windows.net/datasources?api-version=2020-06-30 \
    -H 'Content-Type: application/json' \
    -H 'api-key: '$apiKey \
    -d @- <<EOS
{
    "type": "cosmosdb",
    "name": "cosmos-source",
    "credentials": {
        "connectionString": "ResourceId=/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.DocumentDB/databaseAccounts/$cosmosDBAccountName;Database=$cosmosDBDatabaseName;"
    },
    "container": {
        "name": "$cosmosDBContainerName",
        "query": "SELECT * FROM c WHERE c._ts >= @HighWaterMark ORDER BY c._ts"
    }
}
EOS

# インデックスを作成する
curl -X POST https://$cognitiveSearchName.search.windows.net/indexes?api-version=2020-06-30 \
    -H 'Content-Type: application/json' \
    -H 'api-key: '$apiKey \
    -d @jsons/index.json

# インデクサーを作成する
curl -X POST https://$cognitiveSearchName.search.windows.net/indexers?api-version=2020-06-30 \
    -H 'Content-Type: application/json' \
    -H 'api-key: '$apiKey \
    -d @jsons/indexer.json

# Web アプリで使用する情報を JSON ファイルとして出力する (Cognitive Searviceの名前とクエリキー)
queryKey=`az search query-key list --resource-group $resourceGroupName --service-name $cognitiveSearchName --query "[0].key" --output tsv`
echo "const settings = { \"cognitiveSearchName\": \"$cognitiveSearchName\", \"queryKey\": \"$queryKey\" };" > website/settings.js
