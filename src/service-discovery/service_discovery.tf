locals {
  server_instance_name = "consul-server"
  server_disk_name     = "consul-server.vhdx"
  server_resource_name = "resource.hashi.server"

  ui_instance_name = "consul-ui"
  ui_disk_name     = "consul-ui.vhdx"
  ui_resource_name = "resource.hashi.ui"
}

resource "hyperv_vhd" "consul_server_vhd" {
  count  = var.service_discovery_cluster_size
  path   = "${var.path_hyperv_vhd}\\consul_server_${count.index}\\${local.server_disk_name}"
  source = "${var.path_artefacts}\\${local.server_resource_name}\\resource\\Virtual Hard Disks\\ubuntu-*.vhdx"
}

resource "hyperv_machine_instance" "consul_server" {
  automatic_start_action = "StartIfRunning"
  automatic_start_delay  = 0
  automatic_stop_action  = "ShutDown"

  checkpoint_type = "Disabled"

  count = var.service_discovery_cluster_size

  dvd_drives {
    controller_number   = "0"
    controller_location = "1"
    path                = "${var.path_provisioning_iso}\\server-${count.index}.iso"
    resource_pool_name  = ""
  }

  generation = 2

  guest_controlled_cache_types = false

  hard_disk_drives {
    controller_type           = "Scsi"
    controller_number         = "0"
    controller_location       = "0"
    path                      = hyperv_vhd.consul_server_vhd[count.index].path
    override_cache_attributes = "Default"
  }

  memory_maximum_bytes = 1073741824 # 1Gb
  memory_minimum_bytes = 1073741824 # 1Gb
  memory_startup_bytes = 1073741824 # 1Gb

  name = "${local.name_prefix_tf}-${local.server_instance_name}-${count.index}"

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

resource "windns" "dns_consul_servers" {
  count       = var.service_discovery_cluster_size
  record_name = "${var.service_discovery_server_dns_prefix}-${count.index}"
  record_type = "A"
  zone_name   = "infrastructure.${var.ad_domain}"
  ipv4address = hyperv_machine_instance.consul_server[count.index].network_adaptors.0.ip_addresses[0]
}


# CONSUL UI

resource "hyperv_vhd" "consul_ui_vhd" {
  path   = "${var.path_hyperv_vhd}\\consul_ui\\${local.ui_disk_name}"
  source = "${var.path_artefacts}\\${local.ui_resource_name}\\resource\\Virtual Hard Disks\\ubuntu-*.vhdx"
}

resource "hyperv_machine_instance" "consul_ui" {
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
    path                      = hyperv_vhd.consul_ui_vhd.path
    override_cache_attributes = "Default"
  }

  memory_maximum_bytes = 1073741824 # 1Gb
  memory_minimum_bytes = 1073741824 # 1Gb
  memory_startup_bytes = 1073741824 # 1Gb

  name = "${local.name_prefix_tf}-${local.ui_instance_name}"

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

# CONFIG VALUES

# Wait for 60 seconds because the consul hosts might be restarting
resource "time_sleep" "wait_till_cluster_exists" {
  depends_on = [
    windns.dns_consul_servers[0]
  ]

  create_duration = "210s"
}

module "service_discovery_configuration" {
  depends_on = [
    time_sleep.wait_till_cluster_exists
  ]

  source = "github.com/calvinverse/calvinverse.configuration//consul-kv-service-servicediscovery?ref=feature%2Fterraform-kv-secrets-module"

  # Connection settings
  consul_acl_token       = ""
  consul_datacenter      = var.service_discovery_datacenter
  consul_server_hostname = "${windns.dns_consul_servers[0].record_name}.${windns.dns_consul_servers[0].zone_name}"
  consul_server_port     = var.service_discovery_consul_port

  # Configuration values
  consul_domain = "consulverse"
}
