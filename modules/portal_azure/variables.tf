variable "name_prefix" {
  description = "Prefijo na-u2-cNN-aNNN."
  type        = string
}

variable "x" {
  description = "Numero X del alumno (define 172.20.X.0/24)."
  type        = number
}

variable "location" {
  description = "Ubicacion autorizada de Azure."
  type        = string
}

variable "vm_size" {
  description = "Tamano de la VM."
  type        = string
}

variable "bootstrap" {
  description = "Script de bootstrap ya renderizado (sin codificar), siempre v1."
  type        = string
}

variable "admin_username" {
  description = "Usuario administrativo exigido por la plataforma."
  type        = string
}

variable "admin_ssh_public_key" {
  description = "Clave publica SSH (solo publica)."
  type        = string
}

variable "allowed_http_cidrs" {
  description = "Origenes autorizados para HTTP 80."
  type        = list(string)
}

variable "tags" {
  description = "Tags comunes con proveedor=azure."
  type        = map(string)
}
