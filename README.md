# Bicep-AppGateway

An abstraction of the CARML Azure Application Gateway module

## Assumptions

- The Azure Virtual Network in which to deploy the Application Gateway has a suitable empty subnet. The subnet may have pre-configured route tables and NSGs, as long as they are compatible with Application Gateway requirements.
- TLS certificates for the frontend listeners are available in a Key Vault.
- App Service endpoints already exist and are ready to accept requests.

## Results

- An Application Gateway V2 with WAF instance will be created in the same resource group as the specified subnet.

## Credits

- The *modules/networking/appGw.bicep* module is from the CARML project.
