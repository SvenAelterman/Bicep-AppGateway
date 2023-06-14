param name string
param location string = resourceGroup().location
param tags object

resource pip 'Microsoft.Network/publicIPAddresses@2022-05-01' = {
  name: name
  location: location
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
  }
  sku: {
    name: 'Standard'
  }
  tags: tags
}

output ipAddress string = pip.properties.ipAddress
output id string = pip.id
