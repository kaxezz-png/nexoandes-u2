# ---------- Parametros comunes (identidad U2) ----------

variable "x" {
  description = "Numero asignado por el docente (1-254). Define redes y alumno aNNN."
  type        = number

  validation {
    condition     = var.x >= 1 && var.x <= 254 && floor(var.x) == var.x
    error_message = "x debe ser un entero entre 1 y 254."
  }
}

variable "course" {
  description = "Codigo de curso con formato cNN."
  type        = string

  validation {
    condition     = can(regex("^c[0-9]{2}$", var.course))
    error_message = "course debe tener el formato cNN (ej. c01)."
  }
}

variable "build_ref" {
  description = "Referencia real del codigo desplegado. El pipeline entrega el SHA del commit."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{4,80}$", var.build_ref))
    error_message = "build_ref: 4 a 80 caracteres (letras, numeros, punto, guion o guion bajo)."
  }
}

variable "app_version" {
  description = "Version del Portal en AWS: v1 o v2. Azure conserva siempre v1."
  type        = string

  validation {
    condition     = contains(["v1", "v2"], var.app_version)
    error_message = "app_version debe ser v1 o v2."
  }
}

variable "allowed_http_cidrs" {
  description = "Origenes autorizados para HTTP 80 (ALB en AWS y NSG en Azure)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ---------- Parametros especificos de AWS ----------

variable "aws_region" {
  description = "Region autorizada de AWS."
  type        = string
  default     = "us-east-1"
}

variable "aws_instance_type" {
  description = "Tipo de instancia EC2 del Portal."
  type        = string
  default     = "t3.micro"
}

variable "aws_capacity" {
  description = "Capacidad base fija del grupo EC2 (min = max = deseada)."
  type        = number
  default     = 2

  validation {
    condition     = var.aws_capacity >= 2
    error_message = "Se requieren al menos 2 instancias para repartirlas en dos zonas."
  }
}

variable "aws_ami_id" {
  description = "AMI fija. Vacio = ultima Ubuntu 22.04 LTS de Canonical. Fijarla despues del primer despliegue para que v1 sea reproducible."
  type        = string
  default     = ""
}

# ---------- Parametros especificos de Azure ----------

variable "azure_location" {
  description = "Ubicacion autorizada de Azure."
  type        = string
  default     = "eastus"
}

variable "azure_vm_size" {
  description = "Tamano de la VM Linux."
  type        = string
  default     = "Standard_B1s"
}

variable "azure_admin_username" {
  description = "Usuario administrativo que exige la plataforma (no se abre SSH)."
  type        = string
  default     = "nexoadmin"
}

variable "azure_admin_ssh_public_key" {
  description = "Clave PUBLICA SSH exigida por Azure. Se entrega como secreto del pipeline; la privada nunca sale del PC del alumno."
  type        = string
}
