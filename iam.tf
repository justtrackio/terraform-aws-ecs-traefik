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
  name   = module.this.id
  policy = data.aws_iam_policy_document.default.json

  tags = module.this.tags
}

resource "aws_iam_role_policy_attachment" "task" {
  role       = module.service_task.task_role_name
  policy_arn = aws_iam_policy.default.arn
}

resource "aws_iam_role_policy_attachment" "task_exec" {
  role       = module.service_task.task_exec_role_name
  policy_arn = aws_iam_policy.default.arn
}
