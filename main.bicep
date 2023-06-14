targetScope = 'subscription'

// Governance parameters
@allowed([
  'eastus'
  'eastus2'
  'usgovvirginia'
])
param location string
@allowed([
  'test'
  'demo'
  'prod'
  'TEST'
  'DEMO'
  'PROD'
  ''
])
param environment string = ''
param workloadName string
param tags object
param sequence int
param namingConvention string

// Existing resources
param kvRgName string
param kvName string
param appGwSnId string

// Application Gateway configuration
@description('One or more SSL certificates to be used for the HTTPS listeners. Schema: [{ name: string, kvSecretId: string }]')
param appGwSslCertificates array
@description('One or more configurations for listeners. Schema: [{ name: string, hostNames: [ string ], appGwSslCertificateName: string, backendName: string }]')
param appGwListeners array
@description('One or more backend applications. Schema: [{ name: string, customProbePath: string, backendAddress: string }]')
param appGwBackends array

// Optional parameters
param deploymentTime string = utcNow()

// Variables
var sequenceFormatted = format('{0:00}', sequence)

var deploymentNameStructure = replace('${workloadName}-${environment}-{rtype}-${deploymentTime}', '-', '')
// Naming structure only needs the resource type ({rtype}) replaced
var namingStructure = replace(replace(replace(replace(replace(namingConvention, '{env}', environment), '{loc}', location), '{seq}', sequenceFormatted), '{wloadname}', workloadName), '-', '')

var networkingRgName = split(appGwSnId, '/')[4]

// region Resource Groups

resource networkingRg 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  name: networkingRgName
}

resource kvRg 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  name: kvRgName
}

// endregion

// region Key Vault

resource kv 'Microsoft.KeyVault/vaults@2023-02-01' existing = {
  name: kvName
  scope: kvRg
}

// endregion

// region Deploy the Application Gateway

// Deploy a user-assigned managed identity to allow the App GW to retrieve TLS certs from KV
module uamiModule 'modules/uami.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'uami'), 64)
  scope: networkingRg
  params: {
    location: location
    identityName: replace(namingStructure, '{rtype}', 'uami-appgw')
    tags: tags
  }
}

module uamiKvRoleAssignmentModule 'common-modules/roleAssignments/roleAssignment-kv.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'role-uami-kv'), 64)
  scope: kvRg
  params: {
    kvName: kv.name
    principalId: uamiModule.outputs.principalId
    roleDefinitionId: rolesModule.outputs.roles['Key Vault Secrets User']
  }
}

// Create a public IP address for the App GW frontend
module pipModule 'modules/networking/pip.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'pip-appgw'), 64)
  scope: networkingRg
  params: {
    name: replace(namingStructure, '{rtype}', 'pip-appgw')
    tags: tags
    location: location
  }
}

// region Application Gateway name variables
var appGwName = take(replace(namingStructure, '{rtype}', 'appgw'), 80)
var httpSettingsName = 'httpSettings443'
var frontendIpName = 'appGwPublicFrontendIp'
var frontendPortNamePrefix = 'Public'
var backendAddressPoolNamePrefix = 'be-'
var routingRuleNamePrefix = 'rr-'
var httpListenerNamePrefix = 'l-http'
var redirectRoutingRuleNameSuffix = '-http-redirect'
//var healthProbeNamePrefix = 'hp-'
var redirectNamePrefix = 'redirect-'

var appGwExpectedResourceId = '${networkingRg.id}/providers/Microsoft.Network/applicationGateways/${appGwName}'
// endregion

// Create the configuration for all routing rules: redirects and backends

var httpsRequestRoutingRules = [for (listener, i) in appGwListeners: {
  name: '${routingRuleNamePrefix}${listener.name}'
  properties: {
    ruleType: 'Basic'
    priority: 100 + i
    httpListener: {
      id: '${appGwExpectedResourceId}/httpListeners/${httpListenerNamePrefix}s-${listener.name}'
    }
    backendAddressPool: {
      id: '${appGwExpectedResourceId}/backendAddressPools/${backendAddressPoolNamePrefix}${listener.backendName}'
    }
    backendHttpSettings: {
      id: '${appGwExpectedResourceId}/backendHttpSettingsCollection/${httpSettingsName}'
    }
  }
}]

var httpRequestRoutingRules = [for (listener, i) in appGwListeners: {
  name: '${routingRuleNamePrefix}${listener.name}${redirectRoutingRuleNameSuffix}'
  properties: {
    ruleType: 'Basic'
    priority: 200 + i
    httpListener: {
      id: '${appGwExpectedResourceId}/httpListeners/${httpListenerNamePrefix}-${listener.name}'
    }
    redirectConfiguration: {
      id: '${appGwExpectedResourceId}/redirectConfigurations/${redirectNamePrefix}${listener.name}'
    }
  }
}]

var allRequestRoutingRules = concat(httpsRequestRoutingRules, httpRequestRoutingRules)

// Create the configuration for all listeners: HTTP and HTTPS

var httpsListeners = [for i in range(0, length(appGwListeners)): {
  name: '${httpListenerNamePrefix}s-${appGwListeners[i].name}'
  properties: {
    frontendIPConfiguration: {
      id: '${appGwExpectedResourceId}/frontendIPConfigurations/${frontendIpName}'
    }
    frontendPort: {
      id: '${appGwExpectedResourceId}/frontendPorts/${frontendPortNamePrefix}443'
    }
    hostNames: appGwListeners[i].hostNames
    sslCertificate: {
      id: '${appGwExpectedResourceId}/sslCertificates/${appGwListeners[i].appGwSslCertificateName}'
    }
    protocol: 'Https'
  }
}]

var httpListeners = [for i in range(0, length(appGwListeners)): {
  name: '${httpListenerNamePrefix}-${appGwListeners[i].name}'
  properties: {
    frontendIPConfiguration: {
      id: '${appGwExpectedResourceId}/frontendIPConfigurations/${frontendIpName}'
    }
    frontendPort: {
      id: '${appGwExpectedResourceId}/frontendPorts/${frontendPortNamePrefix}80'
    }
    hostNames: appGwListeners[i].hostNames
    protocol: 'Http'
  }
}]

var allListeners = concat(httpsListeners, httpListeners)

// Create the Application Gateway resource

module appGwModule 'modules/networking/appGw.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'appgw'), 64)
  scope: networkingRg
  params: {
    location: location
    tags: tags

    name: appGwName

    backendAddressPools: [for be in appGwBackends: {
      name: '${backendAddressPoolNamePrefix}${be.name}'
      properties: {
        backendAddresses: [
          {
            fqdn: be.backendAddress
          }
        ]
      }
    }]

    httpListeners: allListeners

    requestRoutingRules: allRequestRoutingRules

    sslCertificates: [for i in range(0, length(appGwSslCertificates)): {
      name: appGwSslCertificates[i].name
      properties: {
        keyVaultSecretId: appGwSslCertificates[i].kvSecretId
      }
    }]

    frontendPorts: [
      {
        name: '${frontendPortNamePrefix}80'
        properties: {
          port: 80
        }
      }
      {
        name: '${frontendPortNamePrefix}443'
        properties: {
          port: 443
        }
      }
    ]

    // Use a single configuration for all backends
    backendHttpSettingsCollection: [
      {
        name: httpSettingsName
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: true
          requestTimeout: 30
        }
      }
    ]

    frontendIPConfigurations: [
      {
        name: frontendIpName
        properties: {
          publicIPAddress: {
            id: pipModule.outputs.id
          }
        }
      }
    ]

    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: appGwSnId
          }
        }
      }
    ]

    redirectConfigurations: [for listener in appGwListeners: {
      name: '${redirectNamePrefix}${listener.name}'
      properties: {
        redirectType: 'Permanent'
        includePath: true
        includeQueryString: true
        requestRoutingRules: [
          {
            id: '${appGwExpectedResourceId}/requestRoutingRules/${routingRuleNamePrefix}${listener.name}${redirectRoutingRuleNameSuffix}'
          }
        ]
        targetListener: {
          id: '${appGwExpectedResourceId}/httpListeners/${httpListenerNamePrefix}s-${listener.name}'
        }
      }
    }]

    userAssignedIdentities: {
      '${uamiModule.outputs.id}': {}
    }

    enableHttp2: true
    sslPolicyName: 'AppGwSslPolicy20220101'
    sslPolicyType: 'Predefined'

    webApplicationFirewallConfiguration: {
      enabled: true
      firewallMode: 'Detection'
      ruleSetType: 'OWASP'
      ruleSetVersion: '3.2'
    }
  }
  dependsOn: [
    uamiModule
  ]
}

// endregion

module rolesModule 'common-modules/roles.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'roles'), 64)
}

output appGwPublicIpAddress string = pipModule.outputs.ipAddress
