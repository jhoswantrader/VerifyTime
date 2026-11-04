# Despliegue de VerifyTime en Vercel

El repositorio contiene actualmente un sitio estático cuyo punto de entrada es `index.html` en la raíz. Puede desplegarse como sitio estático en Vercel sin convertirlo todavía en una aplicación Next.js.

## Importar el proyecto

1. En Vercel, crea un proyecto nuevo e importa `jhoswantrader/VerifyTime`.
2. Selecciona la rama `feature/automatic-membership-verification` para la primera vista previa.
3. Deja **Root Directory** en `./`.
4. No configures Build Command ni Output Directory para este HTML estático, salvo que Vercel solicite explícitamente una configuración.
5. Despliega como Preview. No cambies el dominio de producción hasta revisar la vista previa.

## Variables de entorno

El sitio público no debe contener secretos. No agregues la clave `service_role`, credenciales BDV ni cookies de sesión a variables expuestas al navegador (`NEXT_PUBLIC_*`) ni al HTML.

Cuando se construya el Panel Maestro, las operaciones privilegiadas deben pasar por backend seguro. El navegador solo debe recibir la sesión del usuario y datos permitidos por RLS.

## Estado

Esta guía prepara el despliegue del sitio actual. El Panel Maestro y la conexión al flujo automático de pagos todavía requieren implementación y pruebas; no están activados por este archivo.
