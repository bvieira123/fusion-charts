{{- define "inbound-worker.name" -}}
{{- default "inbound-worker" .Values.inboundWorker.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "inbound-worker.fullname" -}}
{{- if .Values.inboundWorker.fullnameOverride }}
{{- .Values.inboundWorker.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "inbound-worker" .Values.inboundWorker.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}


{{/*
Common labels
*/}}
{{- define "inbound-worker.labels" -}}
{{ include "dataplane.labels" . }}
{{ include "inbound-worker.selectorLabels" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "inbound-worker.selectorLabels" -}}
app.kubernetes.io/name: {{ include "inbound-worker.name" . }}
app: {{ include "inbound-worker.appName" . }}
dplane: "inbound-worker"
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "inbound-worker.serviceAccountName" -}}
{{- if .Values.inboundWorker.serviceAccount.enabled }}
{{- default (include "inbound-worker.fullname" .) .Values.inboundWorker.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.inboundWorker.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Custom templates start here 
*/}}

{{- define "inbound-worker.appName" -}}
{{- $name := default "inbound-worker" .Values.inboundWorker.nameOverride -}}
{{- $env := default "inbound-worker" .Values.appEnv -}}
{{- printf "%s-%s" $name $env  | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Image name
*/}}
{{- define "image.finalname" -}}
{{- printf "%s/%s:%s" .Values.inboundWorker.image.server "inbound-worker" .Chart.AppVersion }}
{{- end }}

{{/*
Salesforce configmap entries — optional overrides, omitted when empty.
Usage: {{- include "inbound-worker.salesforceConfigmap" .Values.inboundWorker | nindent 2 }}
*/}}
{{- define "inbound-worker.salesforceConfigmap" -}}
{{- $sf := .salesforce }}
{{- if not (eq $sf.pubsub_api_url "") }}
EVENT_SALESFORCE_PUBSUB_API_URL: {{ $sf.pubsub_api_url | quote }}
{{- end }}
{{- if not (eq $sf.retry_initial_backoff_duration "") }}
EVENT_SALESFORCE_RETRY_INITIAL_BACKOFF: {{ $sf.retry_initial_backoff_duration | quote }}
{{- end }}
{{- if not (eq $sf.retry_max_backoff_duration "") }}
EVENT_SALESFORCE_RETRY_MAX_BACKOFF: {{ $sf.retry_max_backoff_duration | quote }}
{{- end }}
{{- if not (eq $sf.retry_status_code_list "") }}
EVENT_SALESFORCE_RETRY_GRPC_STATUS_CODES: {{ $sf.retry_status_code_list | quote }}
{{- end }}
{{- if not (eq $sf.grpc_keepalive_time_seconds "") }}
EVENT_SALESFORCE_GRPC_KEEPALIVE_TIME: {{ $sf.grpc_keepalive_time_seconds | quote }}
{{- end }}
{{- if not (eq $sf.grpc_keepalive_timeout_seconds "") }}
EVENT_SALESFORCE_GRPC_KEEPALIVE_TIMEOUT: {{ $sf.grpc_keepalive_timeout_seconds | quote }}
{{- end }}
{{- if not (eq $sf.idle_watchdog_threshold_seconds "") }}
EVENT_SALESFORCE_IDLE_WATCHDOG_THRESHOLD: {{ $sf.idle_watchdog_threshold_seconds | quote }}
{{- end }}
{{- end }}

{{/*
Cpu min request
*/}}
{{- define "microserviceChart.minCpuUnits" -}}
"
{{- index .Values.inboundWorker.valuesPerEnvironment.cpuUnits ((pluck .Values.inboundWorker.environment .Values.inboundWorker.environments | first | default .Values.inboundWorker.environments.sandbox) | int) -}}
m"
{{- end }}