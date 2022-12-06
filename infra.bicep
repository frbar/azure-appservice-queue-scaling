targetScope = 'resourceGroup'

param envName string
param sku string = 'S1'                                     // The SKU of App Service Plan
param linuxFxVersion string = 'DOTNETCORE|6.0'              // The runtime stack of web app
param location string = resourceGroup().location            // Location for all resources

//
// Service Bus Namespace
// 

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-01-01-preview' = {
  name: '${envName}sb'
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {}
}

resource serviceBusQueue 'Microsoft.ServiceBus/namespaces/queues@2022-01-01-preview' = {
  parent: serviceBusNamespace
  name: 'jobs'
  properties: {
    lockDuration: 'PT5M'
    maxSizeInMegabytes: 1024
    requiresDuplicateDetection: false
    requiresSession: false
    defaultMessageTimeToLive: 'P14D'
    deadLetteringOnMessageExpiration: false
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    maxDeliveryCount: 10
    enablePartitioning: false
    enableExpress: false
  }
}

var servicebusconnectionstring = listKeys('${serviceBusNamespace.id}/AuthorizationRules/RootManageSharedAccessKey', serviceBusNamespace.apiVersion).primaryConnectionString
output servicebusconnectionstring string = servicebusconnectionstring

//
// Log Analytics & App Insights
//

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2020-08-01' = {
  name: '${envName}-logs'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      searchVersion: 1
      legacy: 0
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${envName}-appinsights'
  location: location
  kind: 'string'
  tags: {
    displayName: 'AppInsight'
    ProjectName: envName
  }
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId:  logAnalyticsWorkspace.id
  }
}

//
// App Service
// 

resource appServicePlan 'Microsoft.Web/serverfarms@2020-06-01' = {
  name: '${envName}-plan'
  location: location
  properties: {
    reserved: true
  }
  sku: {
    name: sku
  }
  kind: 'linux'
}

resource appService 'Microsoft.Web/sites@2020-06-01' = {
  name: '${envName}-app'
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: linuxFxVersion
      appSettings: [
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
        {
          name: 'NAMESPACE_CONNECTION_STRING'
          value: servicebusconnectionstring
        }
        {
          name: 'QUEUE_NAME'
          value: serviceBusQueue.name
        }
        {
          name: 'SLEEP_DURATION_SEC'
          value: '5'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
      ]
      healthCheckPath: '/health'
    }
  }
  dependsOn: [
    logAnalyticsWorkspace
  ]
}

resource appServiceAppSettings 'Microsoft.Web/sites/config@2020-06-01' = {
  parent: appService
  name: 'logs'
  properties: {
    applicationLogs: {
      fileSystem: {
        level: 'Information'
      }
    }
    httpLogs: {
      fileSystem: {
        retentionInMb: 40
        enabled: true
      }
    }
    failedRequestsTracing: {
      enabled: true
    }
    detailedErrorMessages: {
      enabled: true
    }
  }
}

resource appServiceDiagnosticSettings 'microsoft.insights/diagnosticSettings@2017-05-01-preview' = {
  scope: appService
  name: 'logs'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
        {
          enabled: true
          category: 'AppServiceConsoleLogs'
        }
        {
          enabled: true
          category: 'AppServiceAppLogs'
        }
        {
          enabled: true
          category: 'AppServicePlatformLogs'
        }
      ]
    metrics: [
        {
          enabled: true
          category: 'AllMetrics'
        }
      ]
    }
}

//
// auto-scale rule
//

resource autoScaleRule 'Microsoft.Insights/autoscalesettings@2022-10-01' = {
  name: 'rule1'
  location: location
  properties: {
    enabled: true
    targetResourceUri: appServicePlan.id
    profiles: [
      {
        name: 'profile1'
        capacity: {
          default: '1'
          minimum: '1'
          maximum: '3'
        }
        rules: [
          {
            metricTrigger: {
              metricName: 'MessageCount'
              metricResourceUri: serviceBusQueue.id
              operator: 'GreaterThan'
              statistic: 'Average'
              threshold: 10
              timeAggregation: 'Average'
              timeGrain: 'PT1M'
              timeWindow: 'PT10M'
              dividePerInstance: true
            }
            scaleAction: {
              cooldown: 'PT5M'
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
            }
          }
          {
            metricTrigger: {
              metricName: 'MessageCount'
              metricResourceUri: serviceBusQueue.id
              operator: 'LessThan'
              statistic: 'Average'
              threshold: 5
              timeAggregation: 'Average'
              timeGrain: 'PT1M'
              timeWindow: 'PT10M'
              dividePerInstance: true
            }
            scaleAction: {
              cooldown: 'PT5M'
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'
            }
          }
        ]
      }
    ]
  }
}
