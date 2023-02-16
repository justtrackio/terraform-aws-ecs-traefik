resource "aws_route53_zone" "default" {
  name = var.domain
  vpc {
    vpc_id = var.initial_vpc_id
  }
  tags = module.this.tags

  lifecycle {
    ignore_changes = [vpc]
  }
}

resource "aws_route53_vpc_association_authorization" "networking" {
  vpc_id  = var.vpc_id
  zone_id = aws_route53_zone.default.zone_id
}

resource "aws_route53_zone_association" "networking" {
  provider = aws.owner
  vpc_id   = aws_route53_vpc_association_authorization.networking.vpc_id
  zone_id  = aws_route53_vpc_association_authorization.networking.zone_id
}

resource "aws_route53_vpc_association_authorization" "operations" {
  vpc_id  = var.operations_vpc_id
  zone_id = aws_route53_zone.default.zone_id
}

resource "aws_route53_zone_association" "operations" {
  provider = aws.owner
  vpc_id   = aws_route53_vpc_association_authorization.operations.vpc_id
  zone_id  = aws_route53_vpc_association_authorization.operations.zone_id
}

resource "aws_route53_record" "default" {
  zone_id = aws_route53_zone.default.zone_id
  name    = "*.${var.domain}"
  type    = "A"

  alias {
    name                   = module.nlb.lb_dns_name
    zone_id                = module.nlb.lb_zone_id
    evaluate_target_health = true
  }
}
