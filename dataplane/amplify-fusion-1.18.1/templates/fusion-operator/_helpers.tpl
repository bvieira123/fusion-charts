{{- define "fusionOperator.name" -}}
{{- default "fusion-operator" .Values.fusionOperator.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "fusionOperator.fullname" -}}
{{- if .Values.fusionOperator.fullnameOverride }}
{{- .Values.fusionOperator.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "fusionOperator" .Values.fusionOperator.nameOverride }}
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
{{- define "fusionOperator.labels" -}}
{{ include "dataplane.labels" . }}
{{ include "fusionOperator.selectorLabels" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "fusionOperator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "fusionOperator.name" . }}
app: {{ include "fusionOperator.appName" . }}
dplane: "fusion-operator"
{{- end }}

{{- define "fusionOperator.appName" -}}
{{- $name := default "fusion-operator" .Values.fusionOperator.nameOverride -}}
{{- $env := default "fusion-operator" .Values.appEnv -}}
{{- printf "%s-%s" $name $env  | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "fusionOperator.serviceAccountName" -}}
{{- if .Values.fusionOperator.serviceAccount.enabled }}
{{- default (include "fusionOperator.fullname" .) .Values.fusionOperator.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.fusionOperator.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the name of the service account for jobs to use
*/}}
{{- define "fusionOperator.job.serviceAccountName" -}}
{{- if .Values.fusionOperator.job.serviceAccount.enabled }}
{{- default (include "fusionOperator.fullname" .) .Values.fusionOperator.job.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.fusionOperator.job.serviceAccount.name }}
{{- end }}
{{- end }}