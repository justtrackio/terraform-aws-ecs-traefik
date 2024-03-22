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
  version = "9.8.0"

  create_security_group = false
  name                  = module.this.id
  vpc_id                = var.vpc_id
  subnets               = var.subnets
  internal              = var.internal
  load_balancer_type    = var.load_balancer_type

  security_group_ingress_rules = {
    ingress_all = {
      from_port   = -1
      to_port     = -1
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }
  security_group_egress_rules = {
    egress_all = {
      from_port   = -1
      to_port     = -1
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  target_groups = concat([
    {
      create_attachment  = false
      name               = "${module.this.id}-${var.port_gateway}"
      protocol           = "TCP"
      port               = var.port_gateway
      preserve_client_ip = false
      health_check       = local.health_check
    },
    {
      create_attachment  = false
      name               = "${module.this.id}-${var.port_metadata}"
      protocol           = "TCP"
      port               = var.port_metadata
      preserve_client_ip = false
      health_check       = local.health_check
    },
    {
      create_attachment  = false
      name               = "${module.this.id}-${var.port_health}"
      protocol           = "TCP"
      port               = var.port_health
      preserve_client_ip = false
      health_check       = local.health_check
    },
    {
      create_attachment  = false
      name               = "${module.this.id}-80"
      protocol           = "TCP"
      port               = 80
      preserve_client_ip = false
      health_check       = local.health_check
    },
    ],
    var.prometheus_metrics_enabled ? [
      {
        create_attachment  = false
        name               = "${module.this.id}-${var.port_metrics}"
        protocol           = "TCP"
        port               = var.port_metrics
        preserve_client_ip = false
        health_check       = local.health_check
      },
    ] : []
  )

  listeners = concat([
    {
      forward = {
        target_group_key = 0
      }
      port     = var.port_gateway
      protocol = "TCP"
    },
    {
      forward = {
        target_group_key = 1
      }
      port     = var.port_metadata
      protocol = "TCP"
    },
    {
      forward = {
        target_group_key = 2
      }
      port     = var.port_health
      protocol = "TCP"
    },
    {
      forward = {
        target_group_key = 3
      }
      port            = 443
      protocol        = "TLS"
      certificate_arn = var.https_listeners_certificate_arn
    },
    ], var.prometheus_metrics_enabled ? [
    {
      forward = {
        target_group_key = 4
      }
      port     = var.port_metrics
      protocol = "TCP"
    },
    ] : []
  )

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
  version = "0.61.1"

  container_name   = module.ecs_label.id
  container_image  = "${var.container_image_url}:${var.container_image_tag}"
  container_cpu    = var.container_cpu
  container_memory = var.container_memory
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
    "--metrics.prometheus.entryPoint=metrics",
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
  version = "1.3.0"

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

  task_cpu    = var.task_cpu
  task_memory = var.task_memory

  ecs_load_balancers = concat([
    {
      target_group_arn = module.nlb.target_groups[0].arn
      container_name   = module.ecs_label.id
      elb_name         = null
      container_port   = var.port_gateway
    },
    {
      target_group_arn = module.nlb.target_groups[1].arn
      container_name   = module.ecs_label.id
      elb_name         = null
      container_port   = var.port_metadata
    },
    {
      target_group_arn = module.nlb.target_groups[2].arn
      container_name   = module.ecs_label.id
      elb_name         = null
      container_port   = var.port_health
    },
    {
      target_group_arn = module.nlb.target_groups[3].arn
      container_name   = module.ecs_label.id
      elb_name         = null
      container_port   = 8443
    },
    ],
    var.prometheus_metrics_enabled ? [
      {
        target_group_arn = module.nlb.target_groups[4].arn
        container_name   = module.ecs_label.id
        elb_name         = null
        container_port   = var.port_metrics
      },
    ] : []
  )

  label_orders = var.label_orders
  context      = module.this.context
}
