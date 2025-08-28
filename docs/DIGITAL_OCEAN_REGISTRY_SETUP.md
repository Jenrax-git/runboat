# Configuración de Digital Ocean Container Registry con GitHub Actions

Este documento explica cómo configurar la automatización de builds de Docker para subir imágenes al Container Registry de Digital Ocean.

## Prerrequisitos

1. Una cuenta de Digital Ocean
2. Un repositorio en GitHub (fork del repositorio original)
3. Acceso a los secrets del repositorio
4. Trabajar en la rama `main-jenrax` para mantener el fork separado

## Paso 1: Crear Container Registry en Digital Ocean

1. Ve a [Digital Ocean Container Registry](https://cloud.digitalocean.com/registry)
2. Haz clic en "Create Registry"
3. Elige una región cercana a tu ubicación
4. Dale un nombre al registry (ej: `jenrax-registry`)
5. Selecciona el plan que necesites
6. Haz clic en "Create Registry"

## Paso 2: Crear Access Token en Digital Ocean

1. Ve a [Digital Ocean API Tokens](https://cloud.digitalocean.com/account/api/tokens)
2. Haz clic en "Generate New Token"
3. Dale un nombre descriptivo (ej: "GitHub Actions Registry Access")
4. Asegúrate de que tenga permisos de escritura
5. Copia el token generado (lo necesitarás en el siguiente paso)

## Paso 3: Configurar Secrets en GitHub

En tu repositorio de GitHub, ve a **Settings > Secrets and variables > Actions** y agrega los siguientes secrets:

### `DO_ACCESS_TOKEN`
El token de acceso que creaste en Digital Ocean.

### `DO_REGISTRY_NAME`
El nombre de tu registry (sin el dominio). Por ejemplo, si tu registry se llama `jenrax-registry`, este valor sería `jenrax-registry`.

## Paso 4: Configurar el Workflow

Ya tienes un workflow configurado (`docker-build-do.yml`) que incluye:

- Manejo automático de tags
- Cache de builds para mayor velocidad
- Soporte para versiones semánticas
- Configuración avanzada y flexible

## Paso 5: Activar el Workflow

1. Haz commit y push de los archivos de workflow a tu repositorio
2. El workflow se ejecutará automáticamente en:
   - Push a la rama `main-jenrax`
   - Pull requests a `main-jenrax`
   - Tags que empiecen con `v`

## Uso de las Imágenes

Una vez que el workflow esté funcionando, podrás usar las imágenes en Kubernetes así:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: runboat-app
spec:
  template:
    spec:
      containers:
      - name: runboat-app
        image: registry.digitalocean.com/jenrax-registry/runboat-app:latest
        # o usar un tag específico:
        # image: registry.digitalocean.com/jenrax-registry/runboat-app:abc123def
```

## Troubleshooting

### Error de autenticación
- Verifica que el `DO_ACCESS_TOKEN` sea correcto
- Asegúrate de que el token tenga permisos de escritura

### Error de registry no encontrado
- Verifica que el `DO_REGISTRY_NAME` sea correcto
- Confirma que el registry existe en Digital Ocean

### Build falla
- Revisa los logs del workflow en GitHub Actions
- Verifica que el Dockerfile sea válido

## Comandos útiles

Para hacer pull de una imagen localmente:
```bash
docker pull registry.digitalocean.com/jenrax-registry/runboat-app:latest
```

Para listar las imágenes en tu registry:
```bash
doctl registry repository list
```

## Costos

- Digital Ocean Container Registry tiene un costo mensual basado en el almacenamiento
- Los builds en GitHub Actions son gratuitos para repositorios públicos
- Para repositorios privados, GitHub Actions tiene límites mensuales gratuitos
