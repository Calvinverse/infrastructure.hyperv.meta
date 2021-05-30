provider "hyperv" {
  user            = "${var.hyperv_administrator_user}"
  password        = "${var.hyperv_administrator_password}"
  host            = "${var.hyperv_server_address}"
  port            = 5986
  https           = false
  insecure        = true
  use_ntlm        = true
  tls_server_name = ""
  cacert_path     = ""
  cert_path       = ""
  key_path        = ""
  script_path     = ""
  timeout         = "30s"
}

provider "windns" {
  server = "${var.ad_host}"
  username = "${var.ad_administrator_user}"
  password = "${var.ad_administrator_password}"
  usessl = false
}
