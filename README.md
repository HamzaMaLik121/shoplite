# ShopLite

A tiny online shop split into five containers. The application is deliberately
minimal; the real work in this project is the Docker / AWS / CI side.

| Service   | Folder               | Stack                  | Port | Table      | Endpoints                                                     |
|-----------|----------------------|------------------------|------|------------|---------------------------------------------------------------|
| frontend  | `frontend/`          | React (Vite)           | 80   | –          | UI; calls `/api/<service>/...`                                |
| catalog   | `catalog-service/`   | Node.js + Express      | 3000 | `products` | `GET /health`, `GET /products`, `GET /products/:id`, `POST /products` |
| inventory | `inventory-service/` | Go, `net/http`         | 8081 | `stock`    | `GET /health`, `GET /stock/:productId`, `POST /stock/reserve` |
| orders    | `order-service/`     | Java 21, Spring Boot   | 8082 | `orders`   | `GET /health`, `GET /orders`, `POST /orders`                  |
| postgres  | –                    | `postgres:17-alpine`   | 5432 | all three  | –                                                             |

`POST /orders {"productId":1,"quantity":2}` → orders asks catalog for the price
(unknown product → `400`), asks inventory to reserve stock (not enough → `409`),
then saves the order with `total = price × quantity` and returns `201`.

## Configuration

Every value comes from the environment; see [`.env.example`](.env.example).
Copy it to `.env` (git-ignored) and set real values.

## Running without Docker (for app development only)

Needs Postgres, Node 22+, Go 1.26, Java 21 + Maven.

```bash
# 1. database
createdb shopdb && psql -d shopdb -f db/init.sql

# 2. backends (each in its own terminal, with DB_* exported)
cd catalog-service && npm install && npm start            # :3000
cd inventory-service && go run .                           # :8081
cd order-service && mvn spring-boot:run                    # :8082

# 3. frontend: Vite proxies /api/* to the backends like nginx will
cd frontend && npm install && npm run dev                  # :5173
```

The inventory binary also supports `inventory-service -healthcheck`, which
calls its own `/health` and exits 0/1, for use in a distroless `HEALTHCHECK`.

## Running with Docker (Phase 1)

### Build the images

```bash
docker build -t shop-frontend:1.0.0  frontend
docker build -t shop-catalog:1.0.0   catalog-service
docker build -t shop-inventory:1.0.0 inventory-service
docker build -t shop-orders:1.0.0    order-service
```

Sizes and budgets (the DISK USAGE column of `docker images`):

| Image | Size | Budget |
|---|---|---|
| `shop-frontend` | 21.8 MB | 60 MB |
| `shop-catalog` | 190 MB | 200 MB |
| `shop-inventory` | 21.3 MB | 30 MB |
| `shop-orders` | 165 MB | 300 MB |

All four pass `hadolint`. The only rule ignored is `DL3018` (pin `apk` package
versions): Alpine repositories keep only current versions, so pinning package
versions makes builds break as soon as Alpine updates. The base image tag is the
pin instead. Each ignore is marked in the Dockerfile with that reason.

### Start and stop

```bash
cp .env.example .env          # once; .env is git-ignored
./scripts/up.sh               # TAG=1.0.0 by default
TAG=1.1.0 ./scripts/up.sh     # any tag built earlier
./scripts/down.sh             # keeps the pgdata volume
./scripts/down.sh --purge     # deletes the data too
```

`up.sh` builds any `shop-*` image that is missing before it starts anything, so
a fresh clone only needs `./scripts/up.sh`. To pull the images from a registry
instead of building them (once they are pushed to ECR):

```bash
REGISTRY=123456789012.dkr.ecr.eu-west-1.amazonaws.com ./scripts/up.sh
```

If anything fails to start, the containers that run created are removed again,
so the host is never left half-up.

On a cloud VM the script asks the instance metadata service for the public IP
and adds it to nginx's `server_name`, so `http://<public-ip>` serves the app as
well as `http://shoplite.test`. The port still has to be open in the security
group.
```

Add the name to `/etc/hosts` once:

```
127.0.0.1 shoplite.test
```

Then open <http://shoplite.test>.

`up.sh` creates the networks and volume if missing, replaces containers that
already exist, and waits for each tier to report healthy (Postgres, then the
backends, then the frontend) before starting the next. On failure it prints the
last 20 log lines and exits non-zero.

### Network layout

```
              browser
                 |  :80 (only published port)
           [ frontend ]  frontend-net
            /    |    \
      catalog inventory orders   both networks
            \    |    /
             backend-net (internal)
                   |
              [ postgres ]   no internet, no host port
```

Container names are the DNS names: `postgres`, `catalog`, `inventory`, `orders`,
`frontend`. `frontend/nginx.conf` proxies `/api/<service>/*` over
`frontend-net`, strips the prefix, and closes any other Host header with `444`.

All ten Phase 1 checks and their output are in
[`docs/evidence/phase1-tests.md`](docs/evidence/phase1-tests.md).

## TODO (the rest of the project)

- [ ] `scripts/push.sh`, `scripts/deploy.sh`
- [ ] `.github/workflows/ci.yml`, `deploy.yml`
- [ ] `docs/evidence/phase2.md`

## Smoke test variable

The deploy job calls `/api/catalog/health` at the address in the repository variable
`APP_DOMAIN` (GitHub: Settings -> Secrets and variables -> Actions -> Variables).
Set it without `http://`, for example `100.27.40.157`. It must match `SERVER_NAME`
in `/opt/shoplite/.env` on the VM, because nginx closes requests with any other Host.
