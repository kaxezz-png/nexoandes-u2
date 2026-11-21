# NexoAndes U2 · Portal Operacional en AWS y Azure

Evaluación Sumativa U2 · Automatización de Infraestructura con IaC (IC106TICL)
Alumno: a007 · Curso: c50 (por confirmar) · X = 7 · Docente: Emanuel Ypsent López Adaro

Infraestructura reproducible con Terraform que despliega el Portal Operacional en **AWS** (ALB + grupo EC2) y en **Azure** (VM Linux), y que en AWS ejecuta una **actualización inmutable v1 → v2** y una **recuperación** mediante Instance Refresh, todo desde un pipeline de GitHub Actions.

## 1. Estructura

```text
.
├── main.tf               # orquestación: compone los módulos AWS y Azure
├── versions.tf           # Terraform >= 1.10, providers aws ~> 5.80 y azurerm ~> 4.14, backend S3
├── providers.tf          # un provider por nube, sin alias; credenciales por entorno
├── variables.tf          # parámetros comunes (X, curso, build, versión) y específicos
├── outputs.tf            # salidas por contexto: identidad, aws, azure
├── u2.auto.tfvars        # identidad U2 y versión del Portal (versionado, sin secretos)
├── templates/
│   ├── user_data_u2.sh.tpl        # artefacto docente (sin modificar, LF)
│   └── README_ESTUDIANTE_U2.md    # guía docente del artefacto
├── modules/
│   ├── portal_aws/       # VPC, subredes A/B, IGW, SG, ALB, Launch Template, ASG
│   └── portal_azure/     # RG, VNet, subred, NSG, IP pública, NIC, VM Linux
├── scripts/
│   ├── observar_http.sh       # muestra /api/check cada 2 s, timeout 5 s, sin reintentos
│   ├── observar_capacidad.sh  # grupos EC2 y destinos cada 20 s
│   ├── analizar_ventana.sh    # apoyo: cobertura, brechas y fallos de la ventana
│   └── esperar_refresh.sh     # pipeline: comprueba la estabilización en el proveedor
├── docs/plan_cambio.md   # plan previo del cambio y de la recuperación (E04)
├── evidencias/           # registros de observación (revisados, sin secretos)
└── .github/workflows/u2-infra.yml
```

## 2. Convención U2 aplicada (X = 7)

| Elemento | AWS | Azure |
|---|---|---|
| Red | VPC `10.7.0.0/16` | VNet `172.20.7.0/24` |
| Subredes | A `10.7.10.0/24`, B `10.7.20.0/24` (zonas distintas) | `172.20.7.0/26` |
| Entrada | ALB HTTP 80 → target group → grupo EC2 | IP pública → NIC → VM |
| Cómputo | Launch Template + ASG, capacidad fija 2 | VM `Standard_B1s`, Ubuntu 22.04 |
| Portal | v1 → v2 → v1 (recuperación) | v1 |
| Nombres | `na-u2-c50-a007-*` | `na-u2-c50-a007-az-*` |

Tags en todos los recursos que los admiten: `proyecto=NexoAndes`, `fase=U2`, `alumno=a007`, `curso=c50`, `proveedor=aws|azure`. En AWS se aplican con `default_tags`; las instancias reciben además `portal_version` y `build_ref`.

## 3. Decisiones técnicas

- **Orquestación:** un root module con dos módulos hijos, uno por proveedor. Los parámetros comunes (identidad, build, versión) se resuelven una vez en `locals`; los específicos viven en cada módulo.
- **Contextos y credenciales:** el pipeline de GitHub Actions corre en un **runner autoalojado** (el PC del alumno). AWS usa el perfil local con las credenciales temporales del Learner Lab y Azure la sesión de Azure CLI (`az login`) del alumno. Motivo: el tenant de Azure del instituto no permite registrar service principals (`Insufficient privileges`), por lo que no es posible autenticar un runner alojado por GitHub. No hay credenciales de nube en GitHub ni en el código.
- **State:** un único state remoto en S3 con bloqueo nativo (`use_lockfile`), fuera de Git. Se comparte porque las dos nubes se despliegan y verifican juntas desde el mismo pipeline. Si un apply de una nube fallara, el state conserva lo que sí se creó.
- **build_ref:** el pipeline entrega los 12 primeros caracteres del SHA del commit. En Azure, `custom_data` se ignora después de crear la VM (`ignore_changes`), porque la VM se mantiene en v1 y un commit nuevo no debe reemplazarla.
- **Health check del ALB:** `/api/check`, que responde 200 solo si la comprobación funcional pasa (metadata real e identificación del recurso). `/health` solo prueba que el proceso está vivo.
- **Actualización:** blue-green por grupo EC2 con `create_before_destroy`: cada versión del Launch Template crea un grupo nuevo en el mismo target group; Terraform espera 2 destinos sanos y luego destruye el grupo anterior. Se descartó Instance Refresh porque la política del Learner Lab niega `autoscaling:StartInstanceRefresh`. Detalle en `docs/plan_cambio.md`.
- **Seguridad:** sin SSH en ninguna nube; IMDSv2 obligatorio en AWS; las EC2 solo aceptan tráfico desde el SG del ALB. Azure exige una clave pública administrativa, que se entrega como secreto; la clave privada nunca sale del PC del alumno.

## 4. Preparación (una vez)

1. Bucket S3 para el state, con versionado y sin acceso público: `na-u2-c50-a007-tfstate-7391`.
2. Clave SSH que exige Azure: `ssh-keygen -t ed25519 -f ~/.ssh/nexoandes_u2` (solo se usa la `.pub`; la privada no sale del PC).
3. En GitHub → *Settings → Secrets and variables → Actions → Variables*: `ARM_SUBSCRIPTION_ID` y `TF_STATE_BUCKET` (no son secretos).
4. En *Settings → Environments*: `u2-aprobacion` con *Required reviewers*. Es el gate de autorización del plan.
5. En *Settings → Actions → Runners*: registrar el runner autoalojado de Windows y ejecutarlo con `run.cmd` en la sesión del alumno.
6. Antes de cada sesión: credenciales nuevas del Learner Lab en `~/.aws/credentials` y `az login` vigente.

## 5. Ejecución

| Paso | Cambio en el repo | Pipeline | Evidencia |
|---|---|---|---|
| Despliegue v1 | `app_version = "v1"` | `apply` | E03 |
| Plan posterior | ninguno | `plan` → "No changes" | E03 |
| Actualización | PR con `app_version = "v2"` | `apply` + observación | E05, E06 |
| Recuperación | PR con `app_version = "v1"` | `apply` + observación | E07 |
| Plan posterior | ninguno | `plan` → "No changes" | E07 |
| Limpieza | ninguno | `destroy` | E08 |

Durante la actualización y la recuperación, en dos terminales (Git Bash):

```bash
scripts/observar_http.sh http://<DNS-del-ALB> evidencias/http_v1_a_v2.csv
scripts/observar_capacidad.sh <ARN-target-group> evidencias/capacidad_v1_a_v2
```

Arráncalos 60 s antes de aprobar el apply y detenlos 120 s después de que el job de verificación confirme la estabilización. Luego:

```bash
scripts/analizar_ventana.sh evidencias/http_v1_a_v2.csv <inicio_utc> <estabilizacion_utc> v2 v1,v2 a007 c50
```

## 6. Verificación manual de un Portal

```bash
ENDPOINT="http://<endpoint-real>"
curl -sS --max-time 5 -w '\nHTTP %{http_code}\n' "$ENDPOINT/api/check"
```

En PowerShell usa `curl.exe`. Contrasta siempre tres fuentes: outputs de Terraform, consulta al proveedor y respuesta HTTP.

## 7. Uso de IA

Se utilizó Claude (Anthropic) para orientar la estructura del código Terraform, del pipeline y de los scripts de observación, y para redactar borradores de documentación. Todas las ejecuciones, evidencias y decisiones fueron realizadas y revisadas por el alumno. *(Ajusta este texto a lo que realmente usaste.)*

## 8. Referencias

- AWS. *Instance refresh*. https://docs.aws.amazon.com/autoscaling/ec2/userguide/instance-refresh-overview.html
- AWS. *User data*. https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html
- AWS. *IMDSv2*. https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-service.html
- Microsoft. *Azure Instance Metadata Service*. https://learn.microsoft.com/azure/virtual-machines/instance-metadata-service
- HashiCorp. *aws_autoscaling_group*. https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group
- HashiCorp. *azurerm_linux_virtual_machine*. https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine
- HashiCorp. *S3 backend*. https://developer.hashicorp.com/terraform/language/backend/s3
