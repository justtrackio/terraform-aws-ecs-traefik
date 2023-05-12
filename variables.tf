variable "additional_vpc_id" {
  type        = list(string)
  description = "Additional vpc ids that should get associated with the route53 hosted-zone"
  default     = []
}

variable "cloudwatch_log_group_enabled" {
  type        = bool
  description = "A boolean to disable cloudwatch log group creation"
  default     = true
}

variable "container_image_tag" {
  type        = string
  description = "The image tag used to start the container. Images in the Docker Hub registry available by default"
  default     = "v2.9.6"
}

variable "container_image_url" {
  type        = string
  description = "The image tag used to start the container. Images in the Docker Hub registry available by default"
  default     = "traefik"
}

variable "domain" {
  type        = string
  description = "Domain for the hosted-zone"
}

variable "ecs_cluster_arn" {
  type        = string
  description = "The ECS Cluster ARN where ECS Service will be provisioned"
}

variable "ecs_service_role_enabled" {
  type        = bool
  description = "Whether or not to create the ecs service aws_iam_role resource"
  default     = false
}

variable "ignore_changes_task_definition" {
  type        = bool
  description = "Ignore changes (like environment variables) to the ECS task definition"
  default     = false
}

variable "initial_vpc_id" {
  type        = string
  description = "VPC id to be used when creating the `aws_route53_zone` resource"
}

variable "internal" {
  description = "Boolean determining if the load balancer is internal or externally facing."
  type        = bool
  default     = true
}

variable "label_orders" {
  type = object({
    cloudwatch = optional(list(string)),
    ecs        = optional(list(string)),
    iam        = optional(list(string)),
    ssm        = optional(list(string)),
    vpc        = optional(list(string))
  })
  default     = {}
  description = "Overrides the `labels_order` for the different labels to modify ID elements appear in the `id`"
}

variable "launch_type" {
  type        = string
  description = "The ECS launch type (valid options: FARGATE or EC2)"
  default     = "EC2"
}

variable "load_balancer_type" {
  description = "The type of load balancer to create. Possible values are application or network."
  type        = string
  default     = "network"
}

variable "log_retention_in_days" {
  type        = number
  description = "The number of days to retain logs for the log group"
  default     = 1
}

variable "network_mode" {
  type        = string
  description = "The network mode to use for the task. This is required to be `awsvpc` for `FARGATE` `launch_type` or `null` for `EC2` `launch_type`"
  default     = null
}

variable "port_gateway" {
  type        = number
  description = "Define the gateway port"
  default     = 8088
}

variable "port_health" {
  type        = number
  description = "Define the health port"
  default     = 8090
}

variable "port_metadata" {
  type        = number
  description = "Define the metadata port"
  default     = 8070
}

variable "port_traefik" {
  type        = number
  description = "Define the traefik port"
  default     = 9000
}

variable "subnets" {
  description = "A list of subnets to associate with the load balancer. e.g. ['subnet-1a2b3c4d','subnet-1a2b3c4e','subnet-1a2b3c4f']"
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC id where the load balancer and other resources will be deployed."
  type        = string
}

variable "wait_for_steady_state" {
  type        = bool
  description = "If true, it will wait for the service to reach a steady state (like aws ecs wait services-stable) before continuing"
  default     = true
}
