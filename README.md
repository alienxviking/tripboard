# TripBoard

**TripBoard** is a small trip planner (plan trips, track budgets, move them from *planned → booked → done*). The app itself is simple on purpose. The point of the project is everything around it: containers, CI/CD with security gates, Kubernetes + Helm, infrastructure as code, monitoring and GitOps, plus a troubleshooting challenge on the running system.

Snehangshu Roy. Started as the capstone of my DevOps course (it lived in [devops-homework](https://github.com/alienxviking/devops-homework) until it moved here with its history).

```
tripboard/
├── application/
│   ├── backend/            FastAPI + SQLAlchemy + Alembic, /metrics, JSON logs, 16 pytest tests
│   └── frontend/           React (Vite)
├── docker/                 backend + frontend Dockerfiles (multi-stage, non-root), nginx template, docker-compose.yml
├── kubernetes/             namespace with Pod Security "restricted"
├── helm/tripboard/         Helm chart: backend, frontend, postgres StatefulSet, ingress, HPA, probes, NetworkPolicy, ServiceMonitor, helm test
├── terraform/              kind or EKS cluster + cluster add-ons (Helm) + app bootstrap + AWS VPC/NAT/S3
├── .github/workflows/      ci.yml: the CI/CD pipeline
├── security/               bandit + gitleaks configs
├── monitoring/             kube-prometheus-stack values, Grafana dashboard, alert rules
├── gitops/                 Argo CD values, Argo CD Application, values-prod.yaml (updated by CI)
├── troubleshooting/        final troubleshooting challenge write-up
└── screenshots/
```

## Quickstart

Needs Docker only:

```bash
git clone https://github.com/alienxviking/tripboard.git && cd tripboard
docker compose -f docker/docker-compose.yml up --build -d
curl localhost:8000/health        # {"status":"ok","version":"dev"}
```

The app is on http://localhost:3000 (the API is proxied under `/api`) and the backend on http://localhost:8000. `docker compose -f docker/docker-compose.yml down -v` removes it again, database volume included.

Backend tests, the same commands CI runs:

```bash
cd application/backend
pip install -r requirements.txt -r requirements-dev.txt
flake8 . && pytest -v
```

The tests use an in-memory SQLite database, so they need no Postgres. The lock files are compiled for Linux (CI and the image use them), so on Windows run this in WSL or a `python:3.12` container.

## Configuration

Nothing has to be set to run it locally; [.env.example](.env.example) lists every variable with its default.

| Variable | Read by | Default | |
|---|---|---|---|
| `DATABASE_URL` | backend | `postgresql+psycopg://tripboard:tripboard@localhost:5432/tripboard` | SQLAlchemy URL; compose and the Helm chart set their own |
| `APP_VERSION` | backend | `dev` | the image build sets it to the commit SHA |
| `ENVIRONMENT` | backend | `local` | shown by `/api/info` |
| `APP_NAME` | backend | `TripBoard API` | |
| `LOG_LEVEL` | backend | `INFO` | JSON logs on stdout, one line per request (method, path, status, duration, request id); `DEBUG` adds the probe and scrape requests |
| `POSTGRES_PASSWORD` | docker compose | `tripboard-local` | local Postgres password |
| `BACKEND_URL` | frontend nginx | set by compose / Helm | where `/api` is proxied |

Python dependencies are pinned with pip-tools: edit `requirements.in` / `requirements-dev.in` and run `pip-compile` to update the `.txt` lock files. The frontend is pinned by `package-lock.json` (CI uses `npm ci`). Dependabot opens weekly update PRs for pip, npm, the Docker base images, Terraform providers and the GitHub Actions.

---

## Architecture

```mermaid
flowchart LR
    dev([Developer]) -->|git push| gh[(GitHub repo)]
    gh --> ci
    subgraph ci[GitHub Actions]
      direction TB
      t[Lint + pytest<br/>Frontend build] --> sec[SAST · SCA · Secret scan]
      sec --> img[Docker build x2<br/>Trivy scan = gate]
      img --> push[Push to GHCR<br/>tag = commit SHA]
      push --> kt[Deploy test<br/>kind + helm test]
      kt --> bump[Commit new tag to<br/>gitops/values-prod.yaml]
    end
    push --> ghcr[(GHCR images)]
    bump --> gh
    subgraph k8s[Kubernetes cluster - created by Terraform]
      argo[Argo CD] -->|helm template + apply| app
      subgraph app[namespace tripboard]
        ing[Ingress<br/>tripboard.local] -->|/| fe[frontend x2<br/>nginx]
        ing -->|/api| be[backend x2-5<br/>FastAPI + HPA]
        fe -->|/api| be
        be --> pg[(PostgreSQL<br/>StatefulSet + PVC)]
      end
      prom[Prometheus] -->|scrape /metrics| be
      graf[Grafana] --> prom
      am[Alertmanager] --- prom
    end
    argo -->|watch git| gh
    ghcr -->|pull| app
    tf[Terraform] -->|kind or EKS, helm add-ons,<br/>namespace + DB secret| k8s
    tf -->|VPC, subnets, NAT, S3| aws[(AWS / LocalStack)]
```

Request path: browser → ingress-nginx → `/` frontend (static React) or `/api` backend → PostgreSQL.

Delivery path: commit → pipeline (test, scan, build, scan, push) → pipeline commits the new image tag to git → Argo CD notices → rolling update.

## Technologies

| Area | Tools |
|---|---|
| Application | Python 3.12, FastAPI, SQLAlchemy 2, Alembic, PostgreSQL 16, React 19 + Vite |
| Testing | pytest + coverage (SQLite in-memory test DB), flake8 |
| Containers | Docker multi-stage builds, docker compose, nginx-unprivileged |
| CI/CD | GitHub Actions, GitHub Container Registry |
| DevSecOps | Bandit + Semgrep (SAST), pip-audit + npm audit (SCA), Gitleaks (secrets), Trivy (images), Pod Security "restricted", NetworkPolicy, non-root containers |
| Kubernetes | kind (v1.33) locally, **Amazon EKS 1.36** on AWS, ingress-nginx, metrics-server, HPA, probes, StatefulSet + PVC (EBS gp3 on EKS) |
| Packaging | Helm 3 |
| IaC | Terraform (kind, helm, kubernetes, aws, random providers), LocalStack locally, real AWS for EKS |
| Monitoring | kube-prometheus-stack (Prometheus, Alertmanager, Grafana), prometheus-fastapi-instrumentator |
| GitOps | Argo CD 3.5 (multi-source Application, auto-sync, prune, self-heal) |

---

## 1. Application

Backend endpoints:

| Method | Path | |
|---|---|---|
| GET | `/health` | liveness |
| GET | `/ready` | readiness (checks the DB) |
| GET | `/api/info` | app name, version (git SHA), environment |
| GET/POST | `/api/trips` | list / create |
| GET/PUT/DELETE | `/api/trips/{id}` | read / update / delete |
| GET | `/metrics` | Prometheus metrics (`http_requests_total`, `http_request_duration_seconds`, `tripboard_trips{status}`) |

- Schema is managed with **Alembic** ([0001_create_trips.py](application/backend/alembic/versions/0001_create_trips.py)). Migrations run at container start, and a Postgres **advisory lock** in `alembic/env.py` stops several backend pods from migrating at the same time.
- The entrypoint **waits for the database** before migrating, because on first deploy Postgres and the backend start together.
- Tests use an in-memory SQLite DB through a FastAPI dependency override, never the real database.

## 2. Docker

```bash
docker compose -f docker/docker-compose.yml up --build -d
# frontend http://localhost:3000, backend http://localhost:8000
```

- [backend.Dockerfile](docker/backend.Dockerfile): python:3.12-alpine, deps in a venv in a build stage, `apk upgrade`, runs as uid **10001**.
- [frontend.Dockerfile](docker/frontend.Dockerfile): Node 22 build stage → `nginx-unprivileged` (uid **101**, port 8080). [nginx.conf.template](docker/nginx.conf.template) proxies `/api` to the backend, resolving the name per request (so nginx starts even if the backend isn't there yet).

![compose up](screenshots/01-compose-up-build.png)
![compose ps](screenshots/02-compose-ps-logs.png)
![compose browser](screenshots/03-compose-browser.png)

## 3. Terraform infrastructure

[terraform/](terraform) provisions everything except the app itself:

| File | Creates |
|---|---|
| [cluster.tf](terraform/cluster.tf) | kind cluster: 1 control plane (ports 80/443 mapped for ingress) + 2 workers |
| [addons.tf](terraform/addons.tf) | Helm releases: ingress-nginx, metrics-server, kube-prometheus-stack, Argo CD |
| [app-bootstrap.tf](terraform/app-bootstrap.tf) | namespace `tripboard` (Pod Security restricted) + `tripboard-db` secret with a **random password** (never in git) |
| [aws-network.tf](terraform/aws-network.tf) | VPC 10.30.0.0/16, **2 public + 2 private subnets** in 2 AZs, IGW, NAT gateway, route tables, S3 backup bucket (versioning, encryption, lifecycle, no public access) |
| [eks.tf](terraform/eks.tf) | EKS cluster, node groups, add-ons (VPC CNI, EBS CSI, Pod Identity...), IAM roles, gp3 StorageClass - only when `create_eks = true` (real AWS) |

The same Terraform code has two modes:

| Mode | Cluster | AWS | Run with |
|---|---|---|---|
| local (default) | kind | LocalStack emulator | `terraform apply` |
| real AWS | **EKS** (`eks.tf`) | real account, ap-south-1 | `terraform apply -var-file=eks.tfvars` (see [3b](#3b-real-aws-run-eks)) |

The run below is the local mode (LocalStack community edition has no EKS API, so kind plays the cluster). [terraform.tfvars.example](terraform/terraform.tfvars.example) is committed, but no credentials.

![init](screenshots/10-terraform-init-validate.png)
![plan](screenshots/11-terraform-plan.png)
![apply](screenshots/12-terraform-apply.png)
![cluster](screenshots/13-infra-verify-cluster.png)
![aws](screenshots/14-infra-verify-aws.png)

`terraform destroy` at the end removed all 28 resources:

![destroy](screenshots/50-terraform-destroy.png)

## 3b. Real AWS run: EKS

Later I got an AWS account (free plan with credits), so I ran the same project on **Amazon EKS** in `ap-south-1`. Same Terraform code, a separate workspace (`eks`) and [eks.tfvars](terraform/eks.tfvars). The Helm chart, the Argo CD Application and `gitops/values-prod.yaml` did not change at all.

```mermaid
flowchart LR
    me((my browser /<br/>curl)) -->|HTTP :80<br/>SG: my IP only| edge
    subgraph aws[AWS ap-south-1 - VPC 10.30.0.0/16]
      subgraph pub[public subnets]
        edge[edge node t3.small<br/>ingress-nginx hostPort 80]
        nat[NAT gateway]
      end
      subgraph priv[private subnets, 2 AZs]
        n1[node m7i-flex.large<br/>ap-south-1a]
        n2[node m7i-flex.large<br/>ap-south-1b]
        ebs[(EBS gp3<br/>postgres PVC)]
      end
      cp[EKS control plane 1.36<br/>managed by AWS]
    end
    edge --> n1 & n2
    n1 & n2 -->|pull images| nat --> ghcr[(GHCR)]
    n2 --- ebs
```

| What | How |
|---|---|
| Cluster | EKS 1.36 (standard support - 1.33 is already in paid extended support), access entries API, the IAM user that runs Terraform is admin |
| Nodes | managed node group `default`: 2 × m7i-flex.large in the **private** subnets (internet via NAT); node group `edge`: 1 × t3.small in a public subnet, tainted so only ingress runs there |
| Add-ons | `vpc-cni` with **network policy** enforcement on, `kube-proxy`, `coredns`, `eks-pod-identity-agent`, `aws-ebs-csi-driver` |
| Storage | EBS CSI driver gets its AWS permissions through **EKS Pod Identity** (only its service account, not every pod on the node); default StorageClass `gp3`, encrypted |
| Ingress | ingress-nginx on the edge node, port 80 opened in the security group only for my IP (passed with `-var`, not committed) |
| Credentials | `aws configure` (IAM user), nothing in the code; kubeconfig via `aws eks update-kubeconfig`, tokens from `aws eks get-token` |

### Config and plan

![account and config](screenshots/60-eks-account-and-config.png)
![plan](screenshots/61-eks-terraform-plan.png)

### Apply - and two real problems

VPC, NAT, EKS (about 8.5 minutes for the control plane), node group and add-ons were created, then the apply **failed at ingress-nginx**:

![apply](screenshots/62-eks-terraform-apply.png)

**Problem 1 - no load balancer.** On EKS the normal way is `service.type: LoadBalancer`, and AWS creates an NLB. The service stayed `<pending>`. The events, and the same call by hand, show that the account itself is not allowed to create load balancers (`OperationNotPermitted` - a limit on new free-plan accounts that only AWS Support can lift):

![no load balancer](screenshots/63-eks-problem-no-load-balancer.png)

Fix: a small **edge node group** in a public subnet with the label `ingress-ready=true` and a taint, and ingress-nginx runs there with `hostPort: 80` (the same idea as on kind). The security group rule allows port 80 only from my IP.

![edge node fix](screenshots/64-eks-fix-edge-node-apply.png)

**Problem 2 - "didn't have free ports".** The ingress pod still did not schedule on the edge node. The **EKS Pod Identity Agent** daemonset declares port 80 as a host port on every node, so the scheduler saw a conflict. Nothing on the edge node uses Pod Identity, so I gave the add-on a node affinity that skips `ingress-ready` nodes. After that the apply finished:

![hostport conflict fix](screenshots/65-eks-fix-hostport-conflict.png)

Both fixes are in [eks.tf](terraform/eks.tf) and [addons.tf](terraform/addons.tf) now, so a fresh `apply` works in one go.

### Verify the cluster and AWS resources

![cluster](screenshots/66-eks-verify-cluster.png)
![aws](screenshots/67-eks-verify-aws.png)

### GitOps deploy on EKS

The same `kubectl apply -f gitops/argocd-application.yaml` as on kind. Argo CD pulled the chart and `values-prod.yaml` from GitHub and deployed the app. The postgres PVC became a real **encrypted EBS gp3 volume**:

![gitops bootstrap](screenshots/68-eks-gitops-bootstrap.png)

App over the internet, and the NetworkPolicy being **enforced** (the backend can reach postgres, the frontend can't):

![app over internet](screenshots/69-eks-app-over-internet.png)

Browser (`tripboard.local`, `argocd.local` and `grafana.local` point to the edge node's public IP, like an `/etc/hosts` entry):

![app browser](screenshots/70-eks-app-browser.png)
![argocd](screenshots/71-eks-argocd-tripboard.png)
![grafana](screenshots/72-eks-grafana-tripboard.png)

### AWS console

The console login is not an EKS access entry, so the console can't list Kubernetes objects (pods/nodes "Data unavailable"). Everything AWS-side is visible:

![console cluster](screenshots/73-eks-console-cluster.png)
![console node groups](screenshots/74-eks-console-node-groups.png)
![console ec2](screenshots/75-eks-console-ec2-nodes.png)
![console vpc](screenshots/76-eks-console-vpc.png)

### Destroy

First the app workloads and the postgres PVC are deleted, so the EBS CSI driver deletes the EBS volume (Terraform doesn't know about that volume). Deleting only the Argo CD `Application` is not enough: without the `resources-finalizer.argocd.argoproj.io` finalizer it does not cascade, and the PVC hung in `Terminating` because the postgres pod still used it. Then `terraform destroy`. Afterwards the account has no clusters, instances, volumes, NAT gateways, Elastic IPs or buckets left.

![destroy](screenshots/77-eks-terraform-destroy.png)

What it cost: EKS control plane $0.10/h + 2 × m7i-flex.large + 1 × t3.small + NAT gateway - roughly $0.45/h, paid from the free-plan credits. My first destroy attempt died together with Docker Desktop on my laptop, so the cluster ran about 20 hours instead of 3 before I noticed. Lesson: check the cloud side (`aws eks list-clusters`) after a destroy instead of trusting that the command ran - or set an AWS Budget alert.

## 4. CI/CD pipeline

[`.github/workflows/ci.yml`](.github/workflows/ci.yml), runs on every push to `main` except GitOps, docs and screenshot changes (so the bot commit doesn't loop), and on pull requests that touch the app, Dockerfiles or chart.

| # | Job | Fails the pipeline when |
|---|---|---|
| 1 | Backend - lint & test | flake8 error or any pytest failure |
| 2 | Frontend - build | `npm run build` fails |
| 3 | SAST - Bandit + Semgrep | Bandit medium+ or any Semgrep finding (python, react, dockerfile rules) |
| 4 | SCA - pip-audit + npm audit | known CVE in a backend dependency / high+ in frontend |
| 5 | Secret scan - Gitleaks | a secret in the project files |
| 6 | Docker build (backend, frontend) + **Trivy** | fixable HIGH/CRITICAL CVE in the image (this is the **security gate**) |
| 7 | Push to GHCR | - images tagged with the **commit SHA** only, never `latest` |
| 8 | Deploy test | `helm upgrade --install --wait` on a throw-away kind cluster + `helm test` + API smoke test fail |
| 9 | Update GitOps manifest | - commits `deploy: tripboard <sha>` to `gitops/values-prod.yaml` |

![pipeline](screenshots/21-actions-pipeline.png)
![tests and security](screenshots/26-ci-tests-and-security.png)
![trivy push gitops](screenshots/27-ci-trivy-push-gitops.png)
![ghcr](screenshots/22-ghcr-backend-package.png)

The pipeline caught real problems while I built it:
- Trivy failed the first frontend image: the `nginx-unprivileged:1.29-alpine` base had 43 fixable HIGH CVEs → moved to `1.31-alpine3.24` + `apk upgrade` → 0.
- The first deploy test timed out: `exec /entrypoint.sh: permission denied` (git on Windows had stored the script without the execute bit) and nginx exiting with `host not found in upstream`. Fixed with `COPY --chmod=0755`, `git update-index --chmod=+x` and runtime DNS resolution in nginx, and added a "debug info on failure" step to the job.

## 5. DevSecOps

| Control | Where |
|---|---|
| SAST | Bandit ([security/bandit.yaml](security/bandit.yaml)) + Semgrep in CI |
| SCA | pip-audit (backend), npm audit (frontend) in CI |
| Secret scanning | Gitleaks ([security/gitleaks.toml](security/gitleaks.toml)) in CI |
| Image scanning + gate | Trivy, `--severity HIGH,CRITICAL --ignore-unfixed --exit-code 1`, both images |
| No secrets in git | DB password generated by Terraform (`random_password`) → K8s Secret, chart uses `existingSecret` |
| Least privilege runtime | all containers non-root, `allowPrivilegeEscalation: false`, drop ALL capabilities, seccomp RuntimeDefault, read-only root FS on the backend |
| Pod Security | namespace label `pod-security.kubernetes.io/enforce: restricted` - pods that break the rules are rejected |
| Network | NetworkPolicy: only backend pods may reach Postgres on 5432 |
| Supply chain | images pinned by commit SHA, built and scanned once, the same image goes to test and prod |

## 6. Kubernetes + Helm

Chart [helm/tripboard](helm/tripboard):

| Object | Details |
|---|---|
| Deployment `tripboard-backend` | 2-5 replicas (HPA on CPU 70%), startup/liveness `/health`, readiness `/ready`, requests/limits, ConfigMap + Secret env |
| Deployment `tripboard-frontend` | 2 replicas, `/healthz` probes |
| StatefulSet `tripboard-postgres` | 1Gi PVC (volumeClaimTemplate), `pg_isready` probes, uid 70 |
| Services | ClusterIP backend:8000, frontend:8080, headless postgres |
| Ingress | host `tripboard.local`: `/api` → backend, `/` → frontend |
| ConfigMap, Secret | app config / DB credentials (`existingSecret` in prod) |
| HPA, NetworkPolicy, ServiceMonitor | autoscaling, DB isolation, Prometheus scraping |
| `helm test` | smoke test pod (ready, frontend, API through frontend) |

Production is deployed by Argo CD (section 8). To show the plain Helm workflow I also installed a **staging** copy with the Helm CLI:

```bash
kubectl create namespace tripboard-staging
kubectl label namespace tripboard-staging pod-security.kubernetes.io/enforce=restricted
helm upgrade --install tripboard-staging helm/tripboard -n tripboard-staging \
  --set environment=staging --set image.backend.tag=<sha> --set image.frontend.tag=<sha> \
  --set ingress.host=staging.tripboard.local --wait
helm test tripboard-staging -n tripboard-staging
```

![helm staging](screenshots/16-helm-staging-install.png)

Production resources:

![k8s resources](screenshots/18-k8s-resources.png)

The HPA scaled the backend from 2 to 3 pods by itself under the generated traffic.

App through the Ingress:

![app](screenshots/20-app-via-ingress.png)

## 7. Monitoring

- kube-prometheus-stack installed by Terraform with [kube-prometheus-values.yaml](monitoring/kube-prometheus-values.yaml) (Grafana, Prometheus, Alertmanager behind the ingress).
- Backend exposes `/metrics`. The chart's **ServiceMonitor** makes Prometheus scrape every backend pod.
- Dashboard [grafana-dashboard.yaml](monitoring/grafana-dashboard.yaml) (generated by [make_dashboard.py](monitoring/make_dashboard.py)): backends up, req/s, 5xx ratio, p95 latency, trips stored, req/s per endpoint & status, latency p50/p95, CPU/memory per pod, trips by status, restarts.
- Alerts [alert-rules.yaml](monitoring/alert-rules.yaml): `TripboardBackendDown`, `TripboardHigh5xxRate`, `TripboardSlowRequests`, `TripboardPodRestarting`.

![metrics](screenshots/19-metrics-endpoint.png)
![targets](screenshots/24-prometheus-targets.png)
![grafana](screenshots/25-grafana-tripboard.png)
![alert rules](screenshots/28-prometheus-alert-rules.png)

## 8. GitOps (Argo CD)

[gitops/argocd-application.yaml](gitops/argocd-application.yaml) is a **multi-source** Application: the chart from `helm/tripboard` plus `$values/gitops/values-prod.yaml`. It has auto-sync, `prune` and `selfHeal`. The only manual step after Terraform is applying this file once.

![bootstrap](screenshots/15-gitops-bootstrap.png)

**Full flow, recorded:** I pushed a code change → the pipeline built `2df44d4`, scanned it, pushed it, and committed `deploy: tripboard 2df44d4` → Argo CD went `OutOfSync` → `Progressing` → `Healthy` → `/api/info` returned the new version. No kubectl and no manual helm.

![rollout](screenshots/17-gitops-rollout.png)
![argocd](screenshots/23-argocd-tripboard.png)
![history](screenshots/48-argocd-history.png)

## 9. Troubleshooting challenge

→ **[troubleshooting/README.md](troubleshooting/README.md)**

| # | Fault introduced | Symptom | Root cause found with |
|---|---|---|---|
| 1 | Ingress host typo | 404 on every path | `kubectl get ingress` |
| 2 | Frontend image tag typo | `ImagePullBackOff` | `kubectl describe pod`, `docker manifest inspect` |
| 3 | DB secret renamed | Postgres `CreateContainerConfigError`, backend not Ready | events: `secret "tripboard-database" not found` |
| 4 | (side effect) StatefulSet stuck after fix | Postgres still broken after the git fix | StatefulSet revisions → delete stuck pod |
| 5 | Memory limit < request | Argo CD sync error | Argo operation message (API validation) |
| 6 | Memory limit too low | `OOMKilled`, exit 137 | `describe pod`, `kubectl top`, alert |
| 7 | Manual drift (scale to 0, delete NetworkPolicy) | none - auto-repaired | Argo CD self-heal |

![incident in grafana](screenshots/49-grafana-incident-window.png)

## 10. Lessons learned

- Shift-left security works only if it can **fail the build**. Trivy blocked a base image with 43 HIGH CVEs that I would have shipped otherwise.
- "Works on my machine" happened to me twice: an execute bit lost by git on Windows, and nginx's startup-time DNS resolution. Building and testing the image in CI on a real cluster catches both.
- GitOps turns deployments and rollbacks into commits. Every fix in the challenge was a reviewed-looking commit or a `git revert`, and Argo CD's history matches the git history.
- Readiness probes + rolling updates contain most bad releases. A single-replica StatefulSet has no such safety net, and needs manual action after a failed rollout.
- Terraform for the whole platform (cluster, add-ons, secrets) means I can destroy and rebuild everything in about 10 minutes, which I had to do once after Docker crashed.
- Moving from kind to EKS needed changes only in Terraform (cluster, storage, ingress); the chart and the GitOps files stayed the same. The surprises were account limits (no load balancers) and AWS add-ons using host ports - things an emulator never shows.

## Known limitations

- The full GitOps / troubleshooting work ran on kind + LocalStack. The EKS run on real AWS ([3b](#3b-real-aws-run-eks)) covered infra, deploy, monitoring and was then destroyed to save credits.
- On EKS, ingress goes through a single public edge node instead of an AWS load balancer (the account can't create load balancers yet). One edge node = single point of failure; with a normal account this would be an NLB.
- EKS API endpoint is public (needed for kubectl from my machine); in production I'd limit `public_access_cidrs` or use only the private endpoint + VPN.
- Single Postgres instance, no automated backups yet (the S3 bucket exists for that; a CronJob with `pg_dump` would be next).
- Grafana admin password is in the values file (lab only), and Argo CD uses its generated initial admin password.
- No TLS on the ingress (would use cert-manager in a real setup).
