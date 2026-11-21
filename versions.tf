# Versiones fijadas de Terraform y de los providers (CE3).
# Cada provider se configura una sola vez: no se usan alias porque
# no hay dos configuraciones distintas del mismo provider.

terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.14"
    }
  }

  # State remoto en S3 con bloqueo por archivo (use_lockfile).
  # Configuracion parcial: bucket, key y region se entregan en
  # `terraform init -backend-config=...` desde el pipeline, para no
  # versionar nombres de cuenta. El state NUNCA se sube a Git.
  backend "s3" {}
}
