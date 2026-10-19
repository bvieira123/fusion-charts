{{- define "orchestrator.name" -}}
{{- default "orchestrator" .Values.orchestrator.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "orchestrator.fullname" -}}
{{- if .Values.orchestrator.fullnameOverride }}
{{- .Values.orchestrator.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "orchestrator" .Values.orchestrator.nameOverride }}
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
{{- define "orchestrator.labels" -}}
{{ include "dataplane.labels" . }}
{{ include "orchestrator.selectorLabels" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "orchestrator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "orchestrator.name" . }}
app: {{ include "orchestrator.appName" . }}
dplane: "orchestrator"
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "orchestrator.serviceAccountName" -}}
{{- if .Values.orchestrator.serviceAccount.enabled }}
{{- default (include "orchestrator.fullname" .) .Values.orchestrator.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.orchestrator.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Custom templates start here
*/}}

{{- define "orchestrator.appName" -}}
{{- $name := default "orchestrator" .Values.orchestrator.nameOverride -}}
{{- $env := default "orchestrator" .Values.global.appEnv -}}
{{- printf "%s-%s" $name $env  | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Image name
*/}}
{{- define "image.finalname" -}}
{{- printf "%s/%s:%s" .Values.orchestrator.image.server "orchestrator" .Chart.AppVersion }}
{{- end }}

{{/*
Cpu min request
*/}}
{{- define "microserviceChart.minCpuUnits" -}}
"
{{- index .Values.orchestrator.valuesPerEnvironment.cpuUnits ((pluck .Values.orchestrator.environment .Values.orchestrator.environments | first | default .Values.orchestrator.environments.sandbox) | int) -}}
m"
{{- end }}