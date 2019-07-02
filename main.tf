resource "aws_iam_role" "cloudbuild-role" {
  name_prefix        = "cloudbuild-role-"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.codebuild-assume-role-policy.json

  lifecycle {
    create_before_destroy = true
  }

  force_detach_policies = true
}

data "aws_iam_policy_document" "codebuild-assume-role-policy" {
  statement {
    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "codebuild-service-role-policy" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["*"]
  }

  statement {
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeDhcpOptions",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeVpcs",
    ]

    resources = ["*"]
  }

  statement {
    actions = [
      "ec2:CreateNetworkInterfacePermission",
    ]

    resources = [
      "arn:aws:ec2:${var.region}:${local.account_id}:network-interface/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "ec2:AuthorizedService"

      values = [
        "codebuild.amazonaws.com",
      ]
    }
  }
}

resource "aws_iam_role_policy" "codebuild-custom-policy" {
  name_prefix = "cloudbuild-policy-"
  role        = aws_iam_role.cloudbuild-role.name
  policy      = data.aws_iam_policy_document.codebuild-service-role-policy.json
}

resource "aws_iam_role_policy_attachment" "codebuild-ecr-policy-attachment" {
  role       = aws_iam_role.cloudbuild-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

data "aws_security_group" "default" {
  vpc_id = var.vpc_id
  name   = "default"
}

resource "aws_codebuild_project" "rateco-builder" {
  name          = "rateco-builder"
  build_timeout = 10
  badge_enabled = true
  service_role  = aws_iam_role.cloudbuild-role.arn

  cache {
    type = "LOCAL"

    modes = [
      "LOCAL_DOCKER_LAYER_CACHE",
      "LOCAL_SOURCE_CACHE",
    ]
  }

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/docker:18.09.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = "true"

    environment_variable {
      name  = "ECR_URL"
      value = "${local.account_id}.dkr.ecr.${var.region}.amazonaws.com"
    }
  }

  source {
    type                = "GITHUB"
    location            = "https://github.com/rateco/rateco.ca.git"
    git_clone_depth     = 1
    report_build_status = true

    auth {
      type = "OAUTH"
    }
  }

  vpc_config {
    vpc_id             = var.vpc_id
    subnets            = var.private_subnets
    security_group_ids = [data.aws_security_group.default.id]
  }

  tags = merge(
    local.common_tags,
    {
      "Name" = "codebuild"
    },
  )
}

output "codebuild-badge" {
  value = aws_codebuild_project.rateco-builder.badge_url
}

resource "aws_codebuild_webhook" "github" {
  project_name = aws_codebuild_project.rateco-builder.name
  filter_group {
    filter {
      type                    = "EVENT"
      pattern                 = "PULL_REQUEST_CREATED"
    }
    filter {
      type                    = "EVENT"
      pattern                 = "PULL_REQUEST_UPDATED"
    }filter {
      type                    = "EVENT"
      pattern                 = "PULL_REQUEST_REOPENED"
    }
  }
}

