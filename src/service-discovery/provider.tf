terraform {
  required_providers {
    consul = {
      version = "~> 2.12.0"
    }

    hyperv = {
      source  = "taliesins/hyperv"
      version = "~> 1.0"
    }

    windns = {
      source  = "terraform.example.com/portsofportland/windns"
      version = "~> 0.5"
    }
  }
}

provider "hyperv" {
  timeout     = "120s"
}

provider "windns" {
  server   = var.ad_host
  username = var.ad_administrator_user
  password = var.ad_administrator_password
  usessl   = false
}
