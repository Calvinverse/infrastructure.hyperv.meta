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
  user            = var.hyperv_administrator_user
  password        = var.hyperv_administrator_password
  host            = var.hyperv_server_address
  port            = 5986
  https           = true
  insecure        = true
  use_ntlm        = false
  script_path     = "C:/Temp/terraform_%RAND%.cmd"
  timeout         = "30s"
}

provider "windns" {
  server   = var.ad_host
  username = var.ad_administrator_user
  password = var.ad_administrator_password
  usessl   = false
}
