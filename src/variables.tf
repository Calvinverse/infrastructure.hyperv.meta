#
# ENVIRONMENT
#

variable "ad_domain" {
  description = "The AD domain that the DNS records need to be added to."
  type        = string
}

variable "environment" {
  default     = "test"
  description = "The name of the environment that all the resources are running in."
}

#
# PATHS
#

variable "path_artefacts" {
  description = "The path where the artefact files are extracted to"
  type        = string
}

variable "path_hyperv_temp" {
  description = "The path where Hyper-V places temp files"
  type        = string
}

variable "path_hyperv_vhd" {
  description = "The path to where the VHD files are placed"
  type        = string
}

variable "path_provisioning_iso" {
  description = "The path where the provisioning ISO files are stored."
  type        = string
}

#
# PROVIDERS
#

variable "ad_administrator_password" {
  description = "The password for the AD administrator user."
  type        = string
}

variable "ad_administrator_user" {
  description = "The user name for the AD administrator user."
  type        = string
}

variable "ad_host" {
  description = "The name of the AD server."
  type        = string
}

variable "hyperv_administrator_password" {
  description = "The password for the Hyper-V administrator user."
  type        = string
}

variable "hyperv_administrator_user" {
  description = "The user name for the Hyper-V administrator user."
  type        = string
}

variable "hyperv_server_address" {
  default     = "127.0.0.1"
  description = "The IP address or DNS name of the Hyper-V server on which the resources need to be created."
}

#
# RESOURCES - SERVICE DISCOVERY
#

variable "service_discovery_cluster_size" {
  default     = "3"
  description = "The size of the cluster."
}

#
# TAGS
#

variable "tags" {
  description = "Tags to apply to all resources created."
  type        = map(string)
  default     = {}
}
