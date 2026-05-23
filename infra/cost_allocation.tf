resource "aws_ce_cost_allocation_tag" "cost_project" {
  provider = aws.billing
  count    = var.enable_cost_project_cost_allocation_tag ? 1 : 0

  tag_key = "CostProject"
  status  = "Active"
}
