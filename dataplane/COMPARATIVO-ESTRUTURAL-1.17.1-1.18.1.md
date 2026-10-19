# Amplify Fusion Data Plane — comparativo 1.17.1 → 1.18.1

## Resumo quantitativo

Comparação dos charts originais, antes da customização TLS/RSA:

- 1.17.1: 160 arquivos em 18 diretórios.
- 1.18.1: 172 arquivos em 20 diretórios.
- 79 arquivos idênticos, 81 alterados, 12 adicionados e nenhum removido.
- `values.yaml`: 994 valores-folha na 1.17.1 e 1.098 na 1.18.1.
- 841 caminhos permaneceram, 153 deixaram o local antigo e 257 foram adicionados.

## Reestruturação do values

A 1.18.1 remove a maior parte dos agrupamentos `global.*` e `common.*` e promove ou reorganiza essas configurações:

| 1.17.1 | 1.18.1 |
|---|---|
| `global.appEnv` | `appEnv` |
| `global.clusterKey` | `clusterKey` |
| `global.external_domain` | `external_domain` |
| `global.ctlplane_domain` | `ctlplane_domain` |
| `global.image.*` | `image.*` |
| `common.admin_email` e demais opções de e-mail | `email.*` |
| `common.clusterDetails` | `secrets.clusterDetails` |
| `common.datagridCredentials` | `secrets.datagrid` |
| `common.persistence`, `efs`, `nfs`, `pvc`, `azfiles` | `storage.*` |
| `common.certificate` e `ssh_certificate` | `tls.domainCertificate` e `tls.sshCertificate` |
| `global.encryptAtRest` e `global.kms` | `encryption.*` |
| `common.logFileEnabled` e `logJsonEnabled` | `logging.*` |
| `common.openTelemetry` | `openTelemetry` |

Também houve mudança de representação nos secrets gerenciados pelo chart: vários templates passaram de `Secret.data` (base64) para `Secret.stringData` (texto). O migrador faz a conversão quando o secret não é externo.

## Novos templates

A 1.18.1 acrescenta:

- secrets de credenciais AWS separados para Inbound Worker e Orchestrator;
- serviço headless do PEP Server;
- secret para o keystore Local CRK;
- controlador de failover do Valkey, com Deployment, RBAC, ServiceAccount, PDB e NetworkPolicy;
- CronJob de rotação de logs do Valkey.

## Mudanças operacionais relevantes

- As imagens dos componentes foram atualizadas para 1.18.1; Envoy, Fluent Bit, Fusion Operator, Valkey e SPIRE também receberam novas versões.
- As portas WebSocket foram retiradas dos Services do Envoy e Orchestrator; o servidor WebSocket do Orchestrator passa a vir habilitado por padrão e ganhou limites adicionais.
- Os valores padrão de autoscaling mudaram de forma significativa. Como o cluster somente customizava a ativação dos HPAs, os novos thresholds da 1.18.1 foram mantidos.
- O request padrão de CPU do Orchestrator mudou de `100m` para `1000m`. O valor customizado atual do cluster foi preservado no values migrado.
- O modo do cliente Valkey deixou de ser fixamente `clustered` e agora pode ser escolhido automaticamente.
- O cluster atual usa Valkey interno com um nó. Na 1.18.1 isso exige explicitamente `replicasPerMaster: 0`; o migrador aplica essa compatibilidade e deixa `deployment_model` vazio para a seleção automática de `standalone`.
- As configurações obsoletas `predeploy`, `postdeploy` e `sinkAgent.service`, sem consumidores nos templates, não foram levadas para o arquivo novo.

## Migração executada

O arquivo `dataplane-1.18.1.yaml` parte integralmente dos defaults da nova versão. Somente customizações reais do cluster foram sobrepostas, além das traduções necessárias para os novos caminhos. Isso evita manter tags de imagem e defaults antigos por acidente.

Foram preservados, entre outros:

- ambiente, domínio, cluster key e image pull secret;
- endereços e autenticação de e-mail;
- nomes e uso dos secrets externos `frommail`, `cluster-details` e `datagrid-credentials`;
- habilitação dos HPAs e recursos customizados por workload;
- Service do Envoy;
- tamanho e recursos do Valkey.

`common.certificate.generate.enabled` não foi migrado porque o template 1.17.1 não consultava esse campo. O comportamento efetivo vinha de `common.certificate.enabled`; ele foi traduzido para `tls.domainCertificate.manuallyCreated`.

## Customização TLS/RSA

A solução descrita em `CONFIGURACAO-TLS-RSA.md` foi adaptada ao layout da 1.18.1:

- ConfigMap `<release>-java-security` com a política que permite a suíte RSA requerida;
- init container em Inbound Worker e Orchestrator;
- volume temporário e montagem de `java.security` nos dois workloads;
- argumento `-Djava.security.properties=/etc/fusion-java-security/java.security` nos dois `JAVA_OPTS`;
- checksum do ConfigMap no pod template para provocar rollout quando a política mudar;
- defaults correspondentes atualizados no `values.yaml` e no `values.schema.json`.

## Validação local

- `helm lint`: aprovado.
- `helm template`: 55 recursos renderizados com sucesso usando credenciais fictícias somente para evitar os lookups de secrets externos durante a validação offline.
- Dois init containers e duas montagens TLS/RSA foram confirmados no manifesto renderizado.
- Nenhum comando de instalação ou alteração no cluster foi executado.
