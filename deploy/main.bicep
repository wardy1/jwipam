// Global parameters
targetScope = 'subscription'

@description('GUID for Resource Naming')
param guid string = newGuid()

@description('Deployment Location')
param location string = 'uksouth'

@description('Azure Cloud Enviroment')
param azureCloud string = 'AZURE_PUBLIC'

@description('Flag to Deploy Private Container Registry')
param privateAcr bool = false

@description('Flag to Deploy IPAM as a Function')
param deployAsFunc bool = false

@description('Flag to Deploy IPAM as a Container')
param deployAsContainer bool = false

@description('IPAM-UI App Registration Client/App ID')
param uiAppId string = '00000000-0000-0000-0000-000000000000'

@description('IPAM-Engine App Registration Client/App ID')
param engineAppId string

@secure()
@description('IPAM-Engine App Registration Client Secret')
param engineAppSecret string

@description('Tags')
param tags object = {}

@maxLength(7)
@description('Prefix for Resource Naming')
param namePrefix string = 'ipam'

@description('IPAM Resource Names')
var resourceNames = {
  functionName: 'func-cps-ipam-dev-uksouth-001'
  appServiceName: 'as-cps-ipam-dev-uksouth-001'
  functionPlanName: 'funcpn-cps-ipam-dev-uksouth-001'
  appServicePlanName: 'asep-cps-ipam-dev-uksouth-001'
  cosmosAccountName: 'cm-cps-ipam-dev-uksouth-001'
  cosmosContainerName: 'cosmos-ctr-cps-ipam-dev-uksouth-001'
  cosmosDatabaseName: 'cosmos-db-cps-ipam-dev-uksouth-001'
  keyVaultName: 'kv-jwt-uksouth-007'
  workspaceName: 'log-analytics-cps-ipam-dev-uksouth-001'
  managedIdentityName: '${namePrefix}-mi-${uniqueString(guid)}'
  resourceGroupName: 'rg-cps-ipam-dev-uksouth-001'
  storageAccountName: 'st-cps-ipam-dev-uksouth-001'
  containerRegistryName: 'cr-cps-ipam-dev-uksouth-001'
}

// Resource Group
resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  location: location
  #disable-next-line use-stable-resource-identifiers
  name: resourceNames.resourceGroupName
  tags: tags
}

// Log Analytics Workspace
module logAnalyticsWorkspace './modules/logAnalyticsWorkspace.bicep' = {
  name: 'logAnalyticsWorkspaceModule'
  scope: resourceGroup
  params: {
    location: location
    workspaceName: resourceNames.workspaceName
  }
}

// Managed Identity for Secure Access to KeyVault
module managedIdentity './modules/managedIdentity.bicep' = {
  name: 'managedIdentityModule'
  scope: resourceGroup
  params: {
    location: location
    managedIdentityName: resourceNames.managedIdentityName
  }
}

// KeyVault for Secure Values
module keyVault './modules/keyVault.bicep' = {
  name: 'keyVaultModule'
  scope: resourceGroup

  params: {
    location: location
    keyVaultName: resourceNames.keyVaultName
    identityPrincipalId: managedIdentity.outputs.principalId
    identityClientId: managedIdentity.outputs.clientId
    uiAppId: uiAppId
    engineAppId: engineAppId
    engineAppSecret: engineAppSecret
    workspaceId: logAnalyticsWorkspace.outputs.workspaceId
  }
}

module privateEndpoint 'br/public:avm/res/network/private-endpoint:0.7.0' = {
  name: 'privateEndpointDeployment'
  scope: resourceGroup
  params: {
    // Required parameters
    name: 'ipamkv'
    subnetResourceId: '/subscriptions/5e0b33cf-2cfb-487b-ac44-f9877e08edb8/resourceGroups/rg-vnw-hub-uks-1/providers/Microsoft.Network/virtualNetworks/vnw-hub-uks-1/subnets/privateendpoints'
    // Non-required parameters
    customNetworkInterfaceName: 'ipamkvnic'
    ipConfigurations: [
      {
        name: 'myIPconfig'
        properties: {
          groupId: 'vault'
          memberName: 'default'
          privateIPAddress: '10.0.0.10'
        }
      }
    ]
    location: location
    lock: {
      kind: 'CanNotDelete'
      name: 'myCustomLockName'
    }
    privateDnsZoneGroup: {
      privateDnsZoneGroupConfigs: [
        {
          privateDnsZoneResourceId: '/subscriptions/5e0b33cf-2cfb-487b-ac44-f9877e08edb8/resourceGroups/rg-privdns-uks-1/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net'
        }
      ]
    }
    privateLinkServiceConnections: [
      {
        name: 'kv-jwt-uksouth-002'
        properties: {
          groupIds: [
            'vault'
          ]
          privateLinkServiceId: '/subscriptions/5e0b33cf-2cfb-487b-ac44-f9877e08edb8/resourceGroups/rg-cps-ipam-dev-uksouth-001/providers/Microsoft.KeyVault/vaults/kv-jwt-uksouth-007'
        }
      }
    ]
    tags: {
      Environment: 'Non-Prod'
      'hidden-title': 'This is visible in the resource name'
      Role: 'DeploymentValidation'
    }
  }
  dependsOn: [
    keyVault
  ]
}

// Cosmos DB for IPAM Database
module cosmos './modules/cosmos.bicep' = {
  name: 'cosmosModule'
  scope: resourceGroup
  params: {
    location: location
    cosmosAccountName: resourceNames.cosmosAccountName
    cosmosContainerName: resourceNames.cosmosContainerName
    cosmosDatabaseName: resourceNames.cosmosDatabaseName
    keyVaultName: keyVault.outputs.keyVaultName
    workspaceId: logAnalyticsWorkspace.outputs.workspaceId
    principalId: managedIdentity.outputs.principalId
  }
}

module privateEndpointcosmos 'br/public:avm/res/network/private-endpoint:0.7.0' = {
  name: 'privateEndpointDeploymentcosmos'
  scope: resourceGroup
  params: {
    // Required parameters
    name: 'ipam-cosmos'
    subnetResourceId: '/subscriptions/5e0b33cf-2cfb-487b-ac44-f9877e08edb8/resourceGroups/rg-vnw-hub-uks-1/providers/Microsoft.Network/virtualNetworks/vnw-hub-uks-1/subnets/privateendpoints'
    location: location
    privateLinkServiceConnections: [
      {
        name: 'cosmos-cps-ipam-dev-uksouth-001'
        properties: {
          groupIds: [
            'Sql'
          ]
          privateLinkServiceId: '/subscriptions/5e0b33cf-2cfb-487b-ac44-f9877e08edb8/resourceGroups/rg-cps-ipam-dev-uksouth-001/providers/Microsoft.DocumentDB/databaseAccounts/cm-cps-ipam-dev-uksouth-001'
        }
      }
    ]
  }
  dependsOn: [
    cosmos
  ]
}

// Storage Account for Nginx Config/Function Metadata
module storageAccount './modules/storageAccount.bicep' = if (deployAsFunc) {
  scope: resourceGroup
  name: 'storageAccountModule'
  params: {
    location: location
    storageAccountName: resourceNames.storageAccountName
    workspaceId: logAnalyticsWorkspace.outputs.workspaceId
  }
}

// Container Registry
module containerRegistry './modules/containerRegistry.bicep' = if (privateAcr) {
  scope: resourceGroup
  name: 'containerRegistryModule'
  params: {
    location: location
    containerRegistryName: resourceNames.containerRegistryName
    principalId: managedIdentity.outputs.principalId
  }
}

// App Service w/ Docker Compose + CI
module appService './modules/appService.bicep' = if (!deployAsFunc) {
  scope: resourceGroup
  name: 'appServiceModule'
  params: {
    location: location
    azureCloud: azureCloud
    appServiceName: resourceNames.appServiceName
    appServicePlanName: resourceNames.appServicePlanName
    keyVaultUri: keyVault.outputs.keyVaultUri
    cosmosDbUri: cosmos.outputs.cosmosDocumentEndpoint
    databaseName: resourceNames.cosmosDatabaseName
    containerName: resourceNames.cosmosContainerName
    managedIdentityId: managedIdentity.outputs.id
    managedIdentityClientId: managedIdentity.outputs.clientId
    workspaceId: logAnalyticsWorkspace.outputs.workspaceId
    deployAsContainer: deployAsContainer
    privateAcr: privateAcr
    privateAcrUri: privateAcr ? containerRegistry.outputs.acrUri : ''
  }
}

module privateEndpointappservice 'br/public:avm/res/network/private-endpoint:0.7.0' = {
  name: 'privateEndpointDeploymentappservice'
  scope: resourceGroup
  params: {
    // Required parameters
    name: 'ipam-appservice'
    subnetResourceId: '/subscriptions/5e0b33cf-2cfb-487b-ac44-f9877e08edb8/resourceGroups/rg-vnw-hub-uks-1/providers/Microsoft.Network/virtualNetworks/vnw-hub-uks-1/subnets/privateendpoints'
    location: location
    privateLinkServiceConnections: [
      {
        name: 'ipamappservice'
        properties: {
          groupIds: [
            'sites'
          ]
          privateLinkServiceId: '/subscriptions/5e0b33cf-2cfb-487b-ac44-f9877e08edb8/resourceGroups/rg-cps-ipam-dev-uksouth-001/providers/Microsoft.Web/sites/as-cps-ipam-dev-uksouth-001'
        }
      }
    ]
  }
  dependsOn: [
    appService
  ]
}

// Function App
module functionApp './modules/functionApp.bicep' = if (deployAsFunc) {
  scope: resourceGroup
  name: 'functionAppModule'
  params: {
    location: location
    azureCloud: azureCloud
    functionAppName: resourceNames.functionName
    functionPlanName: resourceNames.appServicePlanName
    keyVaultUri: keyVault.outputs.keyVaultUri
    cosmosDbUri: cosmos.outputs.cosmosDocumentEndpoint
    databaseName: resourceNames.cosmosDatabaseName
    containerName: resourceNames.cosmosContainerName
    managedIdentityId: managedIdentity.outputs.id
    managedIdentityClientId: managedIdentity.outputs.clientId
    storageAccountName: resourceNames.storageAccountName
    workspaceId: logAnalyticsWorkspace.outputs.workspaceId
    deployAsContainer: deployAsContainer
    privateAcr: privateAcr
    privateAcrUri: privateAcr ? containerRegistry.outputs.acrUri : ''
  }
}

// Outputs
output suffix string = uniqueString(guid)
output subscriptionId string = subscription().subscriptionId
output resourceGroupName string = resourceGroup.name
output appServiceName string = deployAsFunc ? resourceNames.functionName : resourceNames.appServiceName
output appServiceHostName string = deployAsFunc
  ? functionApp.outputs.functionAppHostName
  : appService.outputs.appServiceHostName
output acrName string = privateAcr ? containerRegistry.outputs.acrName : ''
output acrUri string = privateAcr ? containerRegistry.outputs.acrUri : ''
output keyvaultId string = keyVault.name
