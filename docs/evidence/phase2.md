# Phase 2 — AWS Deployment Evidence

## Deployment Information

| Item | Value |
|---|---|
| AWS Region | `us-east-1` |
| ECR Repository | `shoplite` |
| EC2 Instance ID | `i-08e9a71800df88eea` |
| Deployment Directory | `/opt/shoplite` |
| Public EC2 IP | `100.27.40.157` |
| Application Port | `80` |

## 1. GitHub Actions OIDC Authentication

GitHub Actions successfully assumed the AWS IAM deployment role.

- OIDC provider: `token.actions.githubusercontent.com`
- IAM role: `shoplite-github-deploy`
- AWS authentication: successful
- ECR login: successful

## 2. Docker Image Deployment

Application images are stored in Amazon ECR.

Repository:

```text
418059030300.dkr.ecr.us-east-1.amazonaws.com/shoplite
```

Images use service-prefixed Git SHA tags, for example:

```text
shoplite:frontend-<commit-sha>
shoplite:catalog-<commit-sha>
shoplite:inventory-<commit-sha>
shoplite:orders-<commit-sha>
```

The EC2 instance uses its IAM role to authenticate and pull images from ECR.

## 3. Container Health Verification

Command:

```bash
docker ps
```

Observed containers:

- frontend
- catalog
- inventory
- orders
- postgres

Frontend health:

```bash
docker inspect frontend \
  --format 'Frontend health: {{.State.Health.Status}}'
```

Observed result:

```text
Frontend health: healthy
```

## 4. Nginx Configuration Verification

Command:

```bash
docker exec frontend nginx -t
```

Observed result:

```text
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

Note: Nginx runs inside the frontend Docker container. The host-level `systemctl status nginx` showing inactive is expected and does not indicate that the container's Nginx is stopped.

## 5. Reverse Proxy Health Tests

Commands:

```bash
curl -i -H 'Host: shoplite.test' \
http://127.0.0.1/health

curl -i -H 'Host: shoplite.test' \
http://127.0.0.1/api/catalog/health

curl -i -H 'Host: shoplite.test' \
http://127.0.0.1/api/inventory/health

curl -i -H 'Host: shoplite.test' \
http://127.0.0.1/api/orders/health
```

Observed results:

| Endpoint | HTTP Status | Response |
|---|---|---|
| `/health` | 200 OK | `ok` |
| `/api/catalog/health` | 200 OK | `{"status":"ok"}` |
| `/api/inventory/health` | 200 OK | `{"status":"ok"}` |
| `/api/orders/health` | 200 | `{"status":"ok"}` |

Frontend page test:

```bash
curl -I -H 'Host: shoplite.test' http://127.0.0.1/
```

Observed result:

```text
HTTP/1.1 200 OK
Content-Type: text/html
```

## 6. Docker Network Verification

Command:

```bash
for c in frontend catalog inventory orders postgres; do
  docker inspect "$c" \
    --format '{{.Name}} -> {{range $n, $v := .NetworkSettings.Networks}}{{$n}} {{end}}'
done
```

Observed network membership:

```text
/frontend -> frontend-net
/catalog -> backend-net frontend-net
/inventory -> backend-net frontend-net
/orders -> backend-net frontend-net
/postgres -> backend-net
```

Internal network verification:

```bash
docker network inspect backend-net \
  --format 'Internal={{.Internal}}'
```

Observed result:

```text
Internal=true
```

## 7. Published Port Verification

Command:

```bash
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

Observed result:

```text
NAMES       PORTS
frontend    0.0.0.0:80->80/tcp, [::]:80->80/tcp
orders      8082/tcp
inventory   8081/tcp
catalog     3000/tcp
postgres    5432/tcp
```

Only the frontend publishes a host port. Backend and database ports are not published to the host.

## 8. Evidence Still to Attach

The following items should be captured before final submission:

- [ ] Screenshot of ECR repositories and image tags.
- [ ] Screenshot of ECR image scan results.
- [ ] Screenshot of successful GitHub Actions CI run.
- [ ] Screenshot of successful GitHub Actions deployment run.
- [ ] Browser screenshot of the application through the intended public hostname.
- [ ] EC2 listening-port output using `sudo ss -tlnp`.
- [ ] Phase 1 network isolation and database persistence test evidence.
- [ ] Database backup and restore evidence, if required by the grading checklist.

## 9. Notes and Limitations

- The locally tested hostname was `shoplite.test`, supplied using the HTTP Host header.
- Public access through a real DNS domain has not yet been verified.
- Network membership and internal-network status have been verified. A separate outbound internet-isolation test for PostgreSQL/backend networking should still be recorded.
- The project currently uses one ECR repository with service-prefixed image tags. The assignment's suggested layout uses four separate repositories. Confirm this deviation is acceptable to the instructor.
- The selected AWS region is `us-east-1`.

---

**Status:** EC2 deployment, container health, Nginx reverse proxy, backend routing, Docker network membership, internal network setting, and host port exposure have been verified.
