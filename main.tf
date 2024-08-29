# Copyright (c) 2022, 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

module "oke" {
  source = "git::https://github.com/robo-cap/terraform-oci-oke.git?ref=c738b12"

  providers = {
    oci.home = oci.home
  }

  # IAM
  tenancy_id                   = var.tenancy_ocid
  compartment_id               = coalesce(var.compartment_id, var.compartment_ocid)
  network_compartment_id       = coalesce(var.compartment_id, var.compartment_ocid)
  create_iam_resources         = var.create_iam_resources
  # create_iam_worker_policy     = "auto"
  # create_iam_autoscaler_policy = "auto"
  # create_iam_operator_policy   = "auto"
  # create_iam_kms_policy        = "auto"
  create_iam_tag_namespace     = var.create_iam_tag_namespace
  create_iam_defined_tags      = false
  # it's recommended to create the following tag namespace and tag keys outside of the oke module
  # tag namespace: oke
  # tag keys: state_id, role, pool, cluster_autoscaler
  use_defined_tags = var.use_defined_tags
  tag_namespace    = var.tag_namespace
  freeform_tags = {
    bastion           = {}
    cluster           = {}
    iam               = {}
    network           = {}
    operator          = {}
    persistent_volume = {}
    service_lb        = {}
    workers           = {}
  }

  defined_tags = {
    bastion           = {}
    cluster           = {}
    iam               = {}
    network           = {}
    operator          = {}
    persistent_volume = {}
    service_lb        = {}
    workers           = {}
  }

  # Common
  ssh_private_key = tls_private_key.stack_key.private_key_openssh
  ssh_public_key  = local.bundled_ssh_public_keys

  # Bastion variables
  create_bastion           = var.create_bastion
  bastion_allowed_cidrs    = var.bastion_allowed_cidrs
  bastion_image_os         = var.bastion_image_os
  bastion_image_os_version = var.bastion_image_os_version
  bastion_image_type       = var.bastion_image_type
  bastion_image_id         = var.bastion_image_id
  bastion_user             = var.bastion_user

  # Operator variables
  create_operator                    = var.create_operator
  operator_image_os                  = var.operator_image_os
  operator_image_os_version          = var.operator_image_os_version
  operator_image_type                = var.operator_image_type
  operator_image_id                  = var.operator_image_id
  operator_install_kubectl_from_repo = false
  operator_user                      = var.operator_user

  # Network variables
  create_vcn               = var.create_vcn
  lockdown_default_seclist = true           # *true/false
  vcn_id                   = var.vcn_id     # Ignored if create_vcn = true
  vcn_cidrs                = [var.cidr_vcn] # Ignored if create_vcn = false
  vcn_name                 = var.vcn_name   # Ignored if create_vcn = false

  subnets = {
    bastion  = { cidr = var.cidr_bastion_subnet }
    operator = { cidr = var.cidr_operator_subnet }
    cp       = { cidr = var.cidr_cp_subnet }
    int_lb   = { cidr = var.cidr_int_lb_subnet }
    pub_lb   = { cidr = var.cidr_pub_lb_subnet }
    workers  = { cidr = var.cidr_workers_subnet }
    pods     = { cidr = var.cidr_pods_subnet }
  }

  nat_gateway_route_rules = [
    # {
    #   destination       = "192.168.0.0/16"
    #   destination_type  = "CIDR_BLOCK"
    #   network_entity_id = "drg"
    #   description       = "Terraformed - 192/16 to DRG"
    # },
  ]

  # Cluster variables
  create_cluster              = var.create_cluster // *true/false
  cluster_name                = var.cluster_name
  cluster_type                = "enhanced"   // *basic/enhanced
  cni_type                    = var.cni_type // *flannel/npn
  kubernetes_version          = var.kubernetes_version
  pods_cidr                   = "10.244.0.0/16"
  services_cidr               = "10.96.0.0/16"
  control_plane_is_public     = var.control_plane_is_public
  load_balancers              = "both"
  preferred_load_balancer     = "public"
  control_plane_allowed_cidrs = var.control_plane_allowed_cidrs
  allow_rules_public_lb = {
    "Allow TCP ingress to public load balancers for SSL traffic from anywhere" : {
      protocol = 6, port = 443, source = "0.0.0.0/0", source_type = "CIDR_BLOCK",
    },
    "Allow TCP ingress to public load balancers for HTTP traffic from anywhere" : {
      protocol = 6, port = 80, source = "0.0.0.0/0", source_type = "CIDR_BLOCK",
    }
  }

  worker_pools = {
    simple-np = {
      description = "Worker nodes for the OKE cluster.",
      size        = var.simple_np_size
      os          = "Oracle Linux",
      os_version  = "8",
      image_type  = "oke",
      image_id    = "ocid1.image...",
      shape       = lookup(var.simple_np_flex_shape, "instanceShape", "VM.Standard.E5.Flex"),
      ocpus       = lookup(var.simple_np_flex_shape, "ocpus", 2),
      memory      = lookup(var.simple_np_flex_shape, "memory", 12)
    },
    gpu-np = {
      description      = "Worker nodes with GPU for the OKE cluster.",
      size             = var.gpu_np_size,
      os               = "Oracle Linux",
      os_version       = "8",
      image_type       = "oke",
      image_id         = "ocid1.image...",
      shape            = var.gpu_np_shape,
      ocpus            = 1,
      memory           = 8
      boot_volume_size = 100
    }
  }

  # # Node pool autoscaler
  # cluster_autoscaler_install           = false
  # cluster_autoscaler_namespace         = "kube-system"
  # cluster_autoscaler_helm_version      = "9.24.0"
  # cluster_autoscaler_helm_values       = {}
  # cluster_autoscaler_helm_values_files = []

  output_detail = true
}

output "bastion" {
  value = "%{if var.create_bastion}${module.oke.bastion_public_ip}%{else}bastion host not created.%{endif}"
}

output "operator" {
  value = "%{if var.create_operator}${module.oke.operator_private_ip}%{else}operator host not created.%{endif}"
}

output "ssh_to_operator" {
  value = "%{if var.create_operator && var.create_bastion}${module.oke.ssh_to_operator}%{else}bastion and operator hosts not created.%{endif}"
}