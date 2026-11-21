# Orquestacion U2: un solo root module compone el modulo AWS y el modulo Azure.
# Parametros comunes -> locals; parametros especificos -> cada modulo.

locals {
  student     = format("a%03d", var.x)
  name_prefix = "na-u2-${var.course}-${local.student}"

  common_tags = {
    proyecto = "NexoAndes"
    fase     = "U2"
    alumno   = local.student
    curso    = var.course
  }

  # Integracion del artefacto docente (README_ESTUDIANTE_U2, seccion 5).
  portal_identity = {
    x         = var.x
    student   = local.student
    course    = var.course
    build_ref = var.build_ref
  }

  portal_aws_bootstrap = templatefile(
    "${path.root}/templates/user_data_u2.sh.tpl",
    merge(local.portal_identity, {
      provider       = "aws"
      portal_version = var.app_version
    })
  )

  portal_azure_bootstrap = templatefile(
    "${path.root}/templates/user_data_u2.sh.tpl",
    merge(local.portal_identity, {
      provider       = "azure"
      portal_version = "v1"
    })
  )
}

module "portal_aws" {
  source = "./modules/portal_aws"

  name_prefix        = local.name_prefix
  x                  = var.x
  app_version        = var.app_version
  build_ref          = var.build_ref
  bootstrap          = local.portal_aws_bootstrap
  instance_type      = var.aws_instance_type
  capacity           = var.aws_capacity
  ami_id             = var.aws_ami_id
  allowed_http_cidrs = var.allowed_http_cidrs
  tags               = merge(local.common_tags, { proveedor = "aws" })
}

module "portal_azure" {
  source = "./modules/portal_azure"

  name_prefix          = local.name_prefix
  x                    = var.x
  location             = var.azure_location
  vm_size              = var.azure_vm_size
  bootstrap            = local.portal_azure_bootstrap
  admin_username       = var.azure_admin_username
  admin_ssh_public_key = var.azure_admin_ssh_public_key
  allowed_http_cidrs   = var.allowed_http_cidrs
  tags                 = merge(local.common_tags, { proveedor = "azure" })
}
