{{/*
SPIRE namespace — shared across all dataplane installs in the same cluster.
*/}}

{{/*
Annotation applied to all SPIRE resources to prevent helm uninstall from deleting them.
SPIRE is shared infrastructure — other dataplanes may still be using it when one is removed.
Manual cleanup is required once all dataplanes have been uninstalled.
*/}}
{{- define "spire.keepAnnotation" -}}
helm.sh/resource-policy: keep
{{- end }}
{{- define "spire.namespace" -}}
{{- .Values.zerotrust.providers.spire.namespace | default "spire" }}
{{- end }}

{{/*
SPIRE Server helpers
*/}}
{{- define "spire-server.name" -}}
{{- default "spire-server" .Values.zerotrust.providers.spire.server.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "spire-server.fullname" -}}
{{- if .Values.zerotrust.providers.spire.server.fullnameOverride }}
{{- .Values.zerotrust.providers.spire.server.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-spire-server" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "spire-server.labels" -}}
{{ include "dataplane.labels" . }}
{{ include "spire-server.selectorLabels" . }}
{{- end }}

{{- define "spire-server.selectorLabels" -}}
app.kubernetes.io/name: {{ include "spire-server.name" . }}
dplane: "spire-server"
{{- end }}

{{- define "spire-server.serviceAccountName" -}}
{{- if .Values.zerotrust.providers.spire.server.serviceAccount.enabled }}
{{- default (include "spire-server.fullname" .) .Values.zerotrust.providers.spire.server.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.zerotrust.providers.spire.server.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
SPIRE Registrar helpers (sidecar in spire-server pod)
*/}}
{{- define "spire-registrar.name" -}}
{{- default "spire-registrar" .Values.zerotrust.providers.spire.server.registrar.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
SPIRE Agent helpers
*/}}
{{- define "spire-agent.name" -}}
{{- default "spire-agent" .Values.zerotrust.providers.spire.agent.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "spire-agent.fullname" -}}
{{- if .Values.zerotrust.providers.spire.agent.fullnameOverride }}
{{- .Values.zerotrust.providers.spire.agent.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-spire-agent" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "spire-agent.labels" -}}
{{ include "dataplane.labels" . }}
{{ include "spire-agent.selectorLabels" . }}
{{- end }}

{{- define "spire-agent.selectorLabels" -}}
app.kubernetes.io/name: {{ include "spire-agent.name" . }}
dplane: "spire-agent"
{{- end }}

{{- define "spire-agent.serviceAccountName" -}}
{{- if .Values.zerotrust.providers.spire.agent.serviceAccount.enabled }}
{{- default (include "spire-agent.fullname" .) .Values.zerotrust.providers.spire.agent.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.zerotrust.providers.spire.agent.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
SPIFFE-ID helpers — emit `spiffe://<trustDomain>/ns/<namespace>/sa/<sa>` URIs for the
dataplane workloads. SPIFFE is a SPIRE-territory concept; these helpers belong here
rather than in the generic templates/_helpers.tpl. Consumers (envoy/configmap.yaml,
pep-server/configmap-pep-server.yaml) are already gated by `zerotrust.enabled`, so calling
them is safe — they only render when SPIRE is the active provider.
*/}}
{{- define "trustDomain.spiffeId" -}}
{{- printf "spiffe://%s" .Values.zerotrust.providers.spire.trustDomain }}
{{- end }}

{{- define "envoy.spiffeId" -}}
{{- printf "spiffe://%s/ns/%s/sa/%s" .Values.zerotrust.providers.spire.trustDomain .Release.Namespace .Values.envoy.serviceAccount.name }}
{{- end }}

{{- define "orchestrator.spiffeId" -}}
{{- printf "spiffe://%s/ns/%s/sa/%s" .Values.zerotrust.providers.spire.trustDomain .Release.Namespace .Values.orchestrator.serviceAccount.name }}
{{- end }}

{{- define "pep-server.spiffeId" -}}
{{- printf "spiffe://%s/ns/%s/sa/%s" .Values.zerotrust.providers.spire.trustDomain .Release.Namespace .Values.pepServer.serviceAccount.name }}
{{- end }}

{{- define "inbound-worker.spiffeId" -}}
{{- printf "spiffe://%s/ns/%s/sa/%s" .Values.zerotrust.providers.spire.trustDomain .Release.Namespace .Values.inboundWorker.serviceAccount.name }}
{{- end }}

{{/*
SPIRE provider implementations of the generic zero-trust dispatch contract
(see templates/_helpers.tpl `amplify-fusion.zerotrust.*` for the contract).

All three helpers receive the chart context directly.

Consumers that need PEM files on disk (valkey, fluent-bit) keep their cert-refresh
sidecar inline — they are SPIRE-aware by necessity since the sidecar's mount names
must match what the consumer's main container reads.
*/}}

{{- define "amplify-fusion.zerotrust.provider.spire.workloadVolumes" -}}
- name: {{ .Values.zerotrust.providers.spire.workload.volumeName }}
  hostPath:
    path: {{ .Values.zerotrust.providers.spire.workload.socketHostPath }}
    type: DirectoryOrCreate
{{- end -}}

{{- define "amplify-fusion.zerotrust.provider.spire.workloadVolumeMounts" -}}
- name: {{ .Values.zerotrust.providers.spire.workload.volumeName }}
  mountPath: {{ .Values.zerotrust.providers.spire.workload.mountPath }}
  readOnly: true
{{- end -}}

{{- define "amplify-fusion.zerotrust.provider.spire.initContainers" -}}
{{- if .Values.zerotrust.providers.spire.workload.waitInitContainer.enabled }}
- name: wait-for-workload-identity
  image: "{{ .Values.global.image.repository }}/{{ .Values.zerotrust.providers.spire.tools.image.name }}:{{ .Values.zerotrust.providers.spire.tools.image.buildTag }}"
  imagePullPolicy: {{ .Values.global.image.pullPolicy }}
  {{- with .Values.zerotrust.providers.spire.tools.securityContext }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  command: ["/bin/bash", "/scripts/wait-for-agent.sh"]
  env:
    - name: SPIRE_AGENT_SOCKET_PATH
      value: {{ .Values.zerotrust.providers.spire.workload.socketPath }}
    - name: AGENT_READINESS_TIMEOUT
      value: {{ .Values.zerotrust.providers.spire.tools.agentReadiness.timeoutSeconds | quote }}
  volumeMounts:
    - name: {{ .Values.zerotrust.providers.spire.workload.volumeName }}
      mountPath: {{ .Values.zerotrust.providers.spire.workload.socketHostPath }}
      readOnly: true
  {{- with .Values.zerotrust.providers.spire.tools.resources }}
  resources:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- end -}}
