# Salidas por contexto. Sirven para correlacionar con la consulta al
# proveedor y con la respuesta HTTP del Portal (E02, E03).

output "identidad" {
  description = "Identidad U2 configurada."
  value = {
    proyecto    = "NexoAndes"
    fase        = "U2"
    x           = var.x
    alumno      = local.student
    curso       = var.course
    prefijo     = local.name_prefix
    build_ref   = var.build_ref
    version_aws = var.app_version
    version_az  = "v1"
  }
}

output "aws" {
  description = "Recursos y endpoint del contexto AWS."
  value = {
    region                  = var.aws_region
    endpoint                = "http://${module.portal_aws.alb_dns_name}"
    alb_dns_name            = module.portal_aws.alb_dns_name
    vpc_id                  = module.portal_aws.vpc_id
    vpc_cidr                = module.portal_aws.vpc_cidr
    subnet_ids              = module.portal_aws.subnet_ids
    subnet_cidrs            = module.portal_aws.subnet_cidrs
    asg_name                = module.portal_aws.asg_name
    target_group_arn        = module.portal_aws.target_group_arn
    launch_template_id      = module.portal_aws.launch_template_id
    launch_template_version = module.portal_aws.launch_template_version
    ami_id                  = module.portal_aws.ami_id
  }
}

output "azure" {
  description = "Recursos y endpoint del contexto Azure."
  value = {
    location       = var.azure_location
    endpoint       = "http://${module.portal_azure.public_ip}"
    resource_group = module.portal_azure.resource_group_name
    vnet_cidr      = module.portal_azure.vnet_cidr
    subnet_cidr    = module.portal_azure.subnet_cidr
    vm_name        = module.portal_azure.vm_name
    vm_id          = module.portal_azure.vm_id
    public_ip      = module.portal_azure.public_ip
    private_ip     = module.portal_azure.private_ip
  }
}

# Salidas simples (texto) para que el pipeline las lea con `terraform output -raw`.
output "aws_endpoint" {
  value = "http://${module.portal_aws.alb_dns_name}"
}

output "aws_asg_name" {
  value = module.portal_aws.asg_name
}

output "aws_target_group_arn" {
  value = module.portal_aws.target_group_arn
}

output "aws_launch_template_version" {
  value = tostring(module.portal_aws.launch_template_version)
}

output "aws_app_version" {
  value = var.app_version
}

output "azure_endpoint" {
  value = "http://${module.portal_azure.public_ip}"
}

output "azure_resource_group" {
  value = module.portal_azure.resource_group_name
}

output "azure_vm_name" {
  value = module.portal_azure.vm_name
}
