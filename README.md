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
├── bootstrap/                    Run once: S3 state bucket + DynamoDB lock table
├── modules/                      Reusable building blocks
│   ├── vpc/          VPC, 3 subnet tiers × 2 AZs, IGW, NAT, route tables, VPC endpoints
│   ├── eks/          EKS cluster, managed node group, core add-ons, OIDC provider (IRSA), access entries
│   ├── irsa/         IAM role for one Kubernetes ServiceAccount (used 3 times)
│   ├── rds/          RDS PostgreSQL, DB security group, credentials in Secrets Manager
│   ├── eks-addons/   Helm: AWS Load Balancer Controller, Secrets Store CSI + AWS provider,
│   │                 metrics-server, Cluster Autoscaler
│   ├── waf/          WAF web ACL (managed rules + rate limit) for the ALB
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

### dev vs prod (`terraform.tfvars`)

| Setting              | dev                      | prod                         |
|----------------------|--------------------------|------------------------------|
| VPC CIDR             | `10.1.0.0/16`            | `10.0.0.0/16`                |
| NAT gateways         | 1 (shared)               | 2 (one per AZ)               |
| Interface endpoints  | no                       | yes                          |
| EKS cluster          | `mycompany-dev-eks`      | `mycompany-prod-eks`         |
| Nodes                | `t3.medium`, 1–2         | `m7i.large`, 2–4             |
| RDS                  | `db.t4g.micro`, single-AZ | `db.t4g.medium`, Multi-AZ, deletion protection, final snapshot |
| WAF                  | off                      | on                           |

### Subnet plan (prod; dev uses `10.1.x.x`)

| Tier     | AZ a           | AZ b           | Route to internet |
|----------|----------------|----------------|-------------------|
| Frontend | `10.0.1.0/24`  | `10.0.2.0/24`  | Internet Gateway  |
| Compute  | `10.0.16.0/20` | `10.0.32.0/20` | NAT gateway       |
| Data     | `10.0.48.0/24` | `10.0.49.0/24` | none              |

Compute subnets are `/20` because the EKS VPC CNI gives every pod its own VPC IP address.

## Prerequisites

- Terraform **1.10 or newer**
- AWS CLI v2, logged in as an IAM user/role with admin rights (Terraform's Helm provider uses `aws eks get-token`)
- `kubectl` (to check the cluster afterwards)

```bash
aws sts get-caller-identity   # check which account you are using
```

## One-time setup: remote state (S3 + DynamoDB)

Terraform state for every environment lives in one S3 bucket; a DynamoDB table holds the lock,
so two people (or Jenkins and a person) can never run `apply` on the same environment at once.

```
S3 bucket  enterprise-hr-portal-tfstate-<account-id>   versioned, encrypted, private, HTTPS only
  ├── dev/terraform.tfstate
  └── prod/terraform.tfstate
DynamoDB   enterprise-hr-portal-tf-locks               key LockID, on-demand, PITR, deletion protection
```

**1. Create them with the bootstrap configuration (once per AWS account):**

```bash
cd bootstrap
terraform init
terraform apply
terraform output        # state_bucket, lock_table
```

**2. Put the bucket name in both backends** (`environments/dev/backend.tf` and
`environments/prod/backend.tf`): replace `CHANGE-ME-enterprise-hr-portal-tfstate` with the
`state_bucket` output. `dynamodb_table` already matches `lock_table`.

**3. Keep the bootstrap state safe.** `bootstrap/terraform.tfstate` stays on your machine
(it is git-ignored). Optionally move it into the new bucket too: add this to `bootstrap/providers.tf`
and run `terraform init -migrate-state`:

```hcl
terraform {
  backend "s3" {
    bucket         = "<state_bucket>"
    key            = "bootstrap/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "enterprise-hr-portal-tf-locks"
    encrypt        = true
  }
}
```

If a run is interrupted and leaves a lock behind, release it with
`terraform force-unlock <LOCK_ID>` (the ID is shown in the error message).

> Terraform 1.11+ prints a deprecation notice for `dynamodb_table`, because S3 can now lock by
> itself (`use_lockfile = true`). DynamoDB locking still works. To switch later, add
> `use_lockfile = true` next to `dynamodb_table`, run `terraform init -reconfigure`, and remove
> `dynamodb_table` once every user and pipeline uses the new setting.

## Values to change in `terraform.tfvars`

| Value                     | Set it to |
|---------------------------|-----------|
| `eks_public_access_cidrs` | `["<jenkins-public-ip>/32", "<your-ip>/32"]` (who may reach the Kubernetes API) |
| `cluster_admin_arns`      | `["arn:aws:iam::<account-id>:user/<jenkins-iam-user>"]` so Jenkins can run `helm upgrade` |
| `region`, `azs`           | Only if you don't use Mumbai (`ap-south-1`); also change `region` in `backend.tf` and `bootstrap/variables.tf` |

## Create an environment

```bash
cd environments/dev          # or environments/prod
terraform init
terraform plan -out=tfplan
terraform apply tfplan       # about 20–25 minutes (EKS ~10 min, RDS ~10 min)
```

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

## Database credentials

Terraform generates a random password, creates the RDS instance with it and stores
`{"username","password","host","port","dbname"}` in Secrets Manager under
`enterprise-hr-portal/<env>/db`. The app reads `username` and `password` from there through IRSA.

- The password is also in the Terraform state, which is why the state bucket is private and encrypted.
- No automatic rotation: the app reads the password when a pod starts. To change it, run
  `terraform apply -replace="module.rds.random_password.db"`, then
  `kubectl rollout restart deploy/enterprise-hr-portal -n hr-portal-<env>`.

## Destroy an environment

The ALB is created by the AWS Load Balancer Controller, not by Terraform. Remove the app first,
otherwise the ALB is left behind and the VPC cannot be deleted:

```bash
helm uninstall enterprise-hr-portal -n hr-portal-dev
kubectl get ingress -A          # wait until no ingress is left
cd environments/dev && terraform destroy
```

Prod has RDS deletion protection on; set `db_deletion_protection = false` and apply before destroying.

## Cost notes

The biggest fixed costs are the EKS control plane, NAT gateways, RDS and (prod) interface endpoints.
Destroy dev when you are not using it.
