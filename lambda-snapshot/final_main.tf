###############################################################
# Provider
###############################################################
provider "aws" {
  region = "us-east-1"
}

###############################################################
# Archive Lambda Code
###############################################################
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

###############################################################
# Discover Subnets in the VPC
###############################################################
data "aws_subnets" "private_subnets" {
  filter {
    name   = "vpc-id"
    values = ["vpc-00cdgshjgajdgajdgj"]
  }
}

###############################################################
# Security Group for Lambda inside VPC
###############################################################
resource "aws_security_group" "lambda_sg" {
  name        = "lambda-ebs-backup-sg"
  description = "Security group for Lambda EBS backup"
  vpc_id      = "vpc-00cdgshjgajdgajdgj"

  # Allow all outbound traffic (required for AWS API calls)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

###############################################################
# IAM Role for Lambda
###############################################################
resource "aws_iam_role" "lambda_role" {
  name = "lambda-ebs-snapshot-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

###############################################################
# IAM Policy: EC2 Snapshot Permissions
###############################################################
resource "aws_iam_role_policy" "lambda_snapshot_policy" {
  name = "lambda-ebs-snapshot-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeVolumes",
          "ec2:CreateSnapshot",
          "ec2:CreateTags",
          "ec2:DescribeSnapshots"
        ]
        Resource = "*"
      }
    ]
  })
}

###############################################################
# Attach VPC Permissions (Fixes CreateNetworkInterface Error)
###############################################################
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

###############################################################
# Attach CloudWatch Logs permissions
###############################################################
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

###############################################################
# Lambda Function
###############################################################
resource "aws_lambda_function" "snapshot_lambda" {
  function_name = "lambda-ebs-auto-snapshot"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"

  timeout     = 300
  memory_size = 256

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      MATCH_SUBSTRING = "khaled"
    }
  }

  # VPC Configuration
  vpc_config {
    subnet_ids         = data.aws_subnets.private_subnets.ids
    security_group_ids = [aws_security_group.lambda_sg.id]
  }
}

###############################################################
# CloudWatch Scheduled Event (Daily)
###############################################################
resource "aws_cloudwatch_event_rule" "daily_schedule" {
  name                = "daily-ebs-snapshot-rule"
  description         = "Run Lambda daily"
  schedule_expression = "rate(1 day)"
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.daily_schedule.name
  target_id = "lambda-ebs-snapshot"
  arn       = aws_lambda_function.snapshot_lambda.arn
}

###############################################################
# Allow CloudWatch to invoke Lambda
###############################################################
resource "aws_lambda_permission" "allow_cw" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.snapshot_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_schedule.arn
}
