locals {
  container_definitions = "[${module.container_definition.json_map_encoded}]"
}

module "nlb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "8.3.1"

  name               = module.this.id
  vpc_id             = var.vpc_id
  subnets            = var.subnets
  internal           = var.internal
  load_balancer_type = var.load_balancer_type

  security_group_rules = {
    ingress_all = {
      type        = "ingress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
    egress_all = {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  target_groups = [
    {
      name             = "${module.this.id}-${var.port_gateway}"
      backend_protocol = "TCP"
      backend_port     = var.port_gateway
    },
    {
      name             = "${module.this.id}-${var.port_metadata}"
      backend_protocol = "TCP"
      backend_port     = var.port_metadata
    },
    {
      name             = "${module.this.id}-${var.port_health}"
      backend_protocol = "TCP"
      backend_port     = var.port_health
    },
    {
      name             = "${module.this.id}-80"
      backend_protocol = "TCP"
      backend_port     = 80
    }
  ]

  http_tcp_listeners = [
    {
      port               = var.port_gateway
      protocol           = "TCP"
      target_group_index = 0
    },
    {
      port               = var.port_metadata
      protocol           = "TCP"
      target_group_index = 1
    },
    {
      port               = var.port_health
      protocol           = "TCP"
      target_group_index = 2
    },
    {
      port               = 80
      protocol           = "TCP"
      target_group_index = 3
    },
  ]

  tags = module.this.tags
}

module "ecs_label" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  label_order = var.label_orders.ecs

  context = module.this.context
}

resource "aws_cloudwatch_log_group" "default" {
  count = var.cloudwatch_log_group_enabled ? 1 : 0

  name              = module.this.id
  tags              = module.this.tags
  retention_in_days = var.log_retention_in_days
}

module "container_definition" {
  source  = "cloudposse/ecs-container-definition/aws"
  version = "0.58.1"

  container_name  = module.ecs_label.id
  container_image = "traefik:${var.container_image_tag}"
  port_mappings = [
    {
      containerPort = var.port_gateway
      hostPort      = 0
      protocol      = "tcp"
    },
    {
      containerPort = var.port_health
      hostPort      = 0
      protocol      = "tcp"
    },
    {
      containerPort = var.port_metadata
      hostPort      = 0
      protocol      = "tcp"
    },
    {
      containerPort = var.port_traefik
      hostPort      = 0
      protocol      = "tcp"
    },
  ]

  command = [
    "--entrypoints.gateway.address=:${var.port_gateway}/tcp",
    "--entrypoints.health.address=:${var.port_health}/tcp",
    "--entrypoints.metadata.address=:${var.port_metadata}/tcp",
    "--entrypoints.traefik.address=:${var.port_traefik}/tcp",
    "--ping=true",
    "--api.insecure=true",
    "--providers.ecs",
    "--providers.ecs.region=${var.aws_region}",
    "--providers.ecs.autodiscoverclusters=true",
    "--providers.ecs.exposedbydefault=false",
    "--providers.ecs.defaultrule=Host(`{{ index .Labels \"Application\"}}.{{ index .Labels \"Domain\"}}`)"
  ]

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group  = try(aws_cloudwatch_log_group.default[0].name, ""),
      awslogs-region = var.aws_region
    }
  }
}

module "service_task" {
  source  = "justtrackio/ecs-alb-service-task/aws"
  version = "1.1.0"

  container_definition_json      = local.container_definitions
  ecs_cluster_arn                = var.ecs_cluster_arn
  vpc_id                         = var.vpc_id
  launch_type                    = var.launch_type
  ignore_changes_task_definition = var.ignore_changes_task_definition
  wait_for_steady_state          = var.wait_for_steady_state
  subnet_ids                     = var.subnets
  network_mode                   = var.network_mode
  ecs_service_role_enabled       = var.ecs_service_role_enabled

  ecs_load_balancers = [
    {
      target_group_arn = module.nlb.target_group_arns[0]
      container_name   = module.ecs_label.id
      elb_name         = null
      container_port   = var.port_gateway
    },
    {
      target_group_arn = module.nlb.target_group_arns[1]
      container_name   = module.ecs_label.id
      elb_name         = null
      container_port   = var.port_metadata
    },
    {
      target_group_arn = module.nlb.target_group_arns[2]
      container_name   = module.ecs_label.id
      elb_name         = null
      container_port   = var.port_health
    },
    {
      target_group_arn = module.nlb.target_group_arns[3]
      container_name   = module.ecs_label.id
      elb_name         = null
      container_port   = var.port_traefik
    }
  ]

  label_orders = var.label_orders
  context      = module.this.context
}
