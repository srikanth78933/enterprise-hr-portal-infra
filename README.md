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
├── modules/                      Reusable building blocks
│   ├── vpc/          VPC, 3 subnet tiers × 2 AZs, IGW, NAT, route tables, VPC endpoints
│   ├── eks/          EKS cluster, managed node group, core add-ons, OIDC provider (IRSA), access entries
│   ├── irsa/         IAM role for one Kubernetes ServiceAccount (used 3 times)
│   ├── rds/          RDS PostgreSQL, DB security group, credentials in Secrets Manager
│   ├── eks-addons/   Helm: AWS Load Balancer Controller, Secrets Store CSI + AWS provider,
│   │                 metrics-server, Cluster Autoscaler
│   └── waf/          WAF web ACL (managed rules + rate limit) for the ALB
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

- Terraform **1.10 or newer** (for S3 native state locking)
- AWS CLI v2, logged in as an IAM user/role with admin rights (Terraform's Helm provider uses `aws eks get-token`)
- `kubectl` (to check the cluster afterwards)

```bash
aws sts get-caller-identity   # check which account you are using
```

## One-time setup: state bucket

Create one S3 bucket for the Terraform state of both environments
(bucket names are global, so add your account ID):

```bash
export REGION=ap-south-1
export BUCKET=enterprise-hr-portal-tfstate-$(aws sts get-caller-identity --query Account --output text)

aws s3api create-bucket --bucket $BUCKET --region $REGION \
  --create-bucket-configuration LocationConstraint=$REGION
aws s3api put-bucket-versioning --bucket $BUCKET --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket $BUCKET \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
echo $BUCKET
```

Put the bucket name in `environments/dev/backend.tf` and `environments/prod/backend.tf`
(replace `CHANGE-ME-enterprise-hr-portal-tfstate`).

## Values to change in `terraform.tfvars`

| Value                     | Set it to |
|---------------------------|-----------|
| `eks_public_access_cidrs` | `["<jenkins-public-ip>/32", "<your-ip>/32"]` (who may reach the Kubernetes API) |
| `cluster_admin_arns`      | `["arn:aws:iam::<account-id>:user/<jenkins-iam-user>"]` so Jenkins can run `helm upgrade` |
| `region`, `azs`           | Only if you don't use Mumbai (`ap-south-1`); also change `region` in `backend.tf` |

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
