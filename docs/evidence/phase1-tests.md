# Phase 1 evidence — isolation tests

Environment: Docker 29.5.3 (Docker Desktop, macOS), images built with `TAG=1.0.0`.

The stack was started with `./scripts/up.sh`. Because adding `shoplite.test` to
`/etc/hosts` needs a password prompt on this machine, the curl commands below use
`--resolve shoplite.test:80:127.0.0.1`, which points the name at the same address
the hosts entry would. With the hosts entry in place, drop `--resolve` and the
commands are exactly as written in the brief.

```bash
R="--resolve shoplite.test:80:127.0.0.1"
```

## Test 1 — the app loads by name

```bash
curl -I $R http://shoplite.test
```

```
HTTP/1.1 200 OK
```

## Test 2 — APIs work through nginx

```bash
curl $R http://shoplite.test/api/catalog/products
```

```
[{"id":1,"name":"Keyboard","price":4500},{"id":2,"name":"Mouse","price":1800},{"id":3,"name":"Monitor","price":32000}]
```

## Test 3 — an order works end to end

```bash
curl -i -X POST $R http://shoplite.test/api/orders/orders \
  -H 'Content-Type: application/json' -d '{"productId":1,"quantity":2}'
curl $R http://shoplite.test/api/inventory/stock/1
```

```
HTTP/1.1 201
Server: nginx/1.27.5
Content-Type: application/json

{"id":1,"productId":1,"quantity":2,"total":9000.00,"createdAt":"2026-11-23T06:23:06.704143"}

{"productId":1,"quantity":18}
```

Stock for product 1 dropped from 20 to 18, as expected.

## Test 4 — backends aren't published

```bash
curl -m 2 localhost:3000
curl -m 2 localhost:8081
curl -m 2 localhost:8082
docker ps --format '{{.Names}} {{.Ports}}'
```

```
curl: (7) Failed to connect to localhost port 3000 after 0 ms: Couldn't connect to server
curl: (7) Failed to connect to localhost port 8081 after 0 ms: Couldn't connect to server
curl: (7) Failed to connect to localhost port 8082 after 0 ms: Couldn't connect to server

catalog 3000/tcp
frontend 0.0.0.0:80->80/tcp, [::]:80->80/tcp
inventory 8081/tcp
orders 8082/tcp
postgres 5432/tcp
```

Only `frontend` shows a host port.

## Test 5 — the frontend network can't see Postgres

```bash
docker run --rm --network frontend-net busybox \
  wget -T 3 -qO- http://postgres:5432
```

```
wget: bad address 'postgres:5432'
```

## Test 6 — backends reach each other on backend-net

```bash
docker run --rm --network backend-net busybox \
  wget -qO- http://catalog:3000/health
```

```
{"status":"ok"}
```

## Test 7 — Postgres has no internet

```bash
docker exec postgres wget -T 5 -qO- https://example.com
```

```
wget: bad address 'example.com'
exit=1
```

## Test 8 — data survives a restart

```bash
./scripts/down.sh
./scripts/up.sh
curl $R http://shoplite.test/api/orders/orders
```

```
Removing containers
Removing networks
Keeping pgdata volume (use --purge to delete it)
stack back up
[{"id":1,"productId":1,"quantity":2,"total":9000.00,"createdAt":"2026-11-23T06:23:06.704143"}]
```

The order from test 3 is still there.

## Test 9 — only --purge deletes data

```bash
./scripts/down.sh --purge
./scripts/up.sh
curl $R http://shoplite.test/api/orders/orders
curl $R http://shoplite.test/api/inventory/stock/1
```

```
Removing containers
Removing networks
Removing pgdata volume (all data will be lost)
stack back up
[]
{"productId":1,"quantity":20}
```

Order list is empty and stock is back to its seed value of 20.

## Test 10 — only the domain is served

```bash
curl -v http://127.0.0.1
curl -v -H 'Host: other.test' http://127.0.0.1
```

```
* Empty reply from server
* Closing connection
curl: (52) Empty reply from server
* Empty reply from server
* Closing connection
curl: (52) Empty reply from server
```

Both are closed with status 444 by nginx's default server block.

## Network membership

```
backend-net (internal=true):  catalog inventory orders postgres
frontend-net:                 catalog inventory orders frontend
```

Postgres is on `backend-net` only; the frontend is on `frontend-net` only; the
three backends bridge both. Full `docker network inspect frontend-net backend-net`
output is in [`network-inspect.txt`](network-inspect.txt).

## Image sizes

```bash
docker images --format '{{.Repository}}:{{.Tag}} {{.Size}}' | grep '^shop-'
```

```
shop-frontend:1.0.0   21.8MB   (budget 60MB)
shop-catalog:1.0.0     190MB   (budget 200MB)
shop-inventory:1.0.0  21.3MB   (budget 30MB)
shop-orders:1.0.0      165MB   (budget 300MB)
```

## hadolint

```bash
docker run --rm -i hadolint/hadolint:v2.12.0 hadolint - < frontend/Dockerfile
docker run --rm -i hadolint/hadolint:v2.12.0 hadolint - < catalog-service/Dockerfile
docker run --rm -i hadolint/hadolint:v2.12.0 hadolint - < inventory-service/Dockerfile
docker run --rm -i hadolint/hadolint:v2.12.0 hadolint - < order-service/Dockerfile
```

All four are clean. `DL3018` (unpinned `apk add`) is ignored on purpose inside
the Dockerfiles, with the reason in a comment and in the README.
