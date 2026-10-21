mock_provider "aws" {
  mock_resource "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::123456789012:policy/mock-gold-boundary" }
  }
}
variables {
  account_id                    = "123456789012"
  state_bucket_name             = "b3-lakehouse-aws-test-state"
  existing_emr_service_role_arn = "arn:aws:iam::123456789012:role/aws-service-role/ops.emr-serverless.amazonaws.com/AWSServiceRoleForAmazonEMRServerless"
  enable_gold_permissions       = true
}
run "gold_permissions_do_not_start_compute" {
  command = apply
  assert {
    condition     = alltrue([for p in concat(values(aws_iam_policy.gold_ci), values(aws_iam_policy.gold_network_ci), values(aws_iam_policy.gold_boundary)) : length(p.policy) <= 6144])
    error_message = "Managed IAM policy exceeds 6144 characters."
  }
  assert {
    condition     = !strcontains(aws_iam_policy.gold_ci["apply"].policy, "RunTask") && !strcontains(aws_iam_policy.gold_ci["apply"].policy, "StartQueryExecution") && !strcontains(aws_iam_policy.gold_ci["plan"].policy, "iam:PassRole")
    error_message = "Deployment must not run paid data workloads; plan stays read-only."
  }
  assert {
    condition     = !strcontains(aws_iam_policy.gold_network_ci["apply"].policy, "CreateNatGateway") && !strcontains(aws_iam_policy.gold_network_ci["apply"].policy, "RunInstances")
    error_message = "No NAT or fixed compute permissions."
  }
  assert {
    condition     = anytrue([for s in jsondecode(aws_iam_policy.gold_network_ci["apply"].policy).Statement : contains(try(tolist(s.Action), [s.Action]), "ec2:CreateSubnet") && s.Resource == "arn:aws:ec2:us-east-1:123456789012:vpc/*" && try(s.Condition.StringEquals["aws:ResourceTag/Project"], "") == "b3-lakehouse-aws"])
    error_message = "Creating subnets, route tables and security groups needs the tagged parent VPC authorized."
  }
  assert {
    condition = alltrue([for role, action in { plan = "ecs:DescribeTaskDefinition", apply = "ecs:DeregisterTaskDefinition" } :
    anytrue([for s in jsondecode(aws_iam_policy.gold_ci[role].policy).Statement : s.Action == action && s.Resource == "*"])])
    error_message = "Task definition describe/deregister support no resource-level permissions and need Resource *."
  }
}
