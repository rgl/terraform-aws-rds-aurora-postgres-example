# About

[![Lint](https://github.com/rgl/terraform-aws-rds-aurora-postgres-example/actions/workflows/lint.yml/badge.svg)](https://github.com/rgl/terraform-aws-rds-aurora-postgres-example/actions/workflows/lint.yml)

An example [Amazon RDS Aurora Serverless PostgreSQL](https://aws.amazon.com/rds/aurora/serverless/) database that can be used from an AWS EC2 Ubuntu Virtual Machine.

**NB** For an [Amazon RDS for PostgreSQL](https://aws.amazon.com/rds/postgresql/) example see the [rgl/terraform-aws-rds-postgres-example repository](https://github.com/rgl/terraform-aws-rds-postgres-example).

This will:

* Use the [Amazon RDS Aurora Serverless PostgreSQL service](https://aws.amazon.com/rds/aurora/serverless/).
  * Create a Database Cluster.
  * Create a Database Instance.
* Create an example Ubuntu Virtual Machine.
  * Can be used to access the Database Instance.
* Create a VPC and all the required plumbing required for the Ubuntu Virtual
  Machine to use an Amazon RDS Aurora Serverless PostgreSQL Database Instance.

# Usage (on a Ubuntu Desktop)

Install the tools:

```bash
./provision-tools.sh
```

Set the AWS Account credentials using SSO, e.g.:

```bash
# set the account credentials.
# NB the aws cli stores these at ~/.aws/config.
# NB this is equivalent to manually configuring SSO using aws configure sso.
# see https://docs.aws.amazon.com/cli/latest/userguide/sso-configure-profile-token.html#sso-configure-profile-token-manual
# see https://docs.aws.amazon.com/cli/latest/userguide/sso-configure-profile-token.html#sso-configure-profile-token-auto-sso
cat >secrets-example.sh <<'EOF'
# set the environment variables to use a specific profile.
# NB use aws configure sso to configure these manually.
# e.g. use the pattern <aws-sso-session>-<aws-account-id>-<aws-role-name>
export aws_sso_session='example'
export aws_sso_start_url='https://example.awsapps.com/start'
export aws_sso_region='eu-west-1'
export aws_sso_account_id='123456'
export aws_sso_role_name='AdministratorAccess'
export AWS_PROFILE="$aws_sso_session-$aws_sso_account_id-$aws_sso_role_name"
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_DEFAULT_REGION
# configure the ~/.aws/config file.
# NB unfortunately, I did not find a way to create the [sso-session] section
#    inside the ~/.aws/config file using the aws cli. so, instead, manage that
#    file using python.
python3 <<'PY_EOF'
import configparser
import os
aws_sso_session = os.getenv('aws_sso_session')
aws_sso_start_url = os.getenv('aws_sso_start_url')
aws_sso_region = os.getenv('aws_sso_region')
aws_sso_account_id = os.getenv('aws_sso_account_id')
aws_sso_role_name = os.getenv('aws_sso_role_name')
aws_profile = os.getenv('AWS_PROFILE')
config = configparser.ConfigParser()
aws_config_directory_path = os.path.expanduser('~/.aws')
aws_config_path = os.path.join(aws_config_directory_path, 'config')
if os.path.exists(aws_config_path):
  config.read(aws_config_path)
config[f'sso-session {aws_sso_session}'] = {
  'sso_start_url': aws_sso_start_url,
  'sso_region': aws_sso_region,
  'sso_registration_scopes': 'sso:account:access',
}
config[f'profile {aws_profile}'] = {
  'sso_session': aws_sso_session,
  'sso_account_id': aws_sso_account_id,
  'sso_role_name': aws_sso_role_name,
  'region': aws_sso_region,
}
os.makedirs(aws_config_directory_path, mode=0o700, exist_ok=True)
with open(aws_config_path, 'w') as f:
  config.write(f)
PY_EOF
unset aws_sso_start_url
unset aws_sso_region
unset aws_sso_session
unset aws_sso_account_id
unset aws_sso_role_name
# show the user, user amazon resource name (arn), and the account id, of the
# profile set in the AWS_PROFILE environment variable.
if ! aws sts get-caller-identity >/dev/null 2>&1; then
  aws sso login
fi
aws sts get-caller-identity
EOF
```

Or, set the AWS Account credentials using an Access Key, e.g.:

```bash
# set the account credentials.
# NB get these from your aws account iam console.
#    see Managing access keys (console) at
#        https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html#Using_CreateAccessKey
cat >secrets-example.sh <<'EOF'
export AWS_ACCESS_KEY_ID='TODO'
export AWS_SECRET_ACCESS_KEY='TODO'
unset AWS_PROFILE
# set the default region.
export AWS_DEFAULT_REGION='eu-west-1'
# show the user, user amazon resource name (arn), and the account id.
aws sts get-caller-identity
EOF
```

Load the secrets:

```bash
source secrets-example.sh
```

Review `main.tf`.

Initialize terraform:

```bash
make terraform-init
```

Launch the example:

```bash
rm -f terraform.log
make terraform-apply
```

Show the terraform state:

```bash
make terraform-show
```

At VM initialization time [cloud-init](https://cloudinit.readthedocs.io/en/latest/index.html) will run the `provision-app.sh` script to launch the example application.

After VM initialization is done (check the instance system log for cloud-init entries), test the `app` endpoint:

```bash
while ! wget -qO- "http://$(terraform output --raw app_ip_address)/test"; do sleep 3; done
```

And open a shell inside the VM:

```bash
ssh "ubuntu@$(terraform output --raw app_ip_address)"
cloud-init status --wait
less /var/log/cloud-init-output.log
systemctl status app
journalctl -u app
exit
```

Try accessing the Aurora PostgreSQL Database Instance, from within the AWS VPC, using [`psql`](https://www.postgresql.org/docs/current/app-psql.html):

```bash
ssh "ubuntu@$(terraform output --raw app_ip_address)" \
  LC_ALL='C.UTF-8' \
  PGSSLMODE='verify-full' \
  PGHOST="$(printf '%q' "$(terraform output --raw db_address)")" \
  PGDATABASE='postgres' \
  PGUSER="$(printf '%q' "$(terraform output --raw db_admin_username)")" \
  PGPASSWORD="$(printf '%q' "$(terraform output --raw db_admin_password)")" \
  psql \
    --echo-all \
    --no-password \
    --variable ON_ERROR_STOP=1 \
    <<'EOF'
-- show information the postgresql version.
select version();
-- show information about the current connection.
select current_user, current_database(), inet_client_addr(), inet_client_port(), inet_server_addr(), inet_server_port(), pg_backend_pid(), pg_postmaster_start_time();
-- show information about the current tls connection.
select case when ssl then concat('YES (', version, ')') else 'NO' end as ssl from pg_stat_ssl where pid=pg_backend_pid();
-- list roles.
\dg
-- list databases.
\l
EOF
```

Open an interactive psql session, show the Aurora PostgreSQL version, and exit:

```bash
ssh -t "ubuntu@$(terraform output --raw app_ip_address)" \
  LC_ALL='C.UTF-8' \
  PGSSLMODE='verify-full' \
  PGHOST="$(printf '%q' "$(terraform output --raw db_address)")" \
  PGDATABASE='postgres' \
  PGUSER="$(printf '%q' "$(terraform output --raw db_admin_username)")" \
  PGPASSWORD="$(printf '%q' "$(terraform output --raw db_admin_password)")" \
  psql
select version();
exit
```

When required, re-create the app EC2 instance:

```bash
make terraform-destroy-app
make terraform-apply
```

Destroy the example:

```bash
make terraform-destroy
```

List this repository dependencies (and which have newer versions):

```bash
GITHUB_COM_TOKEN='YOUR_GITHUB_PERSONAL_TOKEN' ./renovate.sh
```

# References

* [Environment variables to configure the AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html)
* [Token provider configuration with automatic authentication refresh for AWS IAM Identity Center](https://docs.aws.amazon.com/cli/latest/userguide/sso-configure-profile-token.html) (SSO)
* [Managing access keys (console)](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html#Using_CreateAccessKey)
* [AWS General Reference](https://docs.aws.amazon.com/general/latest/gr/Welcome.html)
  * [Amazon Resource Names (ARNs)](https://docs.aws.amazon.com/general/latest/gr/aws-arns-and-namespaces.html)
* [Connect to the internet using an internet gateway](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Internet_Gateway.html#vpc-igw-internet-access)
* [Retrieve instance metadata](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instancedata-data-retrieval.html)
* [How Instance Metadata Service Version 2 works](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-metadata-v2-how-it-works.html)
* [Amazon RDS Aurora PostgreSQL service](https://aws.amazon.com/rds/aurora/)
* [Amazon RDS Aurora Serverless service](https://aws.amazon.com/rds/aurora/serverless/)
* [Amazon RDS Aurora PostgreSQL resources](https://aws.amazon.com/rds/aurora/resources/)
* [Amazon RDS Aurora PostgreSQL User Guide](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/CHAP_AuroraOverview.html)
* [Security with Amazon Aurora PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/AuroraPostgreSQL.Security.html)
* [Using Aurora Serverless v2](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless-v2.html)
* [PostgreSQL Environment Variables](https://www.postgresql.org/docs/16/libpq-envars.html)
* [PostgreSQL System Information Functions and Operators](https://www.postgresql.org/docs/16/functions-info.html)
