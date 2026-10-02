# LivePulse — sitio de descargas

Esta carpeta es el sitio completo. GitHub guarda los archivos y Netlify
gratis los publica. No subas el proyecto LivePulse entero: trae el código,
perfiles del navegador y carpetas que no son la página.

El mapa corto de cada botón está en `LEEME.txt`. El detalle de cada archivo
está en la carpeta donde vive ese archivo.

## Qué archivo baja cada botón

| Botón | Archivo en este sitio | Campo de `enlaces.json` |
| --- | --- | --- |
| Descargar para Windows | `descargas/windows/LivePulse-Setup.exe` | `windows.archivo` |
| Versión portable | `descargas/windows/LivePulse-Portable.exe` | `windowsPortable.archivo` |
| Descargar APK | `descargas/android/LivePulse.apk` | `android.archivo` |

`sitio.js` lee `enlaces.json`. Si `url` está vacío, arma la ruta
`carpeta + archivo`. `index.html` repite esas mismas rutas por si el
navegador no ejecuta JavaScript. Conserva el nombre del archivo y no
tendrás que tocar ni el HTML ni el JSON.

El número que se ve en la página es `version` dentro de `enlaces.json`.

## 1. Subir a GitHub

Hace falta [Git para Windows](https://git-scm.com/download/win).
No uses el botón **Add file** de la web de GitHub: corta en 25 MB y el
instalador pesa unos 87 MB.

1. Entra a [github.com/new](https://github.com/new).
2. Pon un nombre, por ejemplo `livepulse-web`. Puede ser público.
3. No marques “Add a README”. Esta carpeta ya tiene el suyo.
4. Crea el repositorio vacío.
5. Abre PowerShell **dentro de esta carpeta `sitio`** (no en la carpeta LivePulse) y pega, cambiando la URL por la de tu repo:

```powershell
git init
git add .
git commit -m "Sitio de descargas LivePulse"
git branch -M main
git remote add origin https://github.com/TU-USUARIO/livepulse-web.git
git push -u origin main
```

GitHub avisa desde 50 MB y rechaza un archivo desde 100 MB. El instalador
de la 1.0.0 pesa unos 87 MB, así que entra. El push tarda unos minutos.

No actives Git LFS en este repositorio. Netlify gratis no entrega bien
esos archivos: la descarga bajaría un texto corto en lugar del programa.
Si un exe futuro pasa de 100 MB, el `LEEME.txt` de `descargas/windows`
explica cómo usar un Release de GitHub y pegar el `https://` en `url`.

## 2. Publicar en Netlify gratis

1. Entra a [app.netlify.com](https://app.netlify.com) y regístrate con GitHub.
2. **Add new site** → **Import an existing project** → GitHub → elige el repo.
3. Build command: déjalo vacío. Este sitio no se compila.
4. Publish directory: `.`
5. **Deploy**.

La dirección queda en `algo.netlify.app`. En **Site configuration** →
**Domain management** → **Options** → **Edit site name** puedes cambiar
la palabra `algo`.

`netlify.toml` ya dice que la carpeta publicada es esta, y que el exe y
el apk se descargan en lugar de abrirse en el navegador.

Si en vez de un repo solo con este sitio conectas el repo de todo LivePulse,
en Netlify pon **Base directory** en `sitio` y **Publish directory** en `.`.
No publiques la raíz de LivePulse.

## 3. Probar en tu PC antes de subir

En PowerShell, dentro de `sitio`:

```powershell
python -m http.server 5500
```

Abre `http://localhost:5500`. Los tres botones tienen que bajar el archivo
de su carpeta. Cierra el servidor con Ctrl+C.

Abrir `index.html` con doble clic también descarga, porque el `href` ya
apunta al archivo. El tamaño en megabytes y un cambio de `enlaces.json`
se ven cuando la página se abre desde un servidor o desde Netlify.

## 4. Cuando salga otra versión

1. Sustituye el archivo en su carpeta **con el mismo nombre**.
   Los comandos exactos están en `descargas/windows/LEEME.txt` y
   `descargas/android/LEEME.txt`.
2. Si quieres que la página diga otro número, cambia `version` en `enlaces.json`.
3. Desde esta carpeta: `git add`, `git commit`, `git push`.
4. Netlify publica solo. Prueba el botón y mira que el tamaño haya cambiado.

Para el logo y el icono de la pestaña, lee `img/LEEME.txt`.
