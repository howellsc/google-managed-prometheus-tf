variable "name" {
  description = "The unique name for the resource set"
  type        = string
}

variable "vpc_name" {
  description = "VPC Name"
  type        = string
}

variable "region" {
  description = "The region where resources will be created"
  type        = string
}

variable "private_vpc_connection_id" {
  description = "Private VPC Connection ID"
  type        = string
}
