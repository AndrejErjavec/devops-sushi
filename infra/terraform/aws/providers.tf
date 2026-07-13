terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "devops-sushi-tfstate"
    key = "school/terraform.tfstate"
    region = "eu-west-1"
    use_lockfile = true
  }
}

provider "aws" {
  region = "eu-west-1"
}