// Infrastructure pipeline: Terraform for one environment (dev or prod).
//   plan    -> show what would change (no changes made)
//   apply   -> plan, wait for approval, create/update the infrastructure
//   destroy -> remove the app's load balancer, plan the destroy, wait for approval, destroy
// The S3 state bucket and DynamoDB lock table are created automatically on the first run.
pipeline {
    agent any

    parameters {
        choice(name: 'ENVIRONMENT', choices: ['dev', 'prod'], description: 'Environment folder under environments/')
        choice(name: 'ACTION', choices: ['plan', 'apply', 'destroy'], description: 'plan = preview only')
    }

    environment {
        AWS_ACCESS_KEY_ID     = credentials('AWS_ACCESS_KEY_ID')
        AWS_SECRET_ACCESS_KEY = credentials('AWS_SECRET_ACCESS_KEY')
        AWS_DEFAULT_REGION    = 'ap-south-1'

        TF_DIR           = "environments/${params.ENVIRONMENT}"
        LOCK_TABLE       = 'enterprise-hr-portal-tf-locks'
        TF_IN_AUTOMATION = 'true'
        TF_INPUT         = 'false'
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '20'))
        disableConcurrentBuilds()
        timeout(time: 90, unit: 'MINUTES')
    }

    stages {
        stage('Check Tools and Account') {
            steps {
                sh '''
                    terraform version
                    aws --version
                    aws sts get-caller-identity
                '''
            }
        }

        stage('State Backend (S3 + DynamoDB)') {
            steps {
                sh '''
                    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
                    BUCKET="enterprise-hr-portal-tfstate-${ACCOUNT_ID}"

                    if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
                        echo "State bucket $BUCKET exists"
                    else
                        echo "Creating state bucket $BUCKET"
                        aws s3api create-bucket --bucket "$BUCKET" \
                            --create-bucket-configuration LocationConstraint="$AWS_DEFAULT_REGION"
                        aws s3api put-bucket-versioning --bucket "$BUCKET" \
                            --versioning-configuration Status=Enabled
                        aws s3api put-bucket-encryption --bucket "$BUCKET" \
                            --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
                        aws s3api put-public-access-block --bucket "$BUCKET" \
                            --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
                    fi

                    if aws dynamodb describe-table --table-name "$LOCK_TABLE" >/dev/null 2>&1; then
                        echo "Lock table $LOCK_TABLE exists"
                    else
                        echo "Creating lock table $LOCK_TABLE"
                        aws dynamodb create-table --table-name "$LOCK_TABLE" \
                            --attribute-definitions AttributeName=LockID,AttributeType=S \
                            --key-schema AttributeName=LockID,KeyType=HASH \
                            --billing-mode PAY_PER_REQUEST \
                            --deletion-protection-enabled
                        aws dynamodb wait table-exists --table-name "$LOCK_TABLE"
                        aws dynamodb update-continuous-backups --table-name "$LOCK_TABLE" \
                            --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true
                    fi

                    echo "$BUCKET" > .state-bucket
                '''
                script {
                    env.STATE_BUCKET = readFile('.state-bucket').trim()
                }
            }
        }

        stage('Init and Validate') {
            steps {
                sh '''
                    terraform -chdir=$TF_DIR init -backend-config="bucket=$STATE_BUCKET"
                    terraform fmt -check -recursive
                    terraform -chdir=$TF_DIR validate
                '''
            }
        }

        stage('Plan') {
            steps {
                sh '''
                    if [ "$ACTION" = "destroy" ]; then
                        terraform -chdir=$TF_DIR plan -destroy -out=tfplan
                    else
                        terraform -chdir=$TF_DIR plan -out=tfplan
                    fi
                    terraform -chdir=$TF_DIR show -no-color tfplan > plan-$ENVIRONMENT.txt
                '''
                archiveArtifacts artifacts: "plan-${params.ENVIRONMENT}.txt"
            }
        }

        stage('Approve') {
            when {
                expression { params.ACTION != 'plan' }
            }
            steps {
                timeout(time: 30, unit: 'MINUTES') {
                    input message: "${params.ACTION.toUpperCase()} the ${params.ENVIRONMENT} infrastructure? Review the plan above first.",
                          ok: "Yes, ${params.ACTION}"
                }
            }
        }

        stage('Remove App Load Balancers') {
            when {
                expression { params.ACTION == 'destroy' }
            }
            steps {
                // The ALB is created by the AWS Load Balancer Controller from the app's Ingress, not by Terraform.
                // Delete it first, otherwise the VPC cannot be destroyed.
                sh '''
                    CLUSTER=$(terraform -chdir=$TF_DIR output -raw cluster_name 2>/dev/null || true)
                    if [ -n "$CLUSTER" ] && aws eks describe-cluster --name "$CLUSTER" >/dev/null 2>&1; then
                        aws eks update-kubeconfig --name "$CLUSTER"
                        helm uninstall enterprise-hr-portal -n "hr-portal-$ENVIRONMENT" --wait || true
                        helm uninstall beats -n monitoring || true
                        for i in $(seq 1 30); do
                            [ -z "$(kubectl get ingress -A -o name 2>/dev/null)" ] && break
                            echo "Waiting for ingresses (ALBs) to be deleted..."
                            sleep 10
                        done
                    else
                        echo "No cluster found; nothing to clean up"
                    fi
                '''
            }
        }

        stage('Apply') {
            when {
                expression { params.ACTION != 'plan' }
            }
            steps {
                sh 'terraform -chdir=$TF_DIR apply tfplan'
            }
        }

        stage('Outputs') {
            when {
                expression { params.ACTION == 'apply' }
            }
            steps {
                sh 'terraform -chdir=$TF_DIR output'
            }
        }
    }

    post {
        always {
            sh 'rm -f .state-bucket $TF_DIR/tfplan'
        }
        success {
            echo "Terraform ${params.ACTION} for ${params.ENVIRONMENT} finished."
        }
        failure {
            echo 'Terraform pipeline failed. Check the stage logs above.'
        }
    }
}
