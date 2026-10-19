{{/*
Expand the name of the chart.
*/}}
{{- define "marketplace-agent.name" -}}
{{- default "marketplace-agent" .Values.marketplaceAgent.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "marketplace-agent.fullname" -}}
{{- if .Values.marketplaceAgent.fullnameOverride }}
{{- .Values.marketplaceAgent.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "marketplace-agent" .Values.marketplaceAgent.nameOverride }}
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
{{- define "marketplace-agent.labels" -}}
{{ include "ctlplane.labels" . }}
{{ include "marketplace-agent.selectorLabels" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "marketplace-agent.selectorLabels" -}}
ampint.ctlplane: {{ include "marketplace-agent.name" . }}
app: {{ include "marketplace-agent.appName" . }}
release: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "marketplace-agent.serviceAccountName" -}}
{{- if .Values.marketplaceAgent.serviceAccount.enabled }}
{{- default (include "marketplace-agent.fullname" .) .Values.marketplaceAgent.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.marketplaceAgent.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Custom templates start here 
*/}}

{{- define "marketplace-agent.appName" -}}
{{- $name := default "marketplace-agent" .Values.marketplaceAgent.nameOverride -}}
{{- $env := default "marketplace-agent" .Values.global.appEnv -}}
{{- printf "%s-%s" $name $env  | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Image name
*/}}
{{- define "image.finalname" -}}
{{- printf "%s/%s:%s" .Values.marketplaceAgent.image.server "marketplace-agent" .Chart.AppVersion }}
{{- end }}
