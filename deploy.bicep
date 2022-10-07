// パラメータ
param location string = resourceGroup().location
param resourceNameSuffix string = uniqueString(resourceGroup().id)
param cognitiveSearchSku string
param cosmosDatabaseName string
param cosmosContainerName string
param cosmosPartitionKey string
param myPrincipalId string // .Net アプリケーションで使用するプリンシパル情報

// Cognitive Search Service
resource cognitiveSearch 'Microsoft.Search/searchServices@2021-04-01-preview' = {
  name: 'cogs-${resourceNameSuffix}'
  location: location
  sku: {
    name: cognitiveSearchSku
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hostingMode: 'default'
    publicNetworkAccess: 'enabled'
    partitionCount: 1
    replicaCount: 1
  }
}

// Azure Cosmos DB - アカウント
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2021-05-15' = {
  name: 'cosmos-${resourceNameSuffix}'
  location: location
  properties: {
    databaseAccountOfferType: 'Standard'
    locations: [
      {
        locationName: location
      }
    ]
  }
}

// Azure Cosmos DB - データベース
resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2021-05-15' = {
  parent: cosmosAccount
  name: cosmosDatabaseName
  properties: {
    options: {}
    resource: {
      id: cosmosDatabaseName
    }
  }
}

// Azure Cosmos DB - コンテナ
resource cosmosContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2021-05-15' = {
  parent: cosmosDatabase
  name: cosmosContainerName
  properties: {
    resource: {
      id: cosmosContainerName
      partitionKey: {
        paths: [
          cosmosPartitionKey
        ]
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: []
        compositeIndexes: []
      }
    }
  }
}

// Azure Cosmos DB - ロール定義 (カスタムロール)
resource cosmosRoleDefinition 'Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions@2021-11-15-preview' = {
  name: guid(resourceGroup().id, cosmosAccount.id)
  parent: cosmosAccount
  properties: {
    roleName: 'CosmosDBDataContributor'
    type: 'CustomRole'
    assignableScopes: [
      cosmosAccount.id
    ]
    permissions: [
      {
        dataActions: [
          'Microsoft.DocumentDB/databaseAccounts/readMetadata'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/*'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/*'
        ]
        notDataActions: []
      }
    ]
  }
}

// ロール割り当て：.Netアプリ → Cosmos DB (カスタムロール)
resource cosmosRoleAssignment1 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2021-11-15-preview' = {
  name: guid(resourceGroup().id, cosmosRoleDefinition.id, myPrincipalId)
  parent: cosmosAccount
  properties: {
    principalId: myPrincipalId
    roleDefinitionId: cosmosRoleDefinition.id
    scope: cosmosAccount.id
  }
}

// ロール割り当て：Cognitive Search → Cosmos DB (カスタムロール)
resource cosmosRoleAssignment2 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2021-11-15-preview' = {
  name: guid(resourceGroup().id, cosmosRoleDefinition.id, cognitiveSearch.id)
  parent: cosmosAccount
  properties: {
    principalId: cognitiveSearch.identity.principalId
    roleDefinitionId: cosmosRoleDefinition.id
    scope: cosmosAccount.id
  }
  dependsOn: [
    cosmosRoleAssignment1
  ]
}

// ロール定義：Cosmos DB アカウントの閲覧者ロール (Cosmos DB アカウントの閲覧者ロール)
resource roleDefinition 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  scope: cosmosAccount
  name: 'fbdf93bf-df7d-467e-a4d2-9458aa1360c8' // Cosmos DB アカウントの閲覧者ロール
}

// ロール割り当て：Cognitive Search → Cosmos DB (Cosmos DB アカウントの閲覧者ロール)
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(resourceGroup().id, cognitiveSearch.id, roleDefinition.id)
  properties: {
    roleDefinitionId: roleDefinition.id
    principalId: cognitiveSearch.identity.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    cosmosRoleAssignment2
  ]
}

// パラメータ出力
output cognitiveSearchName string = cognitiveSearch.name
output cosmosDBAccountName string = cosmosAccount.name
output cosmosDBDatabaseName string = cosmosDatabase.name
output cosmosDBContainerName string = cosmosContainer.name
