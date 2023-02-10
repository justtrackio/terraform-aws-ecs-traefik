data "aws_ecs_cluster" "example" {
  cluster_name = "example"
}

data "aws_vpc" "initial" {}

data "aws_vpc" "operations" {}

module "traefik" {
  source            = "../../"
  name              = "traefik"
  aws_region        = "eu-central-1"
  domain            = "example.com"
  ecs_cluster_arn   = data.aws_ecs_cluster.example.arn
  initial_vpc_id    = data.aws_vpc.initial.id
  operations_vpc_id = data.aws_vpc.operations.id
  subnets           = var.subnets
  vpc_id            = var.vpc_id
}
