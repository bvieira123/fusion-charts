{{/*
Expand the name of the chart.
*/}}
{{- define "auditservice.name" -}}
{{- default "auditservice" .Values.auditservice.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified auditservice name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "auditservice.fullname" -}}
{{- if .Values.auditservice.fullnameOverride }}
{{- .Values.auditservice.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "auditservice" .Values.auditservice.nameOverride }}
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
{{- define "auditservice.labels" -}}
{{ include "ctlplane.labels" . }}
{{ include "auditservice.selectorLabels" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "auditservice.selectorLabels" -}}
app: {{ include "auditservice.appName" . }}
ampint.ctlplane: {{ include "auditservice.name" . }}
release: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "auditservice.serviceAccountName" -}}
{{- if .Values.auditservice.serviceAccount.enabled }}
{{- default (include "auditservice.fullname" .) .Values.auditservice.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.auditservice.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Custom templates start here 
*/}}

{{- define "auditservice.appName" -}}
{{- $name := default "auditservice" .Values.auditservice.nameOverride -}}
{{- $env := default "auditservice" .Values.appEnv -}}
{{- printf "%s-%s" $name $env  | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Image name
*/}}
{{- define "image.finalname" -}}
{{- printf "%s/%s:%s" .Values.auditservice.image.server "auditservice" .Chart.AppVersion }}
{{- end }}
