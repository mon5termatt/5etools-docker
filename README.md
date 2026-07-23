# 5etools Docker

Follows the [5eTools Node.js install guide](https://wiki.tercept.net/en/5eTools/InstallGuide):

1. Clone [5etools-src](https://github.com/5etools-mirror-3/5etools-src) and [5etools-img](https://github.com/5etools-mirror-3/5etools-img) into `5etools-src/img/`
2. `npm i`
3. `npm run build:sw:prod` (on by default)
4. `npm run build:seo` (on by default)
5. `npm run serve:dev` (http-server on port 5050)

nginx listens on port 80, shows a loading page until the Node server is up, then proxies to it.

## Quick start

```bash
docker compose up -d --build
```

A default `.env` ships in the repo (required by some stack UIs). On first container start, the same defaults are also written to `/data/.env` in the volume — edit that file and restart to change `BUILD_SW` / `BUILD_SEO` / `AUTO_PULL_INTERVAL` without rebuilding.

Open:

http://localhost:11014/

The UI is available as soon as source + `npm i` finish; images keep downloading in the background. Progress is exposed at `/status.json`, and a small overlay is injected into HTML pages while sync/build is busy.

## Layout

```
/data/5etools-src/          # source clone + node_modules
/data/5etools-src/img/      # image clone
```

Persisted in the `5etools-data` volume.

## Config (`.env`)

| Variable | Default | Description |
|---|---|---|
| `AUTO_PULL_INTERVAL` | `3600` | Seconds between git pulls + rebuild. `0` disables. |
| `BUILD_SW` | `true` | Run `npm run build:sw:prod`. Set `false` to skip. |
| `BUILD_SEO` | `true` | Run `npm run build:seo`. Set `false` to skip. |
| `SRC_REPO` / `IMG_REPO` | mirror-3 URLs | Override clone sources |
| Port mapping | `11014:80` | Change left side in `docker-compose.yml` |

## Useful commands

```bash
docker compose logs -f
docker compose up -d --build --force-recreate
docker compose down
docker compose down -v   # also delete downloaded data
```
