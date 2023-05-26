module "traefik" {
  source              = "../../"
  name                = "traefik"
  aws_region          = "eu-central-1"
  aws_account_id      = "123456789012"
  organizational_unit = "ou"
  domain              = "example.com"
  ecs_cluster_arn     = "example"
  initial_vpc_id      = "vpc-00000000000000000"
  subnets             = ["subnet-00000000000000000"]
  vpc_id              = "vpc-11111111111111111"
}
