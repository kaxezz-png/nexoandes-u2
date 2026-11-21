variable "name_prefix" {
  description = "Prefijo na-u2-cNN-aNNN."
  type        = string
}

variable "x" {
  description = "Numero X del alumno (define 10.X.0.0/16)."
  type        = number
}

variable "app_version" {
  description = "Version del Portal que instala el bootstrap (v1/v2)."
  type        = string
}

variable "build_ref" {
  description = "Referencia del commit desplegado (se copia a los tags de la instancia)."
  type        = string
}

variable "bootstrap" {
  description = "Script de bootstrap ya renderizado (sin codificar)."
  type        = string
}

variable "instance_type" {
  description = "Tipo de instancia EC2."
  type        = string
}

variable "capacity" {
  description = "Capacidad base fija del ASG."
  type        = number
}

variable "ami_id" {
  description = "AMI fija; vacio = ultima Ubuntu 22.04 LTS."
  type        = string
  default     = ""
}

variable "allowed_http_cidrs" {
  description = "Origenes autorizados para HTTP 80 hacia el ALB."
  type        = list(string)
}

variable "tags" {
  description = "Tags comunes con proveedor=aws (para instancias y volumenes del ASG)."
  type        = map(string)
}
