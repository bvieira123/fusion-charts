{{- define "sink-agent.name" -}}
{{- default "sink-agent" .Values.sinkAgent.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "sink-agent.fullname" -}}
{{- if .Values.sinkAgent.fullnameOverride }}
{{- .Values.sinkAgent.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "sink-agent" .Values.sinkAgent.nameOverride }}
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
{{- define "sink-agent.labels" -}}
{{ include "dataplane.labels" . }}
{{ include "sink-agent.selectorLabels" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "sink-agent.selectorLabels" -}}
app.kubernetes.io/name: {{ include "sink-agent.name" . }}
app: {{ include "sink-agent.appName" . }}
dplane: "sink-agent"
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "sink-agent.serviceAccountName" -}}
{{- if .Values.sinkAgent.serviceAccount.enabled }}
{{- default (include "sink-agent.fullname" .) .Values.sinkAgent.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.sinkAgent.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Custom templates start here 
*/}}

{{- define "sink-agent.appName" -}}
{{- $name := default "sink-agent" .Values.sinkAgent.nameOverride -}}
{{- $env := default "sink-agent" .Values.global.appEnv -}}
{{- printf "%s-%s" $name $env  | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Image name
*/}}
{{- define "image.finalname" -}}
{{- printf "%s/%s:%s" .Values.sinkAgent.image.server "sink-agent" .Chart.AppVersion }}
{{- end }}

{{/*
Cpu min request
*/}}
{{- define "microserviceChart.minCpuUnits" -}}
"
{{- index .Values.sinkAgent.valuesPerEnvironment.cpuUnits ((pluck .Values.sinkAgent.environment .Values.sinkAgent.environments | first | default .Values.sinkAgent.environments.sandbox) | int) -}}
m"
{{- end }}