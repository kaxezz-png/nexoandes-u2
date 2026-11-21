# Datos de identificacion U2 (no son secretos: este archivo SI se versiona).
# build_ref NO va aqui: lo entrega el pipeline con el SHA del commit.
# azure_admin_ssh_public_key NO va aqui: lo entrega el pipeline como secreto.

x      = 7
course = "c50" # CONFIRMAR con el docente (el ejemplo de la guia usa c01)

# Version del Portal en AWS. Se cambia SOLO por commit + PR:
#   v1 -> despliegue inicial (E03)
#   v2 -> actualizacion inmutable (E05)
#   v1 -> recuperacion / reversion planificada (E07)
app_version = "v1"

aws_region     = "us-east-1"
azure_location = "brazilsouth"

# Despues del primer despliegue, copia aqui el AMI que muestra
# `terraform output aws` para que la version de retorno sea reproducible.
aws_ami_id = "ami-012cadcb0ec2f554f"
azure_vm_size  = "Standard_D2s_v4" # Standard_B1s sin capacidad en brazilsouth
