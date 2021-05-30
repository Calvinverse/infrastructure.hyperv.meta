locals {
    server_instance_name = "consul-server"
    server_disk_name = "server.vhdx"
    server_resource_name = "resource.hashi.server"

    ui_resource_name = "resource.hashi.ui"
}



resource "hyperv_vhd" "consul_server_vhd" {
  count = var.service_discovery_cluster_size
  path = "${var.path_hyperv_vhd}/consul_server_${count.index}/${local.server_disk_name}"
  source = "${var.path_artefacts}/${local.server_resource_name}/resource/Virtual Hard Disks/ubuntu-*.vhdx"
  vhd_type = "Dynamic"
}

resource "hyperv_machine_instance" "consul_server" {
  automatic_start_action = "StartIfRunning"
  automatic_start_delay = 0
  automatic_stop_action = "ShutDown"

  checkpoint_type = "Disabled"

  count = var.service_discovery_cluster_size

  dvd_drives {
    controller_number = "0"
    controller_location = "1"
    path = "${var.path_provisioning_iso}/server-${count.index}.iso"
    resource_pool_name = ""
  }

  dynamic_memory = false

  generation = 2

  guest_controlled_cache_types = false

  hard_disk_drives {
    controller_type = "Scsi"
    controller_number = "0"
    controller_location = "0"
    path = "${var.path_hyperv_vhd}/consul_server_${count.index}/${local.server_disk_name}"
    override_cache_attributes = "Default"
  }

  memory_maximum_bytes = 1073741824 # 1Gb
  memory_minimum_bytes = 1073741824 # 1Gb
  memory_startup_bytes = 1073741824 # 1Gb

  name = "${local.name_prefix_tf}-${local.server_instance_name}-${count.index}"

  network_adaptors {
    name = "wan"
    switch_name = "${hyperv_network_switch.switch.name}"
    management_os = false
    is_legacy = false
    dynamic_mac_address = true
    virtual_subnet_id = 0
    allow_teaming = "On"
    wait_for_ips = true
  }

  processor_count = 2

  smart_paging_file_path = "${var.path_hyperv_temp}"
  snapshot_file_location = "${var.path_hyperv_temp}"

  state = "Running"

  static_memory = true

  vm_firmware {
      enable_secure_boot = "On"
      secure_boot_template = "MicrosoftUEFICertificateAuthority"
      preferred_network_boot_protocol = "IPv4"
  }
}

resource "windns" "dns-consul-servers" {
  count = var.service_discovery_cluster_size
  record_name = "hashiserver-${count.index}"
  record_type = "A"
  zone_name = "infrastructure.${var.ad_domain}"
  ipv4address = hyperv_machine_instance.consul_server[count.index].network_adapters.0.ip_addresses
}


# CONSUL UI

# CONFIG VALUES
