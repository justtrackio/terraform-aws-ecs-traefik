module "iam_label" {
  source  = "justtrackio/label/null"
  version = "0.26.0"

  label_order = var.label_orders.iam

  context = module.this.context
}

data "aws_iam_policy_document" "default" {
  statement {
    sid    = "TraefikECSReadAccess"
    effect = "Allow"

    actions = [
      "ecs:ListClusters",
      "ecs:DescribeClusters",
      "ecs:ListTasks",
      "ecs:DescribeTasks",
      "ecs:DescribeContainerInstances",
      "ecs:DescribeTaskDefinition",
      "ec2:DescribeInstances",
      "ssm:DescribeInstanceInformation"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "default" {
  name   = module.iam_label.id
  policy = data.aws_iam_policy_document.default.json

  tags = module.iam_label.tags
}

resource "aws_iam_role_policy_attachment" "task" {
  role       = module.service_task.task_role_name
  policy_arn = aws_iam_policy.default.arn
}

resource "aws_iam_role_policy_attachment" "task_exec" {
  role       = module.service_task.task_exec_role_name
  policy_arn = aws_iam_policy.default.arn
}
