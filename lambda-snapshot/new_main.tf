terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# --------------------------------------------------------------------------
# 1. IAM ROLE FOR LAMBDA
# --------------------------------------------------------------------------
resource "aws_iam_role" "lambda_role" {
  name = "lambda-ebs-snapshot-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# --------------------------------------------------------------------------
# 2. IAM POLICY FOR EBS SNAPSHOTS + LOGGING
# --------------------------------------------------------------------------
resource "aws_iam_policy" "lambda_policy" {
  name = "lambda-ebs-snapshot-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2SnapshotPermissions"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags",
          "ec2:DescribeVolumes",
          "ec2:CreateSnapshot",
          "ec2:CreateTags",
          "ec2:DescribeSnapshots"
        ]
        Resource = "*"
      },
      {
        Sid    = "LambdaLogging"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# --------------------------------------------------------------------------
# 3. ARCHIVE THE PYTHON LAMBDA CODE
# --------------------------------------------------------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

# --------------------------------------------------------------------------
# 4. VPC DISCOVERY (automatically find all subnets in the VPC)
# --------------------------------------------------------------------------
data "aws_subnets" "lambda_subnets" {
  filter {
    name   = "vpc-id"
    values = ["vpc-00cdgshjgajdgajdgj"]
  }
}

# --------------------------------------------------------------------------
# 5. SECURITY GROUP FOR THE LAMBDA FUNCTION
# --------------------------------------------------------------------------
resource "aws_security_group" "lambda_sg" {
  name        = "lambda-ebs-backup-sg"
  description = "Security group for Lambda to run inside VPC"
  vpc_id      = "vpc-00cdgshjgajdgajdgj"

  # Lambda needs outbound traffic to reach EC2 API endpoints (public AWS endpoints)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --------------------------------------------------------------------------
# 6. LAMBDA FUNCTION (with VPC config)
# --------------------------------------------------------------------------
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

  # ---- VPC CONFIGURATION ----
  vpc_config {
    subnet_ids         = data.aws_subnets.lambda_subnets.ids
    security_group_ids = [aws_security_group.lambda_sg.id]
  }
}

# --------------------------------------------------------------------------
# 7. EVENTBRIDGE (SCHEDULED DAILY EXECUTION)
# --------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "daily_rule" {
  name                = "DailyEBSBackupRule"
  description         = "Runs the EC2 snapshot Lambda once per day"
  schedule_expression = "cron(0 3 * * ? *)" # 03:00 UTC daily
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.daily_rule.name
  target_id = "lambda-ebs-snapshot"
  arn       = aws_lambda_function.snapshot_lambda.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.snapshot_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_rule.arn
}
