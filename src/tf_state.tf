terraform {
  backend "local" {
  }

  required_providers {
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