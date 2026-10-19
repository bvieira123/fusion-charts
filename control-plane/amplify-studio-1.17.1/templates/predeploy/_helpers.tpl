{{- define "predeploy.name" -}}
{{- default "predeploy" .Values.predeploy.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified predeploy name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "predeploy.fullname" -}}
{{- if .Values.predeploy.fullnameOverride }}
{{- .Values.predeploy.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "predeploy" .Values.predeploy.nameOverride }}
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
{{- define "predeploy.labels" -}}
{{ include "ctlplane.labels" . }}
{{ include "predeploy.selectorLabels" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "predeploy.selectorLabels" -}}
app.kubernetes.io/name: {{ include "predeploy.name" . }}
app: {{ include "predeploy.appName" . }}
ampint.ctlplane: {{ include "predeploy.name" . }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "predeploy.serviceAccountName" -}}
{{- if .Values.predeploy.serviceAccount.enabled }}
{{- default (include "predeploy.fullname" .) .Values.predeploy.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.predeploy.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Custom templates start here
*/}}
{{- define "predeploy.appName" -}}
{{- $name := default "predeploy" .Values.predeploy.nameOverride -}}
{{- $env := default "predeploy" .Values.global.appEnv -}}
{{- printf "%s-%s" $name $env  | trunc 63 | trimSuffix "-" -}}
{{- end }}
