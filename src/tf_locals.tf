locals {
  environment_short = substr(var.environment, 0, 1)
}

# Name prefixes
locals {
  name_prefix = "${local.environment_short}"
  name_prefix_tf = "${local.name_prefix}-tf"
}

locals {
  common_tags = {
  }

  extra_tags = {
  }
}

locals {
  admin_username = "thebigkahuna"
}