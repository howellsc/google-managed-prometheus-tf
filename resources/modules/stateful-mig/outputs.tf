# output "instance_ips" {
#   value = {
#     for k, v in google_compute_address.internal_ips : k => v.address
#   }
# }

output "instance_group" {
  value = google_compute_instance_group_manager.mig.instance_group
}