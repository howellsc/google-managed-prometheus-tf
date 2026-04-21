variable "name" {
  description = "Load balancer name"
  type        = string
}

variable "backend_instance_group" {
  description = "Instance group self link from MIG"
  type        = string
}

variable "port" {
  description = "Backend port"
  type        = number
  default     = 80
}

variable "health_check_path" {
  description = "HTTP health check path"
  type        = string
  default     = "/"
}