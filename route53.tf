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

resource "aws_route53_vpc_association_authorization" "default" {
  vpc_id  = var.vpc_id
  zone_id = aws_route53_zone.default.zone_id
}

resource "aws_route53_zone_association" "default" {
  provider = aws.owner
  vpc_id   = aws_route53_vpc_association_authorization.default.vpc_id
  zone_id  = aws_route53_vpc_association_authorization.default.zone_id
}

resource "aws_route53_vpc_association_authorization" "additional" {
  for_each = toset(var.additional_vpc_id)
  vpc_id   = each.value
  zone_id  = aws_route53_zone.default.zone_id
}

resource "aws_route53_zone_association" "additional" {
  for_each = toset(var.additional_vpc_id)
  provider = aws.owner
  vpc_id   = aws_route53_vpc_association_authorization.additional[each.key].vpc_id
  zone_id  = aws_route53_vpc_association_authorization.additional[each.key].zone_id
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

resource "aws_route53_record" "traefik" {
  zone_id = aws_route53_zone.default.zone_id
  name    = var.domain
  type    = "A"

  alias {
    name                   = module.nlb.lb_dns_name
    zone_id                = module.nlb.lb_zone_id
    evaluate_target_health = true
  }
}
