# Enterprise HR Portal – Infrastructure

Terraform for the AWS infrastructure that runs
[Enterprise HR Portal](https://github.com/srikanth78933/Enterprise-HR-Management-System) on Amazon EKS.
The application is deployed by the Jenkins pipeline in
[enterprise-hr-portal-deploy](https://github.com/srikanth78933/enterprise-hr-portal-deploy).

```
                         Users ─► Route 53 ─► AWS WAF
                                      │
┌─ VPC ───────────────────────────────┼───────────────────────────────┐
│  Frontend subnets (public)    ALB (created by the LB Controller), NAT│
│  Compute subnets  (private)   EKS worker nodes + app pods           │
│  Data subnets     (isolated)  RDS PostgreSQL (Multi-AZ in prod)     │
└──────────────────────────────── 2 Availability Zones ───────────────┘
```

## Repository layout

```
enterprise-hr-portal-infra/
├── Jenkinsfile                   plan / apply / destroy for dev or prod (creates the state backend)
├── bootstrap/                    Optional: create the S3 state bucket + DynamoDB lock table by hand
├── modules/                      Reusable building blocks
│   ├── vpc/          VPC, 3 subnet tiers × 2 AZs, IGW, NAT, route tables, VPC endpoints
│   ├── eks/          EKS cluster, managed node group, core add-ons, OIDC provider (IRSA), access entries
│   ├── irsa/         IAM role for one Kubernetes ServiceAccount (used 3 times)
│   ├── rds/          RDS PostgreSQL, DB security group, credentials in Secrets Manager
│   ├── eks-addons/   Helm: AWS Load Balancer Controller, Secrets Store CSI + AWS provider,
│   │                 metrics-server, Cluster Autoscaler
│   ├── waf/          WAF web ACL (managed rules + rate limit) for the ALB
│   ├── elk-ec2/      ELK monitoring server: EC2, data volume, passwords, config bucket, Kibana ALB
│   └── s3/           Private, encrypted, HTTPS-only S3 bucket (state bucket and app buckets)
└── environments/                 One folder = one environment = one state file
    ├── dev/   backend.tf  providers.tf  main.tf  variables.tf  outputs.tf  terraform.tfvars
    └── prod/  (same files; only backend.tf key and terraform.tfvars differ)
```

`main.tf` is identical in both environments; every difference lives in `terraform.tfvars`.

## What each environment creates

| Area     | Resources |
|----------|-----------|
| Network  | VPC, 2 frontend + 2 compute + 2 data subnets, Internet Gateway, NAT gateway(s), route tables, S3 gateway endpoint, optional interface endpoints (Secrets Manager, STS, Logs) |
| EKS      | Cluster (API access mode), managed node group (Amazon Linux 2023), add-ons `vpc-cni`, `kube-proxy`, `coredns`, IAM OIDC provider, cluster-admin access entries |
| IRSA     | `…-aws-lb-controller` role, `…-cluster-autoscaler` role, `enterprise-hr-portal-<env>-secrets-role` for the app (reads only its own DB secret) |
| Add-ons  | AWS Load Balancer Controller, Secrets Store CSI driver + AWS provider (secret sync enabled), metrics-server, Cluster Autoscaler |
| Database | RDS PostgreSQL 16 (encrypted, private), DB subnet group, security group allowing 5432 only from EKS, Secrets Manager secret `enterprise-hr-portal/<env>/db` |
| Edge     | WAF web ACL (prod), attached to the ALB through the app's Ingress annotation |
| Storage  | Optional S3 buckets from `s3_buckets` in `terraform.tfvars` (none by default) |
| Monitoring | ELK EC2 instance (private, SSM only), encrypted EBS data volume, passwords in Secrets Manager, config bucket, Kibana ALB limited to `kibana_allowed_cidrs` |

### dev vs prod (`terraform.tfvars`)

| Setting              | dev                      | prod                         |
|----------------------|--------------------------|------------------------------|
| VPC CIDR             | `10.1.0.0/16`            | `10.0.0.0/16`                |
| NAT gateways         | 1 (shared)               | 2 (one per AZ)               |
| Interface endpoints  | no                       | yes                          |
| EKS cluster          | `mycompany-dev-eks`      | `mycompany-prod-eks`         |
| Nodes (Spot)         | `m7i-flex.large`, 1–2    | `m7i-flex.large`, 2–4        |
| RDS                  | `db.t4g.micro`, single-AZ | `db.t4g.medium`, Multi-AZ, deletion protection, final snapshot |
| WAF                  | off                      | on                           |
| ELK monitoring EC2   | `m7i-flex.large` (Spot), 30 GiB data | `m7i-flex.large` (Spot), 100 GiB data |

### Subnet plan (prod; dev uses `10.1.x.x`)

| Tier     | AZ a           | AZ b           | Route to internet |
|----------|----------------|----------------|-------------------|
| Frontend | `10.0.1.0/24`  | `10.0.2.0/24`  | Internet Gateway  |
| Compute  | `10.0.16.0/20` | `10.0.32.0/20` | NAT gateway       |
| Data     | `10.0.48.0/24` | `10.0.49.0/24` | none              |

Compute subnets are `/20` because the EKS VPC CNI gives every pod its own VPC IP address.

## Prerequisites

- Terraform **1.10 or newer**, AWS CLI v2, `kubectl` and `helm` on the machine that runs Terraform
  (the Jenkins server or your laptop)
- An IAM user with admin rights. Whoever creates the cluster automatically gets cluster-admin on it.
- **New AWS account:** check **Service Quotas → Amazon EC2 → Running On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances**.
  New accounts can have a small vCPU limit. dev needs about 4 vCPUs (2 × `t3.medium`); prod needs about
  12 (2 × `m7i.large` + the `m7i.xlarge` ELK server, more when the autoscaler adds nodes).
  Request an increase before applying prod if the limit is lower.

## Run with Jenkins (recommended)

The `Jenkinsfile` runs Terraform for one environment:

| Parameter     | Values | Meaning |
|---------------|--------|---------|
| `ENVIRONMENT` | `dev`, `prod` | Folder under `environments/` |
| `ACTION`      | `plan` | Show what would change; nothing is created |
|               | `apply` | Plan → manual approval → create/update |
|               | `destroy` | Remove the app's ALB → plan destroy → manual approval → destroy |

Stages: check tools and account → **create the state bucket and lock table if missing** → init/validate →
plan (saved as a build artifact) → approve → apply → outputs.

Jenkins setup:

1. Terraform on the Jenkins server:
   ```bash
   TF_VERSION=1.13.4
   curl -fsSLo /tmp/terraform.zip https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip
   sudo unzip -o /tmp/terraform.zip -d /usr/local/bin && rm /tmp/terraform.zip
   ```
2. Credentials `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` (Secret text), as for the deploy pipeline.
3. **New Item** → `enterprise-hr-portal-infra` → **Pipeline** → *Pipeline script from SCM* →
   `https://github.com/srikanth78933/enterprise-hr-portal-infra.git`, branch `*/main`, script path `Jenkinsfile`.
4. **Build Now** once (Jenkins learns the parameters; this first run is a dev `plan`).
   Then **Build with Parameters** → `dev` + `apply`.

The first dev apply takes about 25 minutes (EKS ~10 min, RDS ~10 min).

## Remote state (S3 + DynamoDB)

Terraform state for every environment lives in one S3 bucket; a DynamoDB table holds the lock,
so two people (or Jenkins and a person) can never run `apply` on the same environment at once.

```
S3 bucket  enterprise-hr-portal-tfstate-<account-id>   versioned, encrypted, private
  ├── dev/terraform.tfstate
  └── prod/terraform.tfstate
DynamoDB   enterprise-hr-portal-tf-locks               key LockID, on-demand, PITR, deletion protection
```

**The Jenkinsfile creates both automatically** on its first run. The bucket name contains the
account ID, so `backend.tf` doesn't hard-code it; it is passed at `terraform init` time.

Alternatively, create them with Terraform from the `bootstrap/` folder (same names, so both ways are
compatible): `cd bootstrap && terraform init && terraform apply`.

If a run is interrupted and leaves a lock behind, release it with
`terraform force-unlock <LOCK_ID>` (the ID is shown in the error message).

> Terraform 1.11+ prints a deprecation notice for `dynamodb_table`, because S3 can now lock by
> itself (`use_lockfile = true`). DynamoDB locking still works. To switch later, add
> `use_lockfile = true` next to `dynamodb_table`, run `terraform init -reconfigure`, and remove
> `dynamodb_table` once every user and pipeline uses the new setting.

## Values to change in `terraform.tfvars`

| Value                     | Set it to |
|---------------------------|-----------|
| `eks_public_access_cidrs` | Who may reach the Kubernetes API. `0.0.0.0/0` works (IAM login is still required); tighter: `["<jenkins-public-ip>/32", "<your-ip>/32"]` |
| `cluster_admin_arns`      | Extra IAM users/roles that need cluster-admin. Leave empty if the same IAM user runs Terraform and the app pipeline. |
| `kibana_allowed_cidrs` (prod) | `["<your-ip>/32"]` |
| `region`, `azs`           | Only if you don't use Mumbai (`ap-south-1`); also change `region` in `backend.tf` and the Jenkinsfiles |

## Run manually (without Jenkins)

```bash
cd environments/dev          # or environments/prod
terraform init -backend-config="bucket=enterprise-hr-portal-tfstate-$(aws sts get-caller-identity --query Account --output text)"
terraform plan -out=tfplan
terraform apply tfplan
```

(Create the state bucket and table first, with the Jenkins pipeline or `bootstrap/`.)

Check the cluster:

```bash
$(terraform output -raw configure_kubectl)
kubectl get nodes
kubectl get pods -n kube-system   # aws-load-balancer-controller, secrets-store-csi-driver,
                                  # secrets-provider-aws, metrics-server, cluster-autoscaler
```

## Connect the deploy repo

Terraform prints everything the deploy repo needs:

```bash
terraform output deploy_repo_values
```

| Output                       | Goes into (enterprise-hr-portal-deploy) |
|------------------------------|-----------------------------------------|
| `rds_endpoint`               | `config/env-<env>.yaml` → `env.DB_HOST` |
| `db_secret_name`             | `environments/<env>/values.yaml` → `secrets.awsSecretName` (already `enterprise-hr-portal/<env>/db`) |
| `app_irsa_role_arn`          | `environments/<env>/values.yaml` → `serviceAccount.roleArn` |
| `region`                     | `Jenkinsfile` → `AWS_REGION` |
| `waf_web_acl_arn` (prod)     | Ingress annotation `alb.ingress.kubernetes.io/wafv2-acl-arn` |

Terraform already does the manual steps listed in the deploy repo README (Secrets Manager secret,
CSI driver, IRSA role, metrics-server, EKS access for Jenkins).

The IRSA role trusts exactly namespace `hr-portal-<env>` and ServiceAccount `enterprise-hr-portal`,
which is what the Helm chart and Jenkinsfile use. Keep those names in sync.

## S3 buckets

Add buckets per environment in `terraform.tfvars`; no code changes are needed:

```hcl
s3_buckets = {
  documents = { app_access = true }          # app pods can read/write through their IRSA role
  reports   = { expiration_days = 90 }       # objects are deleted after 90 days
}
```

| Option                               | Default | Meaning |
|--------------------------------------|---------|---------|
| `app_access`                         | `false` | Grants the app's IRSA role `ListBucket`, `GetObject`, `PutObject`, `DeleteObject` |
| `versioning`                         | `true`  | Keep previous versions of objects |
| `noncurrent_version_expiration_days` | `30`    | Delete old versions after this many days |
| `expiration_days`                    | none    | Delete objects this many days after upload |
| `force_destroy`                      | `false` | Let `terraform destroy` remove a non-empty bucket (dev only) |

Every bucket is private (public access blocked), encrypted (SSE-S3), HTTPS-only, with ACLs
disabled. The real name is `enterprise-hr-portal-<env>-<key>-<account-id>`
(see `terraform output s3_bucket_names`). Keys: lowercase letters, digits and hyphens, max 20 characters.

If the application starts using a bucket, add its name to `config/env-<env>.yaml` in the deploy repo,
for example `DOCUMENTS_BUCKET: "enterprise-hr-portal-dev-documents-<account-id>"`.

## ELK monitoring server

With `enable_elk = true` (dev and prod), Terraform creates everything the
[monitoring repo](https://github.com/srikanth78933/enterprise-hr-portal-monitoring) needs:

| Resource | Details |
|----------|---------|
| EC2 `enterprise-hr-portal-prod-elk` | Ubuntu 24.04, `m7i-flex.large` (Spot), first compute subnet, no public IP, IMDSv2, Docker + Compose + AWS CLI installed by user data |
| Data volume | Encrypted gp3 EBS (100 GiB) mounted at `/data`; kept if the instance is replaced |
| Access | SSM Session Manager only (no SSH, no key pair) |
| Security groups | 5044 (Logstash) and 9200 (Elasticsearch) from the EKS nodes only; 5601 from the Kibana ALB only |
| Kibana ALB `hrp-prod-kibana` | Public, open only to `kibana_allowed_cidrs`; HTTPS when a certificate ARN is passed to the module |
| Secret `enterprise-hr-portal/prod/elk` | Generated passwords for `elastic`, `kibana_system`, `logstash_writer`, `metricbeat_writer` and the Kibana encryption key |
| Bucket `enterprise-hr-portal-prod-elk-config-<account-id>` | Jenkins uploads the stack's config here; the instance downloads it |

Set `kibana_allowed_cidrs` in `environments/prod/terraform.tfvars` to your own IP before applying.
After `terraform apply`, `terraform output elk` shows the instance ID, private IP and Kibana URL.
The monitoring repo's Jenkinsfile finds the instance by its `Name` tag, so nothing needs to be copied.

## Database credentials

Terraform generates a random password, creates the RDS instance with it and stores
`{"username","password","host","port","dbname"}` in Secrets Manager under
`enterprise-hr-portal/<env>/db`. The app reads `username` and `password` from there through IRSA.

- The password is also in the Terraform state, which is why the state bucket is private and encrypted.
- No automatic rotation: the app reads the password when a pod starts. To change it, run
  `terraform apply -replace="module.rds.random_password.db"`, then
  `kubectl rollout restart deploy/enterprise-hr-portal -n hr-portal-<env>`.

## Destroy an environment

With Jenkins: **Build with Parameters** → environment + `destroy`. The pipeline removes the app's
Helm release (and with it the ALB) before destroying.

Manually: the ALB is created by the AWS Load Balancer Controller, not by Terraform. Remove the app
first, otherwise the ALB is left behind and the VPC cannot be deleted:

```bash
helm uninstall enterprise-hr-portal -n hr-portal-dev
kubectl get ingress -A          # wait until no ingress is left
cd environments/dev && terraform destroy
```

Prod has RDS deletion protection on; set `db_deletion_protection = false` and apply before destroying.

## Cost notes

The biggest fixed costs are the EKS control plane, NAT gateways, RDS and (prod) interface endpoints.
Destroy dev when you are not using it.
