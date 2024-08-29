# orm-stack-oke-helm-deployment

## Getting started

This stack deploys an OKE cluster with two nodepools:
- one nodepool with flexible shapes
- one nodepool with GPU shapes

It also deploys several applications to the OKE cluster using helm:
- nginx
- cert-manager
- vllm
- qdrant vector DB
- jupyterhub

**Note:** For helm deployments it's necessary to create bastion and operator host, **or** configure a cluster with public API endpoint.

In case the bastion and operator hosts are not created, is a prerequisite to have the following tools already installed and configured:
- helm
- oci-cli
- kubectl
- jq 
- bash

## Helm Deployments

### Nginx

[Nginx](https://kubernetes.github.io/ingress-nginx/deploy/) is deployed and configured as default ingress controller.

### Cert-manager

[Cert-manager](https://cert-manager.io/docs/) is deployed to handle the configuration of TLS certificate for the configured ingress resources. Currently it's using the [staging Let's Encrypt endpoint](https://letsencrypt.org/docs/staging-environment/).

### Jupyterhub

[Jupyterhub](https://jupyterhub.readthedocs.io/en/stable/) will be accessible to the address: [https://jupyter.a.b.c.d.nip.io](https://jupyter.a.b.c.d.nip.io), where a.b.c.d is the public IP address of the load balancer associated with the NGINX ingress controller.

JupyterHub is using a dummy authentication scheme (user/password) and the access is secured using the variables:

```
jupyter_admin_user
jupyter_admin_password
```

### vLLM

The LLM model is deployed using [vLLM](https://docs.vllm.ai/en/latest/index.html).

The configured model (`model`) is pulled from HuggingFace using the provided HuggingFace access token(`HF_TOKEN`).

The access to the deployed model is secured with the configured `LLM_API_KEY`.

The service can be accessed publicly using the address [https://llm.a.b.c.d.nip.io](https://llm.a.b.c.d.nip.io), 
where a.b.c.d is the public IP address of the load balancer associated with the NGINX ingress controller.

### Qdrant

[Qdrant Vector DB](https://qdrant.tech/documentation/) is deployed in stand-alone mode to store the embeddings required the RAG pipeline.

## How to deploy?

1. Deploy via ORM
- Create a new stack
- Upload the TF configuration files
- Configure the variables
- Apply

2. Local deployment

- Create a file called `terraform.auto.tfvars` with the required values.

```
# ORM injected values

region            = "eu-frankfurt-1"
tenancy_ocid      = "ocid1.tenancy.oc1..aaaaaaaaiyavtwbz4kyu7g7b6wglllccbflmjx2lzk5nwpbme44mv54xu7dq"
compartment_ocid  = "ocid1.compartment.oc1..aaaaaaaaqi3if6t4n24qyabx5pjzlw6xovcbgugcmatavjvapyq3jfb4diqq"

# OKE Terraform module values
create_iam_resources     = false
create_iam_tag_namespace = false
ssh_public_key           = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDU+UhFcOrrOEYim254Uy9i6ZT3M4goH+poSYlWmylnvvAcryJg54kMRWv3rV/Xx6nxbyjukDXGQTYj0Q5caSlGwdg2e4yVLxLRUQbIacW5K468f8EkfNoYNDGrmARvhybWSQvLk5EHR7DlBXQXCmS5yiO7gl+5PFncnNlNRhhwujuHE5nEkdAXSLrAL+NE2hZxlAgpEV0X9Zu9lyl9UT2kgekQ0mr5eDsJMKNoqBoWnhaXEQuCJ4Bw7rJy55GNmwLS/KtpQRKSuAlTRG7pLEL4nc1BOvPQTfx/+gMcT6+NL1yxUusXXuqfk377loeyjiKK+lDrG6pU2gu6+YX68/dn ssh-key-2021-07-20"

## NodePool with non-GPU shape is created by default with size 1
simple_np_size = 1
simple_np_flex_shape = {
    "instanceShape" = "VM.Standard.E5.Flex"
    "ocpus"         = 2
    "memory"        = 12
  }

## NodePool with GPU shape is created by default with size 0
gpu_np_size = 1
gpu_np_shape = "VM.GPU.A10.1"

cluster_name         = "oke"
vcn_name             = "oke-vcn"
compartment_id       = "ocid1.compartment.oc1..aaaaaaaaqi3if6t4n24qyabx5pjzlw6xovcbgugcmatavjvapyq3jfb4diqq"
jupyter_admin_user   = "andrei"
jupyter_admin_password = "<my-secure-password>"
HF_TOKEN               = "<my-hugging-face-token>"
LLM_API_KEY            = "<my-secure-api-key>"
```

- Execute the commands

```
terraform init
terraform plan
terraform apply
```

## Known Issues

If `terraform destroy` fails, manually remove the LoadBalancer resource configured for the Nginx Ingress Controller.

After `terrafrom destroy`, the block volumes corresponding to the PVCs used by the applications in the cluster won't be removed. You have to manually remove them.