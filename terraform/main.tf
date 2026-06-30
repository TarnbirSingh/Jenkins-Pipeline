terraform {
  required_version = ">= 1.6.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.53.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "openstack" {
  cloud = "openstack"
}

# ==============================================================================
# DATA SOURCES
# ==============================================================================

data "openstack_images_image_v2" "ubuntu" {
  count       = var.use_mock_provider ? 0 : 1
  name        = var.image_name
  most_recent = true
}

data "openstack_compute_flavor_v2" "selected" {
  count = var.use_mock_provider ? 0 : 1
  name  = var.flavor_name
}

data "openstack_networking_network_v2" "external" {
  count    = var.use_mock_provider ? 0 : 1
  name     = var.external_network_name
  external = true
}

# ==============================================================================
# CREDENTIALS
# ==============================================================================

resource "random_password" "admin_password" {
  length           = 16
  special          = true
  override_special = "_%@"
}

resource "random_password" "student_passwords" {
  for_each         = toset(var.student_emails)
  length           = 16
  special          = true
  override_special = "_%@"
}

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "openstack_compute_keypair_v2" "jenkins_keypair" {
  count      = var.use_mock_provider ? 0 : 1
  name       = "jenkins-keypair-${var.deployment_id}"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

# ==============================================================================
# SECURITY GROUP
# ==============================================================================

resource "openstack_networking_secgroup_v2" "jenkins_access" {
  count       = var.use_mock_provider ? 0 : 1
  name        = "jenkins-access-${var.deployment_id}"
  description = "Jenkins CI/CD: SSH + Jenkins Web UI"
}

resource "openstack_networking_secgroup_rule_v2" "ssh_ingress" {
  count             = var.use_mock_provider ? 0 : 1
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.jenkins_access[0].id
}

resource "openstack_networking_secgroup_rule_v2" "jenkins_ingress" {
  count             = var.use_mock_provider ? 0 : 1
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8080
  port_range_max    = 8080
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.jenkins_access[0].id
}

# ==============================================================================
# FLOATING IP (muss vor der VM allokiert werden wegen templatefile-Referenz)
# ==============================================================================

resource "openstack_networking_floatingip_v2" "jenkins_fip" {
  count = var.use_mock_provider ? 0 : 1
  pool  = var.floating_ip_pool
}

# ==============================================================================
# INSTANCE
# ==============================================================================

resource "openstack_compute_instance_v2" "jenkins_server" {
  count           = var.use_mock_provider ? 0 : 1
  name            = "jenkins-${var.deployment_id}"
  image_id        = data.openstack_images_image_v2.ubuntu[0].id
  flavor_id       = data.openstack_compute_flavor_v2.selected[0].id
  key_pair        = openstack_compute_keypair_v2.jenkins_keypair[0].name
  security_groups = [openstack_networking_secgroup_v2.jenkins_access[0].name]

  network {
    name = var.network_name
  }

  depends_on = [openstack_networking_floatingip_v2.jenkins_fip]

  user_data = templatefile("${path.module}/cloud-init.yaml", {
    app_name        = var.app_name
    jenkins_version = var.jenkins_version
    git_repo_url    = var.git_repo_url
    floating_ip     = openstack_networking_floatingip_v2.jenkins_fip[0].address

    admin_username = replace(replace(lower(var.admin_email), "@", "_"), ".", "_")
    admin_email    = var.admin_email
    admin_password = random_password.admin_password.result

    students = [
      for email in var.student_emails : {
        username = replace(replace(lower(email), "@", "_"), ".", "_")
        email    = email
        password = random_password.student_passwords[email].result
      }
    ]
  })
}

resource "openstack_compute_floatingip_associate_v2" "jenkins_fip_assoc" {
  count       = var.use_mock_provider ? 0 : 1
  floating_ip = openstack_networking_floatingip_v2.jenkins_fip[0].address
  instance_id = openstack_compute_instance_v2.jenkins_server[0].id
}

# ==============================================================================
# MOCK RESOURCE
# ==============================================================================

resource "null_resource" "mock_jenkins_server" {
  count = var.use_mock_provider ? 1 : 0
  triggers = {
    deployment_id = var.deployment_id
    app_name      = var.app_name
  }
}
