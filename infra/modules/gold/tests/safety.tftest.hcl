mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/gold-test" }
  }
}
variables {
  account_id             = "123456789012"
  region                 = "us-east-1"
  task_boundary_arn      = "arn:aws:iam::123456789012:policy/gold-task-boundary"
  execution_boundary_arn = "arn:aws:iam::123456789012:policy/gold-execution-boundary"
}
run "no_task_without_reviewed_image" {
  command = apply
  assert {
    condition     = length(aws_ecs_task_definition.gold) == 0 && !aws_s3_bucket.gold.force_destroy && !aws_ecr_repository.gold.force_delete
    error_message = "No image means no task definition; preserve data and images on destroy."
  }
  assert {
    condition     = aws_athena_workgroup.gold.configuration[0].bytes_scanned_cutoff_per_query == 1073741824 && aws_athena_workgroup.gold.configuration[0].enforce_workgroup_configuration
    error_message = "Enforce 1 GiB scan limit, encryption and results location."
  }
  assert {
    condition     = length(aws_security_group.gold.ingress) == 0 && one(aws_security_group.gold.egress).to_port == 443
    error_message = "No ingress; HTTPS egress only."
  }
}
run "bounded_fargate_definition" {
  command = apply
  variables { image_digest = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
  assert {
    condition     = aws_ecs_task_definition.gold[0].cpu == "512" && aws_ecs_task_definition.gold[0].memory == "1024" && aws_ecs_task_definition.gold[0].requires_compatibilities == toset(["FARGATE"])
    error_message = "Bound the container to 0.5 vCPU / 1 GiB."
  }
  assert {
    condition     = aws_iam_role.task.permissions_boundary == var.task_boundary_arn && !strcontains(aws_iam_role_policy.task.policy, "iam:") && !strcontains(aws_iam_role_policy.task.policy, "RunTask")
    error_message = "The runtime must not manage IAM or start more compute."
  }
}
