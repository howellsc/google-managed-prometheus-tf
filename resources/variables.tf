variable "project_id" {
  description = "The Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "The region where resources will be created"
  type        = string
  default     = "us-west2"
  # Default value
}

variable "zone" {
  description = "The zone where resources will be created"
  type        = string
  default     = "us-west2-a"
}

variable "name" {
  description = "The unique name for the resource set"
  type        = string
  default     = "dev"
}