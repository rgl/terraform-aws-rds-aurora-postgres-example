locals {
  # see https://github.com/porsager/postgres/blob/v3.4.4/src/index.js#L535-L557
  example_db_admin_connection_string = format(
    "postgres://%s:%s@%s?sslmode=verify-full",
    urlencode(aws_rds_cluster.example.master_username),
    urlencode(aws_rds_cluster.example.master_password),
    aws_rds_cluster.example.endpoint
  )
}

# see https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password
resource "random_password" "example_db_admin_password" {
  length           = 16 # min 8.
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!#$%&*()-_=+[]{}<>:?" # NB cannot contain /'"@
}

# see https://awscli.amazonaws.com/v2/documentation/api/latest/reference/rds/create-db-cluster.html
# see https://awscli.amazonaws.com/v2/documentation/api/latest/reference/rds/create-db-instance.html
# see https://docs.aws.amazon.com/AmazonRDS/latest/AuroraPostgreSQLReleaseNotes/AuroraPostgreSQL.Updates.html
# see https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Concepts.DBInstanceClass.html
# see the available instance classes with:
#       aws rds describe-orderable-db-instance-options \
#         --engine aurora-postgresql \
#         --engine-version 16.2 \
#         --query "OrderableDBInstanceOptions[].{DBInstanceClass:DBInstanceClass,StorageType:StorageType,SupportedEngineModes:SupportedEngineModes[0]}" \
#         --output table \
#         --region eu-west-1
# NB the aws_db_instance terraform resource cannot be used to create an aurora database instance.
# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster
resource "aws_rds_cluster" "example" {
  cluster_identifier     = var.name_prefix
  engine                 = "aurora-postgresql"
  engine_version         = "16.2"
  master_username        = "postgres" # NB cannot be admin.
  master_password        = random_password.example_db_admin_password.result
  db_subnet_group_name   = aws_db_subnet_group.db.name
  vpc_security_group_ids = [aws_security_group.db.id]
  availability_zones     = [local.vpc_az_a]
  skip_final_snapshot    = true
  apply_immediately      = true
  tags = {
    Name = var.name_prefix
  }
  lifecycle {
    ignore_changes = [
      # TODO why is this changing after initial creation?
      #      see https://github.com/hashicorp/terraform-provider-aws/issues/37210
      availability_zones,
    ]
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster_instance
resource "aws_rds_cluster_instance" "example" {
  count              = 1
  cluster_identifier = aws_rds_cluster.example.id
  identifier         = "${var.name_prefix}-${count.index}"
  instance_class     = "db.t3.medium"
  engine             = aws_rds_cluster.example.engine
  engine_version     = aws_rds_cluster.example.engine_version
  apply_immediately  = aws_rds_cluster.example.apply_immediately
  tags = {
    Name = "${var.name_prefix}-${count.index}"
  }
}
