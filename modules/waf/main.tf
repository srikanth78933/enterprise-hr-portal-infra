# AWS WAF web ACL for the ALB: AWS managed rule groups plus a per-IP rate limit.
# The ALB is created by the AWS Load Balancer Controller, so the ACL is attached through the
# Ingress annotation alb.ingress.kubernetes.io/wafv2-acl-arn (see the deploy repo).

locals {
  managed_rule_groups = {
    AWSManagedRulesCommonRuleSet          = 1
    AWSManagedRulesKnownBadInputsRuleSet  = 2
    AWSManagedRulesSQLiRuleSet            = 3
    AWSManagedRulesAmazonIpReputationList = 4
  }
}

resource "aws_wafv2_web_acl" "this" {
  name  = var.name
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = local.managed_rule_groups
    content {
      name     = rule.key
      priority = rule.value

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = rule.key
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = rule.key
        sampled_requests_enabled   = true
      }
    }
  }

  rule {
    name     = "rate-limit-per-ip"
    priority = 10

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit-per-ip"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = var.name
    sampled_requests_enabled   = true
  }
}
