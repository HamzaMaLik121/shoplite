# ShopLite — Multi-Service DevOps Project

A containerized multi-service application deployed on AWS EC2 using Docker, Amazon ECR, GitHub Actions, and Nginx reverse proxy.

## Architecture

ShopLite consists of five containers:

| Container | Technology | Purpose |
|---|---|---|
| Frontend | React / Nginx | Web application and reverse proxy |
| Catalog | Node.js | Catalog API |
| Inventory | Go | Inventory API |
| Orders | Java / Spring Boot | Orders API |
| PostgreSQL | PostgreSQL 17 | Database |

### Docker Network Architecture

```text
                    Browser
                       |
                    Port 80
                       |
                +--------------+
                |   Frontend   |
                |     Nginx    |
                +--------------+
                       |
                 frontend-net
                /      |       \
           Catalog  Inventory  Orders
                \      |       /
                 backend-net
                   (internal)
                       |
                  PostgreSQL
```

- Frontend connects only to `frontend-net`.
- Catalog, Inventory, and Orders connect to both networks.
- PostgreSQL connects only to `backend-net`.
- `backend-net` is an internal Docker network.
- Only the frontend publishes a host port: `80`.
- PostgreSQL uses persistent Docker volume storage.

## Technology Stack

- Docker and Docker Compose
- AWS EC2
- Amazon Elastic Container Registry (ECR)
- GitHub Actions
- GitHub Actions OIDC authentication
- Nginx reverse proxy
- Node.js, Go, Java, React
- PostgreSQL
- Trivy image scanning

## AWS Deployment

| Setting | Value |
|---|---|
| AWS Region | `us-east-1` |
| ECR Repository | `shoplite` |
| EC2 Operating System | Ubuntu |
| Deployment Directory | `/opt/shoplite` |
| Application Port | `80` |

Images are stored in Amazon ECR and deployed to EC2 using GitHub Actions.

GitHub Actions authenticates to AWS through OIDC rather than storing long-lived AWS access keys in GitHub secrets.

Images are tagged using Git commit SHA values to support traceable deployments.

## Reverse Proxy Routes

Nginx routes incoming requests to the appropriate backend service.

| Route | Backend |
|---|---|
| `/api/catalog/` | `catalog:3000` |
| `/api/inventory/` | `inventory:8081` |
| `/api/orders/` | `orders:8082` |
| `/health` | Frontend health check |

## Health Checks

The following endpoints are available:

```text
/api/catalog/health
/api/inventory/health
/api/orders/health
/health
```

## Deployment Verification

The EC2 deployment has been tested.

| Verification | Result |
|---|---|
| Frontend container health | Healthy |
| Nginx configuration test | Passed |
| Frontend health endpoint | HTTP 200 |
| Catalog health endpoint | HTTP 200 |
| Inventory health endpoint | HTTP 200 |
| Orders health endpoint | HTTP 200 |
| Backend network isolation | Verified |
| PostgreSQL network placement | Verified |
| Only frontend host port published | Verified |

See [`docs/evidence/phase2.md`](docs/evidence/phase2.md) for deployment verification details.

## Repository Structure

```text
shoplite/
├── .github/
│   └── workflows/
│       ├── ci.yml
│       └── deploy.yml
├── frontend/
├── catalog-service/
├── inventory-service/
├── order-service/
├── db/
│   └── init.sql
├── scripts/
│   ├── up.sh
│   ├── down.sh
│   ├── push.sh
│   └── deploy.sh
├── docs/
│   └── evidence/
│       ├── phase1-tests.md
│       └── phase2.md
└── README.md
```

## Running Locally

Requirements:
- Docker
- Docker Compose

Start the application:

```bash
./scripts/up.sh
```

Stop the application:

```bash
./scripts/down.sh
```

## Security Notes

- Backend services are not directly published to host ports.
- PostgreSQL is isolated on an internal Docker network.
- GitHub Actions uses OIDC for AWS authentication.
- EC2 uses an IAM role to pull images from ECR.
- Application environment variables are kept outside the repository.

**Never commit `.env`, private SSH keys, AWS credentials, or other secrets.**

## Project Status

The application is deployed on AWS EC2. Frontend health, reverse proxy routing, backend health endpoints, and Docker network architecture have been verified.

Further evidence and remaining assignment checks are tracked in `docs/evidence/`.
