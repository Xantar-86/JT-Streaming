# JT-Streaming web: build-context

Deze map is de Docker-build-context voor de webversie van JT-Streaming (gebaseerd op Fladder van
DonutWare, GPL-3.0). Hij wordt gemaakt door `pwsh tool/jt/build-web.ps1` en bevat:

| Pad | Inhoud |
|---|---|
| `build/web/` | De gebouwde Flutter-webapp (met `LICENSE.txt` en `jt-buildinfo.json`) |
| `Dockerfile` | Het **ongewijzigde** upstream-Dockerfile van Fladder (nginx:alpine) |
| `docker-entrypoint.sh` | Het **ongewijzigde** upstream-entrypoint (LF-regeleinden) |
| `LICENSE` | GPL-3.0 |
| `BUILDINFO.txt` | Versie, commit, Flutter-versie, bouwdatum |

## Image bouwen

```sh
mkdir -p /tmp/jt && tar -xf jt-streaming-web-<versie>.tar -C /tmp/jt && cd /tmp/jt
docker build -t jt-streaming:<versie> -t jt-streaming:latest \
  --label org.opencontainers.image.title=JT-Streaming \
  --label org.opencontainers.image.licenses=GPL-3.0 .
```

Controleer eerst de tar met het meegeleverde `.sha256`-bestand (`sha256sum -c`).

## Container

Dezelfde omgevingsvariabelen als het officiële Fladder-image:

| Variabele | Betekenis | Voorbeeld |
|---|---|---|
| `BASE_URL` | Jellyfin-server | `https://tv.fam-thoelen.be` |
| `FLADDER_WEBPATH` | Pad waaronder de app draait | `/fladder/` |
| `SEERR_BASE_URL` | Optioneel, Seerr | leeg |

Na de start toont `<webpath>/jt-buildinfo.json` welke versie draait.
