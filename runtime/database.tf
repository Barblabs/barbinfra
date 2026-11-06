resource "aws_db_instance" "main" {
  identifier = local.name

  engine = "postgres"
  # Pinned because RDS otherwise picks its newest minor, and barbackend tests
  # only against Postgres 15.
  engine_version = "15.19"
  instance_class = "db.t4g.micro"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "barbackend"
  username = "barbackend"
  # RDS keeps the password in its own Secrets Manager secret, so it never
  # enters Terraform state.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period   = 7
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name}-final"

  # The database holds every Customer's data and the iTop credentials
  # encrypted with CREDENTIALS_KEY; losing it cannot be undone.
  lifecycle {
    prevent_destroy = true
  }
}

# RDS rotates its managed secret every 7 days by default. barbackend reads the
# password once, from DATABASE_URL at startup, so a rotation would break new
# connections until the next deploy.
resource "aws_secretsmanager_secret_rotation" "database" {
  secret_id        = aws_db_instance.main.master_user_secret[0].secret_arn
  rotation_enabled = false
}
