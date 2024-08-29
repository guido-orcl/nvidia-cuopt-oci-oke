---
singleuser:
  defaultUrl: "/lab"
  extraEnv:
    JUPYTERHUB_SINGLEUSER_APP: "jupyter_server.serverapp.ServerApp"
  lifecycleHooks:
    postStart:
      exec:
        command:
          [
            "/bin/sh",
            "-c",
            "gitpuller https://github.com/robo-cap/llm-jupyter-notebooks.git main examples"
          ]
  cloudMetadata:
    blockWithIptables: false

hub:
  config:
    Authenticator:
      admin_users:
        - ${admin_user}
    DummyAuthenticator:
        password: '${admin_password}'
    JupyterHub:
      authenticator_class: dummy

ingress:
  enabled: true
  ingressClassName: nginx
  annotations:
    cert-manager.io/cluster-issuer: "le-clusterissuer"

proxy:
  service:
    type: ClusterIP