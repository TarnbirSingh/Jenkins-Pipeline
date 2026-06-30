# ==============================================================================
# SYSTEM OUTPUTS (MANDATORY)
# ==============================================================================

output "instance_id" {
  description = "MANDATORY: ID der Jenkins-VM für das Backend-Management"
  value       = var.use_mock_provider ? "mock-instance-${var.deployment_id}" : openstack_compute_instance_v2.jenkins_server[0].id
}

output "app_name" {
  description = "MANDATORY: Name der Anwendung für das Backend-Management"
  value       = var.app_name
}

# ==============================================================================
# USER OUTPUTS
# ==============================================================================

output "jenkins_url" {
  description = "Jenkins Web-Oberfläche (Port 8080)"
  value       = var.use_mock_provider ? "http://mock-ip:8080" : "http://${openstack_networking_floatingip_v2.jenkins_fip[0].address}:8080"
}

output "ssh_command" {
  description = "SSH-Befehl für den VM-Zugang"
  value       = var.use_mock_provider ? "ssh ubuntu@mock-ip" : "ssh -i <private_key> ubuntu@${openstack_networking_floatingip_v2.jenkins_fip[0].address}"
}

output "admin_credentials" {
  description = "Admin-Zugangsdaten des Dozenten (Jenkins Admin)"
  sensitive   = true
  value = {
    username    = replace(replace(lower(var.admin_email), "@", "_"), ".", "_")
    email       = var.admin_email
    password    = random_password.admin_password.result
    jenkins_url = var.use_mock_provider ? "http://mock-ip:8080" : "http://${openstack_networking_floatingip_v2.jenkins_fip[0].address}:8080"
  }
}

output "student_credentials" {
  description = "Zugangsdaten aller Studierenden"
  sensitive   = true
  value = {
    for email in var.student_emails : email => {
      username    = replace(replace(lower(email), "@", "_"), ".", "_")
      email       = email
      password    = random_password.student_passwords[email].result
      jenkins_url = var.use_mock_provider ? "http://mock-ip:8080" : "http://${openstack_networking_floatingip_v2.jenkins_fip[0].address}:8080"
    }
  }
}

output "ssh_private_key" {
  description = "SSH Private Key für den VM-Zugang"
  sensitive   = true
  value       = tls_private_key.ssh_key.private_key_openssh
}
