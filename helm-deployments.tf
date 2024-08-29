# Copyright (c) 2022, 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  deploy_from_operator      = alltrue([var.create_bastion, var.create_operator])
  deploy_from_local         = alltrue([!local.deploy_from_operator, var.control_plane_is_public])
  operator_helm_values_path = "/home/${var.operator_user}/helm-values"
}

data "oci_containerengine_cluster_kube_config" "kube_config" {
  count = local.deploy_from_local ? 1 : 0

  cluster_id = module.oke.cluster_id
  endpoint   = "PUBLIC_ENDPOINT"
}

resource "local_file" "cluster_kube_config_file" {
  count = local.deploy_from_local ? 1 : 0

  content  = one(data.oci_containerengine_cluster_kube_config.kube_config.*.content)
  filename = "${path.root}/cluster_kubeconfig"
}

module "nginx" {
  source = "./helm-module"

  bastion_host    = module.oke.bastion_public_ip
  bastion_user    = var.bastion_user
  operator_host   = module.oke.operator_private_ip
  operator_user   = var.bastion_user
  ssh_private_key = tls_private_key.stack_key.private_key_openssh

  deploy_from_operator = local.deploy_from_operator
  deploy_from_local    = local.deploy_from_local

  deployment_name           = "ingress-nginx"
  helm_chart                = "ingress-nginx"
  namespace                 = "nginx"
  helm_repository           = "https://kubernetes.github.io/ingress-nginx"
  operator_helm_values_path = local.operator_helm_values_path
  pre_deployment_commands   = []
  post_deployment_commands  = []

  helm_template_values_override = templatefile(
    "${path.root}/helm-values-templates/nginx-values.yaml.tpl",
    {
      min_bw        = 100,
      max_bw        = 100,
      pub_lb_nsg_id = module.oke.pub_lb_nsg_id
    }
  )
  helm_user_values_override = ""

  local_kubeconfig_path = "${path.root}/cluster_kubeconfig"
  depends_on            = [module.oke, local_file.cluster_kube_config_file]
}


module "cert-manager" {
  source = "./helm-module"

  bastion_host    = module.oke.bastion_public_ip
  bastion_user    = var.bastion_user
  operator_host   = module.oke.operator_private_ip
  operator_user   = var.bastion_user
  ssh_private_key = tls_private_key.stack_key.private_key_openssh

  deploy_from_operator = local.deploy_from_operator
  deploy_from_local    = local.deploy_from_local

  deployment_name           = "cert-manager"
  helm_chart                = "cert-manager"
  namespace                 = "cert-manager"
  helm_repository           = "https://charts.jetstack.io"
  operator_helm_values_path = local.operator_helm_values_path
  pre_deployment_commands   = []
  post_deployment_commands = [
    "cat <<'EOF' | kubectl apply -f -",
    "apiVersion: cert-manager.io/v1",
    "kind: ClusterIssuer",
    "metadata:",
    "  name: le-clusterissuer",
    "spec:",
    "  acme:",
    "    # You must replace this email address with your own.",
    "    # Let's Encrypt will use this to contact you about expiring",
    "    # certificates, and issues related to your account.",
    "    email: user@oracle.om",
    "    server: https://acme-staging-v02.api.letsencrypt.org/directory",
    "    privateKeySecretRef:",
    "      # Secret resource that will be used to store the account's private key.",
    "      name: le-clusterissuer-secret",
    "    # Add a single challenge solver, HTTP01 using nginx",
    "    solvers:",
    "    - http01:",
    "        ingress:",
    "          ingressClassName: nginx",
    "EOF"
  ]

  helm_template_values_override = templatefile(
    "${path.root}/helm-values-templates/cert-manager-values.yaml.tpl",
    {}
  )
  helm_user_values_override = ""

  local_kubeconfig_path = "${path.root}/cluster_kubeconfig"

  depends_on = [module.oke, local_file.cluster_kube_config_file]
}

module "jupyter" {
  source = "./helm-module"

  bastion_host    = module.oke.bastion_public_ip
  bastion_user    = var.bastion_user
  operator_host   = module.oke.operator_private_ip
  operator_user   = var.bastion_user
  ssh_private_key = tls_private_key.stack_key.private_key_openssh

  deploy_from_operator = local.deploy_from_operator
  deploy_from_local    = local.deploy_from_local

  deployment_name           = "jupyterhub"
  helm_chart                = "jupyterhub"
  namespace                 = "default"
  helm_repository           = "https://hub.jupyter.org/helm-chart/"
  operator_helm_values_path = local.operator_helm_values_path
  pre_deployment_commands   = ["export PUBLIC_IP=$(kubectl get svc -A -l app.kubernetes.io/name=ingress-nginx  -o json | jq -r '.items[] | select(.spec.type == \"LoadBalancer\") | .status.loadBalancer.ingress[].ip')"]
  deployment_extra_args = [
    "--set ingress.hosts[0]=jupyter.$${PUBLIC_IP}.nip.io",
    "--set ingress.tls[0].hosts[0]=jupyter.$${PUBLIC_IP}.nip.io",
    "--set ingress.tls[0].secretName=jupyter-tls"
  ]
  post_deployment_commands = []

  helm_template_values_override = templatefile(
    "${path.root}/helm-values-templates/jupyterhub-values.yaml.tpl",
    {
      admin_user     = var.jupyter_admin_user
      admin_password = var.jupyter_admin_password
    }
  )
  helm_user_values_override = ""

  local_kubeconfig_path = "${path.root}/cluster_kubeconfig"

  depends_on = [module.oke, local_file.cluster_kube_config_file, module.nginx]
}


module "cuopt" {
  source = "./helm-module"

  bastion_host    = module.oke.bastion_public_ip
  bastion_user    = var.bastion_user
  operator_host   = module.oke.operator_private_ip
  operator_user   = var.bastion_user
  ssh_private_key = tls_private_key.stack_key.private_key_openssh
  ngc_apikey = var.ngc_apikey
  cuopt_version = var.cuopt_version
  deploy_from_operator = local.deploy_from_operator
  deploy_from_local    = local.deploy_from_local

  deployment_name           = "cuopt"
  helm_chart                = "cuopt-24.03.00"
  namespace                 = "cuopt"
  helm_repository           = "https://helm.ngc.nvidia.com/nvidia/charts/"
  operator_helm_values_path = local.operator_helm_values_path
  pre_deployment_commands   = ["kubectl create namespace cuopt && kubectl create secret --namespace cuopt docker-registry ngc-docker-reg-secret --docker-server=nvcr.io --docker-username='$oauthtoken' --docker-password='${var.ngc_apikey}'"]
  deployment_extra_args = []
  post_deployment_commands = []

  helm_template_values_override = templatefile(
    "${path.root}/helm-values-templates/cuopt.tpl",
    {}
  )
  helm_user_values_override = ""

  local_kubeconfig_path = "${path.root}/cluster_kubeconfig"

  depends_on = [module.oke, local_file.cluster_kube_config_file, module.nginx]
}