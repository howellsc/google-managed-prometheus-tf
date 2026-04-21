variable "name" {
  description = "MIG name"
  type        = string
}

variable "zone" {
  type = string
}

variable "region" {
  type = string
}

variable "subnetwork" {
  description = "Subnetwork self link"
  type        = string
}

variable "instance_template" {
  description = "Instance template self link"
  type        = string
}

variable "instances" {
  description = "Map of instance name => internal IP"
  type = map(string)
}