# Contextos separados por nube. Ninguna credencial se escribe en el codigo.
# - AWS: credenciales temporales del Learner Lab en el perfil local
#   (~/.aws/credentials) del equipo que ejecuta el runner.
# - Azure: sesion de Azure CLI (`az login`) del alumno. El tenant del
#   instituto no permite registrar service principals (Insufficient
#   privileges), por eso el pipeline corre en un runner autoalojado.
#   La suscripcion se indica con ARM_SUBSCRIPTION_ID.

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(local.common_tags, { proveedor = "aws" })
  }
}

provider "azurerm" {
  features {}
}
