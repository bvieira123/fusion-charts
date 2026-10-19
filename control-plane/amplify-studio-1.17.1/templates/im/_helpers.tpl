{{/*
Expand the name of the chart.
*/}}
{{- define "im.name" -}}
{{- default "im" .Values.im.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "im.fullname" -}}
{{- if .Values.im.fullnameOverride }}
{{- .Values.im.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "im" .Values.im.nameOverride }}
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
{{- define "im.labels" -}}
{{ include "ctlplane.labels" . }}
{{ include "im.selectorLabels" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "im.selectorLabels" -}}
app: {{ include "im.appName" . }}
ampint.ctlplane: {{ include "im.name" . }}
release: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "im.serviceAccountName" -}}
{{- if .Values.im.serviceAccount.enabled }}
{{- default (include "im.fullname" .) .Values.im.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.im.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "im.appName" -}}
{{- $name := default "im" .Values.im.nameOverride -}}
{{- $env := default "im" .Values.global.appEnv -}}
{{- printf "%s-%s" $name $env  | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Image name
*/}}
{{- define "image.finalname" -}}
{{- printf "%s/%s:%s" .Values.im.image.server "im" .Chart.AppVersion }}
{{- end }}
