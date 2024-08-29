# Copyright (c) 2022, 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  helm_values_override_user_file     = "${var.deployment_name}-${var.namespace}-user-values-override.yaml"
  helm_values_override_template_file = "${var.deployment_name}-${var.namespace}-template-values-override.yaml"

  operator_helm_values_override_user_file_path     = join("/", [var.operator_helm_values_path, local.helm_values_override_user_file])
  operator_helm_values_override_template_file_path = join("/", [var.operator_helm_values_path, local.helm_values_override_template_file])

  local_helm_values_override_user_file_path     = join("/", [path.root, local.helm_values_override_user_file])
  local_helm_values_override_template_file_path = join("/", [path.root, local.helm_values_override_template_file])
}

resource "null_resource" "helm_deployment_via_operator" {
  count = var.deploy_from_operator ? 1 : 0

  triggers = {
    manifest_md5    = try(md5("${var.helm_template_values_override}-${var.helm_user_values_override}"), null)
    deployment_name = var.deployment_name
    namespace       = var.namespace
    bastion_host    = var.bastion_host
    bastion_user    = var.bastion_user
    ssh_private_key = var.ssh_private_key
    operator_host   = var.operator_host
    operator_user   = var.operator_user
  }

  connection {
    bastion_host        = self.triggers.bastion_host
    bastion_user        = self.triggers.bastion_user
    bastion_private_key = self.triggers.ssh_private_key
    host                = self.triggers.operator_host
    user                = self.triggers.operator_user
    private_key         = self.triggers.ssh_private_key
    timeout             = "40m"
    type                = "ssh"
  }

  # #create cuopt secret
  provisioner "remote-exec" {
    inline = [""]
    on_failure = continue
  }
  
  provisioner "remote-exec" {
    inline = ["mkdir -p ${var.operator_helm_values_path}"]
  }

  provisioner "file" {
    content     = var.helm_template_values_override
    destination = local.operator_helm_values_override_template_file_path
  }

  provisioner "file" {
    content     = var.helm_user_values_override
    destination = local.operator_helm_values_override_user_file_path
  }



provisioner "remote-exec" {
  inline = concat(
    var.pre_deployment_commands,
    [
      "if [ \"${var.deployment_name}\" = \"cuopt\" ]; then",
      "  helm upgrade --install cuopt ${var.cuopt_version} --namespace cuopt --create-namespace --wait --username '$oauthtoken' --password '${var.ngc_apikey}' --set tolerations[0].key='nvidia.com/gpu' --set tolerations[0].operator='Exists' --set tolerations[0].effect='NoSchedule'",
      "else",
      "  if [ -s \"${local.operator_helm_values_override_user_file_path}\" ]; then",
      join(" ", concat([
        "    helm upgrade --install ${var.deployment_name} ${var.helm_chart}",
        "    --repo ${var.helm_repository}",
        "    --namespace ${var.namespace} --create-namespace --wait",
        "    -f ${local.operator_helm_values_override_template_file_path}",
        "    -f ${local.operator_helm_values_override_user_file_path}"
      ], var.deployment_extra_args)),
      "  else",
      join(" ", concat([
        "    helm upgrade --install ${var.deployment_name} ${var.helm_chart}",
        "    --repo ${var.helm_repository}",
        "    --namespace ${var.namespace} --create-namespace --wait",
        "    -f ${local.operator_helm_values_override_template_file_path}"
      ], var.deployment_extra_args)),
      "  fi",
      "fi"
    ],
    var.post_deployment_commands
  )
}


  provisioner "remote-exec" {
    when       = destroy
    inline     = ["helm uninstall ${self.triggers.deployment_name} --namespace ${self.triggers.namespace} --wait"]
    on_failure = continue
  }

  lifecycle {
    ignore_changes = [
      triggers["namespace"],
      triggers["deployment_name"],
      triggers["bastion_host"],
      triggers["bastion_user"],
      triggers["ssh_private_key"],
      triggers["operator_host"],
      triggers["operator_user"]
    ]
  }
}


resource "local_file" "helm_template_file" {
  count = var.deploy_from_local ? 1 : 0

  content  = var.helm_template_values_override
  filename = local.local_helm_values_override_template_file_path
}


resource "local_file" "helm_user_file" {
  count = var.deploy_from_local ? 1 : 0

  content  = var.helm_user_values_override
  filename = local.local_helm_values_override_user_file_path
}

resource "null_resource" "helm_deployment_from_local" {
  count = var.deploy_from_local ? 1 : 0

  triggers = {
    manifest_md5          = try(md5("${var.helm_template_values_override}-${var.helm_user_values_override}"), null)
    deployment_name       = var.deployment_name
    namespace             = var.namespace
    local_kubeconfig_path = var.local_kubeconfig_path
  }

  provisioner "local-exec" {
    working_dir = path.root
    command     = <<-EOT
      export KUBECONFIG=${var.local_kubeconfig_path}
      ${join("\n", var.pre_deployment_commands)}
      if [ -s "${local.local_helm_values_override_user_file_path}" ]; then
      helm upgrade --install ${var.deployment_name} ${var.helm_chart} \
      --repo ${var.helm_repository} \
      --namespace ${var.namespace} \
      --create-namespace --wait \
      -f ${local.local_helm_values_override_template_file_path} \
      -f ${local.local_helm_values_override_user_file_path} ${join(" ", var.deployment_extra_args)}
      else
      helm upgrade --install ${var.deployment_name} ${var.helm_chart} \
      --repo ${var.helm_repository} \
      --namespace ${var.namespace} \
      --create-namespace --wait \
      --kubeconfig ./cluster_kubeconfig \
      -f ${local.local_helm_values_override_template_file_path} ${join(" ", var.deployment_extra_args)}
      fi
      ${join("\n", var.post_deployment_commands)}
      EOT
  }

  provisioner "remote-exec" {
    when = destroy
    inline = [
      "export KUBECONFIG=${self.triggers.local_kubeconfig_path}",
    "helm uninstall ${self.triggers.deployment_name} --namespace ${self.triggers.namespace} --wait"]
    on_failure = continue
  }

  lifecycle {
    ignore_changes = [
      triggers["namespace"],
      triggers["deployment_name"],
      triggers["local_kubeconfig_path"]
    ]
  }

  depends_on = [local_file.helm_template_file, local_file.helm_user_file]
}