ingress:
  enabled: true

deploy:
  env:
    - name: HF_TOKEN
      value: ${HF_TOKEN}
  extraArgs:
    - "--model"
    - "${model}"
    - "--max-model-len"
    - "${max_model_len}"
    - "--api-key"
    - "${LLM_API_KEY}"
  
  pvcCache:
    enabled: true