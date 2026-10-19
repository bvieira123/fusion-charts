{{- define "pep-server.name" -}}
{{- default "pep-server" .Values.pepServer.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "pep-server.fullname" -}}
{{- if .Values.pepServer.fullnameOverride }}
{{- .Values.pepServer.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "pep-server" .Values.pepServer.nameOverride }}
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
{{- define "pep-server.labels" -}}
{{ include "dataplane.labels" . }}
{{ include "pep-server.selectorLabels" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "pep-server.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pep-server.name" . }}
app: {{ include "pep-server.appName" . }}
dplane: "pep-server"
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "pep-server.serviceAccountName" -}}
{{- if .Values.pepServer.serviceAccount.enabled }}
{{- default (include "pep-server.fullname" .) .Values.pepServer.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.pepServer.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Custom templates start here
*/}}

{{- define "pep-server.appName" -}}
{{- $name := default "pep-server" .Values.pepServer.nameOverride -}}
{{- $env := default "pep-server" .Values.global.appEnv -}}
{{- printf "%s-%s" $name $env  | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Image name
*/}}
{{- define "image.finalname" -}}
{{- printf "%s/%s:%s" .Values.pepServer.image.server "pep-server" .Chart.AppVersion }}
{{- end }}

{{/*
Cpu min request
*/}}
{{- define "microserviceChart.minCpuUnits" -}}
"
{{- index .Values.pepServer.valuesPerEnvironment.cpuUnits ((pluck .Values.pepServer.environment .Values.pepServer.environments | first | default .Values.pepServer.environments.sandbox) | int) -}}
m"
{{- end }}