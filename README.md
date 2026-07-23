# 5etools Docker

Clones [5etools-src](https://github.com/5etools-mirror-3/5etools-src) and [5etools-img](https://github.com/5etools-mirror-3/5etools-img) (into `5etools-src/img/`), then serves the site with nginx.

The web UI starts immediately. While repos are cloning or updating, missing pages show a loading screen that auto-refreshes when the site is ready. Source is served as soon as it finishes; images keep downloading in the background.

## Quick start

```bash
docker compose up -d --build
```

Open right away:

http://localhost:11014/

First start still takes a while for the image repo (large). The loading page reports progress via `/status.json`.

## Layout inside the container

```
/data/5etools-src/          # source clone (web root)
/data/5etools-src/img/      # image clone
```

Data is stored in the `5etools-data` Docker volume so restarts do not re-download everything.

## Config

| Variable | Default | Description |
|---|---|---|
| `AUTO_PULL_INTERVAL` | `3600` | Seconds between `git pull`s. `0` disables. |
| `SRC_REPO` | 5etools-src URL | Source repository |
| `IMG_REPO` | 5etools-img URL | Image repository |
| Port mapping | `8080:80` | Change left side in `docker-compose.yml` |

## Useful commands

```bash
# Follow logs (clone progress)
docker compose logs -f

# Force rebuild / recreate
docker compose up -d --build --force-recreate

# Stop
docker compose down

# Stop and delete downloaded data
docker compose down -v
```
