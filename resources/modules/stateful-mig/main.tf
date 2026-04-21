locals {
  instance_names = keys(var.instances)
}

# # Reserve internal IPs
# resource "google_compute_address" "internal_ips" {
#   for_each     = var.instances
#   name         = "${var.name}-${each.key}-ip"
#   region       = var.region
#   subnetwork   = var.subnetwork
#   address_type = "INTERNAL"
#   address      = each.value
# }

# Stateful MIG
resource "google_compute_instance_group_manager" "mig" {
  name               = var.name
  zone               = var.zone
  base_instance_name = var.name

  target_size = 3

  version {
    instance_template = var.instance_template
  }

  named_port {
    name = "http"
    port = 80
  }

  named_port {
    name = "layer-4"
    port = 6005
  }

  stateful_internal_ip {
    interface_name = "nic0"
    delete_rule = "NEVER"
  }
}

# # Per-instance config (assign fixed IPs)
# resource "google_compute_per_instance_config" "configs" {
#   for_each               = var.instances
#   name                   = "${var.name}-${each.key}"
#   instance_group_manager = google_compute_instance_group_manager.mig.name
#   zone                   = var.zone
#
#   preserved_state {
#     internal_ip {
#       interface_name = "nic0"
#
#       ip_address {
#         address = google_compute_address.internal_ips[each.key].id
#       }
#     }
#   }
#
#   depends_on = [google_compute_instance_group_manager.mig]
# }
#
# # Resize MIG AFTER configs exist
# resource "null_resource" "resize_mig" {
#   triggers = {
#     size = length(var.instances)
#   }
#
#   provisioner "local-exec" {
#     command = "gcloud compute instance-groups managed resize ${google_compute_instance_group_manager.mig.name} --zone ${var.zone} --size ${length(var.instances)}"
#   }
#
#   depends_on = [
#     google_compute_per_instance_config.configs
#   ]
# }
