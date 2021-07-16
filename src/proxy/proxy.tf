locals {
  instance_name = "proxy-server"
  disk_name     = "proxy-server.vhdx"
  resource_name = "resource.proxy.edge"
}

resource "hyperv_vhd" "proxy_server_vhd" {
  count  = var.proxy_cluster_size
  path   = "${var.path_hyperv_vhd}\\proxy_edge_${count.index}\\${local.disk_name}"
  source = "${var.path_artefacts}\\${local.resource_name}\\resource\\Virtual Hard Disks\\ubuntu-*.vhdx"
}

#
# PROXY
#

resource "hyperv_machine_instance" "proxy_server_0" {
  automatic_start_action = "StartIfRunning"
  automatic_start_delay  = 0
  automatic_stop_action  = "ShutDown"

  checkpoint_type = "Disabled"

  dvd_drives {
    controller_number   = "0"
    controller_location = "1"
    path                = "${var.path_provisioning_iso}\\linux-client.iso"
    resource_pool_name  = ""
  }

  generation = 2

  guest_controlled_cache_types = false

  hard_disk_drives {
    controller_type           = "Scsi"
    controller_number         = "0"
    controller_location       = "0"
    path                      = hyperv_vhd.proxy_server_vhd[0].path
    override_cache_attributes = "Default"
  }

  memory_maximum_bytes = 1073741824 # 1Gb
  memory_minimum_bytes = 1073741824 # 1Gb
  memory_startup_bytes = 1073741824 # 1Gb

  name = "${local.name_prefix_tf}-${local.instance_name}-0"

  network_adaptors {
    name                = "wan"
    switch_name         = data.hyperv_network_switch.switch.name
    management_os       = false
    is_legacy           = false
    dynamic_mac_address = true
    virtual_subnet_id   = 0
    allow_teaming       = "On"
    wait_for_ips        = true
  }

  processor_count = 1

  smart_paging_file_path = var.path_hyperv_temp
  snapshot_file_location = var.path_hyperv_temp

  state = "Running"

  static_memory = true

  vm_firmware {
    enable_secure_boot              = "On"
    secure_boot_template            = "MicrosoftUEFICertificateAuthority"
    preferred_network_boot_protocol = "IPv4"
  }

  wait_for_state_timeout = 180
  wait_for_ips_timeout   = 600
}


resource "windns" "dns_proxy_server_0" {
  record_name = var.environment
  record_type = "A"
  zone_name   = "infrastructure.${var.ad_domain}"
  ipv4address = hyperv_machine_instance.proxy_server_0.network_adaptors[0].ip_addresses[0]
}

# CONFIG VALUES

module "service_discovery_configuration" {
  source = "github.com/calvinverse/calvinverse.configuration//consul-kv-service-proxy?ref=feature%2Fterraform-kv-secrets-module"

  # Connection settings
  consul_acl_token       = ""
  consul_datacenter      = "calvinverse-01"
  consul_server_hostname = "hashiserver-0.${windns.dns_proxy_server_0.zone_name}"
  consul_server_port     = 8500

  # Configuration values
  proxy_ui_color = "red"
  proxy_ui_title = "calvinverse-01"
}
