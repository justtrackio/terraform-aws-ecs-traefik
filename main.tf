locals {
  container_definitions = "[${module.container_definition.json_map_encoded}]"
  health_check = {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    protocol            = "TCP"
  }
}

module "nlb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "8.7.0"

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

  target_groups = concat([
    {
      name               = "${module.this.id}-${var.port_gateway}"
      backend_protocol   = "TCP"
      backend_port       = var.port_gateway
      preserve_client_ip = false
      health_check       = local.health_check
    },
    {
      name               = "${module.this.id}-${var.port_metadata}"
      backend_protocol   = "TCP"
      backend_port       = var.port_metadata
      preserve_client_ip = false
      health_check       = local.health_check
    },
    {
      name               = "${module.this.id}-${var.port_health}"
      backend_protocol   = "TCP"
      backend_port       = var.port_health
      preserve_client_ip = false
      health_check       = local.health_check
    },
    {
      name               = "${module.this.id}-${var.port_grpc}"
      backend_protocol   = "TCP"
      backend_port       = var.port_grpc
      preserve_client_ip = false
      health_check       = local.health_check
    },
    {
      name               = "${module.this.id}-80"
      backend_protocol   = "TCP"
      backend_port       = 80
      preserve_client_ip = false
      health_check       = local.health_check
    },
    ], var.prometheus_metrics_enabled ? [
    {
      name               = "${module.this.id}-${var.port_metrics}"
      backend_protocol   = "TCP"
      backend_port       = var.port_metrics
      preserve_client_ip = false
      health_check       = local.health_check
    },
    ] : []
  )

  http_tcp_listeners = concat([
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
      port               = var.port_grpc
      protocol           = "TCP"
      target_group_index = 3
    },
    ], var.prometheus_metrics_enabled ? [
    {
      port               = var.port_metrics
      protocol           = "TCP"
      target_group_index = 4
    },
    ] : []
  )

  https_listeners = [
    {
      port               = 443
      protocol           = "TLS"
      certificate_arn    = var.https_listeners_certificate_arn
      target_group_index = 4
    },
  ]

  tags = module.this.tags
}

module "ecs_label" {
  source  = "justtrackio/label/null"
  version = "0.26.0"

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
  container_image = "${var.container_image_url}:${var.container_image_tag}"
  port_mappings = concat([
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
    {
      containerPort = var.port_grpc
      hostPort      = 0
      protocol      = "tcp"
    },
    {
      containerPort = 8000
      hostPort      = 0
      protocol      = "tcp"
    },
    {
      containerPort = 8443
      hostPort      = 0
      protocol      = "tcp"
    },
    ], var.prometheus_metrics_enabled ? [{
      containerPort = var.port_metrics
      hostPort      = 0
      protocol      = "tcp"
    }] : []
  )

  docker_labels = {
    "traefik.enable"                       = true
    "traefik.http.routers.traefik.rule"    = "Host(`${module.this.name}.${var.domain}`)"
    "traefik.http.routers.traefik.service" = "api@internal"
  }

  command = concat([
    "--entrypoints.gateway.address=:${var.port_gateway}/tcp",
    "--entrypoints.grpc.address=:${var.port_grpc}/tcp",
    "--entrypoints.health.address=:${var.port_health}/tcp",
    "--entrypoints.metadata.address=:${var.port_metadata}/tcp",
    "--entrypoints.traefik.address=:${var.port_traefik}/tcp",
    "--entrypoints.websecure.address=:8443/tcp",
    "--entrypoints.web.address=:8000/tcp",
    "--ping=true",
    "--api.insecure=true",
    "--providers.ecs",
    "--providers.ecs.region=${module.this.aws_region}",
    "--providers.ecs.autodiscoverclusters=true",
    "--providers.ecs.exposedbydefault=false",
    "--providers.ecs.defaultrule=Host(`{{ index .Labels \"Application\"}}.{{ index .Labels \"Domain\"}}`)",
    ], var.prometheus_metrics_enabled ? [
    "--metrics.prometheus=${var.prometheus_metrics_enabled}",
    "--entryPoints.metrics.address=:${var.port_metrics}",
    ] : []
  )

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group  = try(aws_cloudwatch_log_group.default[0].name, ""),
      awslogs-region = module.this.aws_region
    }
  }
}

module "service_task" {
  source  = "justtrackio/ecs-alb-service-task/aws"
  version = "1.1.0"

  container_definition_json          = local.container_definitions
  ecs_cluster_arn                    = var.ecs_cluster_arn
  vpc_id                             = var.vpc_id
  launch_type                        = var.launch_type
  ignore_changes_task_definition     = var.ignore_changes_task_definition
  wait_for_steady_state              = var.wait_for_steady_state
  subnet_ids                         = var.subnets
  network_mode                       = var.network_mode
  ecs_service_role_enabled           = var.ecs_service_role_enabled
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  desired_count                      = var.desired_count
  ordered_placement_strategy = [
    {
      type  = "spread"
      field = "attribute:ecs.availability-zone"
    },
    {
      type  = "spread"
      field = "instanceId"
    }
  ]

  service_placement_constraints = [
    {
      type       = "distinctInstance"
      expression = null
    }
  ]

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
      container_port   = var.port_grpc
    },
    {
      target_group_arn = module.nlb.target_group_arns[4]
      container_name   = module.ecs_label.id
      elb_name         = null
      container_port   = 8443
    },
  ]

  label_orders = var.label_orders
  context      = module.this.context
}
