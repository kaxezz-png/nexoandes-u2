# Contextos separados por nube.
# - AWS: credenciales temporales del laboratorio por variables de entorno
#   (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN).
# - Azure: service principal por variables de entorno
#   (ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID).
# Ninguna credencial se escribe en el codigo.

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(local.common_tags, { proveedor = "aws" })
  }
}

provider "azurerm" {
  features {}
}
