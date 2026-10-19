# Habilitação de TLS_RSA no Amplify Fusion Data Plane 1.16.2

Este documento descreve exclusivamente a solução com ConfigMap utilizada para permitir que o Inbound Worker e o Orchestrator negociem o cipher suite `TLS_RSA_WITH_AES_256_GCM_SHA384`.

## Contexto

A implementação utiliza somente a alternativa de arquivo de segurança indicada pela Axway. A lista de algoritmos não é informada diretamente em `JAVA_OPTS` e `JAVA_TOOL_OPTIONS` não é utilizado.

1. Um ConfigMap contém um arquivo adicional `java.security`.
2. Um init container copia o arquivo para um volume `emptyDir` compartilhado.
3. O Inbound Worker e o Orchestrator montam o arquivo.
4. `JAVA_OPTS` referencia o arquivo por meio de um argumento sem espaços:

   ```text
   -Djava.security.properties=/etc/fusion-java-security/java.security
   ```

## Pré-requisitos

- Helm configurado.
- Acesso ao cluster Kubernetes.
- Repositório Helm da Axway configurado como `axway-cft`.
- Chart Amplify Fusion versão `1.16.2` disponível localmente.
- Arquivo de valores da instalação disponível como `values.yaml` na raiz.

Se for necessário obter novamente o chart original:

```powershell
helm pull axway-cft/amplifyfusion-helm-prod-amplify-fusion `
  --version 1.16.2 `
  --untar
```

Os exemplos seguintes consideram que o chart está em `./amplify-fusion`.

## 1. Criar o ConfigMap

Crie `amplify-fusion/templates/common/configmap-java-security.yaml`:

```yaml
{{- if or .Values.inboundWorker.enabled .Values.orchestrator.enabled }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-java-security
  namespace: {{ .Release.Namespace }}
data:
  java.security: |-
    # TLS_RSA is intentionally omitted to allow TLS_RSA_WITH_AES_256_GCM_SHA384.
    jdk.tls.disabledAlgorithms=SSLv3, TLSv1, TLSv1.1, DTLSv1.0, RC4, DES, MD5withRSA, DH keySize < 1024, EC keySize < 224, 3DES_EDE_CBC, anon, NULL, ECDH, include jdk.disabled.namedCurves
{{- end }}
```

O nome renderizado para o release utilizado neste ambiente será `fusion-data-plane-java-security`.

## 2. Alterar o values.yaml

Mantenha as opções JVM existentes e acrescente o arquivo de segurança aos dois componentes.

Inbound Worker:

```yaml
inboundWorker:
  javaOpts: >-
    -XX:+UseG1GC -XX:-G1PeriodicGCInvokesConcurrent -XX:G1PeriodicGCInterval=300000
    -XX:MaxRAMPercentage=75
    -Djava.security.properties=/etc/fusion-java-security/java.security
```

Orchestrator:

```yaml
orchestrator:
  javaOpts: >-
    -XX:+UseG1GC -XX:-G1PeriodicGCInvokesConcurrent -XX:G1PeriodicGCInterval=300000
    -XX:MaxRAMPercentage=75 -Djdk.virtualThreadScheduler.parallelism=64
    -Djava.security.properties=/etc/fusion-java-security/java.security
```

## 3. Alterar os Deployments

As alterações devem ser aplicadas nos arquivos:

- `amplify-fusion/templates/inbound-worker/deployment.yaml`
- `amplify-fusion/templates/orchestrator/deployment.tpl`

### 3.1 Adicionar o checksum

Em `spec.template.metadata.annotations`, adicione:

```yaml
annotations:
  checksum/java-security: {{ include (print $.Template.BasePath "/common/configmap-java-security.yaml") . | sha256sum }}
```

Se já existirem `podAnnotations`, mantenha-as abaixo do checksum:

```yaml
metadata:
  annotations:
    checksum/java-security: {{ include (print $.Template.BasePath "/common/configmap-java-security.yaml") . | sha256sum }}
  {{- with .Values.inboundWorker.podAnnotations }}
    {{- toYaml . | nindent 8 }}
  {{- end }}
```

No Orchestrator, substitua `inboundWorker.podAnnotations` por `orchestrator.podAnnotations`.

O checksum garante que uma alteração posterior no ConfigMap gere automaticamente um novo rollout.

### 3.2 Adicionar o init container

Adicione um segundo item em `spec.template.spec.initContainers`, depois do init container original.

No Inbound Worker:

```yaml
- name: java-security-init
  securityContext:
    {{- toYaml .Values.inboundWorker.securityContext | nindent 12 }}
  image: "{{ default .Values.global.image.repository .Values.global.alpinetools.image.repository }}/{{ .Values.global.alpinetools.image.name }}:{{ .Values.global.alpinetools.image.tag }}"
  imagePullPolicy: {{ .Values.global.image.pullPolicy }}
  command:
    - /bin/sh
    - -c
    - cp /java-security-config/java.security /java-security/java.security
  volumeMounts:
    - name: fusion-java-security-config
      mountPath: /java-security-config
      readOnly: true
    - name: fusion-java-security
      mountPath: /java-security
```

No Orchestrator, utilize `.Values.orchestrator.securityContext`.

Ao inserir o bloco diretamente nos templates, preserve a indentação do item existente em `initContainers`.

### 3.3 Montar o arquivo no container principal

Em `volumeMounts` do container principal dos dois componentes, adicione:

```yaml
- name: fusion-java-security
  mountPath: /etc/fusion-java-security/java.security
  subPath: java.security
  readOnly: true
```

### 3.4 Declarar os volumes

Em `spec.template.spec.volumes` dos dois componentes, adicione:

```yaml
- name: fusion-java-security-config
  configMap:
    name: {{ .Release.Name }}-java-security
- name: fusion-java-security
  emptyDir: {}
```

## 4. Validar antes da instalação

Valide o chart e o `values.yaml`:

```powershell
helm lint .\amplify-fusion -f .\values.yaml
```

Para renderizar somente os recursos afetados fora do cluster:

```powershell
helm template fusion-data-plane .\amplify-fusion `
  --namespace fusion `
  --values .\values.yaml `
  --set common.certificate.enabled=false `
  --show-only templates/common/configmap-java-security.yaml `
  --show-only templates/inbound-worker/configmap-inbound.yaml `
  --show-only templates/inbound-worker/deployment.yaml `
  --show-only templates/orchestrator/configmap.yaml `
  --show-only templates/orchestrator/deployment.yaml
```

O override `common.certificate.enabled=false` acima é utilizado somente para permitir a renderização offline do chart. Não o acrescente ao comando real de upgrade se a instalação utiliza o secret de certificado já existente.

## 5. Aplicar no cluster

É obrigatório utilizar o chart local modificado. O chart remoto `axway-cft/amplifyfusion-helm-prod-amplify-fusion` não contém o ConfigMap, os volumes nem o init container criados neste procedimento.

Execute:

```powershell
helm upgrade --install `
  --namespace fusion `
  fusion-data-plane `
  .\amplify-fusion `
  --values .\values.yaml `
  --create-namespace `
  --wait `
  --wait-for-jobs `
  --timeout 40m
```

Não é necessário informar `--version 1.16.2` ao usar o diretório local. A versão já está declarada em `amplify-fusion/Chart.yaml`.

## 6. Verificar a implantação

Confirme a criação do ConfigMap:

```powershell
kubectl get configmap fusion-data-plane-java-security --namespace fusion
```

Confira o conteúdo aplicado:

```powershell
kubectl get configmap fusion-data-plane-java-security `
  --namespace fusion `
  --output jsonpath='{.data.java\.security}'
```

Acompanhe os rollouts:

```powershell
kubectl rollout status deployment/inbound-worker-design `
  --namespace fusion --timeout=10m

kubectl rollout status deployment/orchestrator-design `
  --namespace fusion --timeout=10m
```

Confirme o arquivo dentro dos containers:

```powershell
kubectl exec --namespace fusion deployment/inbound-worker-design `
  -- cat /etc/fusion-java-security/java.security

kubectl exec --namespace fusion deployment/orchestrator-design `
  -- cat /etc/fusion-java-security/java.security
```

Confirme o `JAVA_OPTS`:

```powershell
kubectl exec --namespace fusion deployment/inbound-worker-design `
  -- printenv JAVA_OPTS

kubectl exec --namespace fusion deployment/orchestrator-design `
  -- printenv JAVA_OPTS
```

## Troubleshooting

### Pod parado em Init

Liste os pods e consulte os logs do init container:

```powershell
kubectl get pods --namespace fusion

kubectl logs --namespace fusion <NOME_DO_POD> `
  --container java-security-init
```

Confira volumes, mounts e eventos:

```powershell
kubectl describe pod --namespace fusion <NOME_DO_POD>
```

### Erro de arquivo não encontrado

Verifique se o `JAVA_OPTS` aponta exatamente para:

```text
/etc/fusion-java-security/java.security
```

Confira também se o ConfigMap foi criado com o nome derivado do release:

```text
<RELEASE>-java-security
```

Para este ambiente, o nome é `fusion-data-plane-java-security`.

### O upgrade não contém o ConfigMap

Confirme que o comando utiliza `./amplify-fusion` como chart. Se o comando utilizar `axway-cft/amplifyfusion-helm-prod-amplify-fusion`, as alterações locais serão ignoradas.

Verifique o manifesto armazenado pelo Helm:

```powershell
helm get manifest fusion-data-plane --namespace fusion |
  Select-String 'fusion-data-plane-java-security'
```

## Considerações de segurança

- `TLS_RSA_WITH_AES_256_GCM_SHA384` utiliza troca de chaves RSA estática e não oferece forward secrecy.
- TLS 1.0, TLS 1.1, SSLv3 e os demais algoritmos fracos presentes na lista continuam desabilitados.
- Como a lista não contém `TLS_RSA`, outros cipher suites `TLS_RSA` suportados pela JVM também podem se tornar elegíveis. A negociação ainda depende dos ciphers oferecidos pelo servidor remoto e pela aplicação.
- A alteração deve ser testada e limitada aos ambientes que realmente necessitam interoperar com o endpoint legado.

## Reversão

Para reverter completamente:

1. Remova `-Djava.security.properties=/etc/fusion-java-security/java.security` dos dois `javaOpts`.
2. Remova `configmap-java-security.yaml`.
3. Remova os init containers `java-security-init`.
4. Remova os mounts e volumes `fusion-java-security-config` e `fusion-java-security`.
5. Remova as annotations `checksum/java-security`.
6. Execute novamente o `helm upgrade` usando o chart resultante.

Não volte diretamente ao chart remoto enquanto o `values.yaml` ainda apontar para o arquivo customizado, pois o chart remoto não criará nem montará esse arquivo.
