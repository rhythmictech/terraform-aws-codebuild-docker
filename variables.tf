data "aws_caller_identity" "current" {
}

locals {
  account_id = data.aws_caller_identity.current.account_id

  common_tags = {
    Namespace = var.namespace
    Owner     = var.owner
  }
}

variable "region" {
  type = string
}

variable "private_subnets" {
  type = list(string)
}

variable "vpc_id" {
  type = string
}

variable "namespace" {
  type = string
}

variable "owner" {
  type    = string
  default = ""
}

