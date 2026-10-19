{{/*
Expand the name of the chart.
*/}}
{{- define "hazelcast.name" -}}
{{- default "hazelcast" .Values.hazelcast.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified hazelcast name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "hazelcast.fullname" -}}
{{- if .Values.hazelcast.fullnameOverride }}
{{- .Values.hazelcast.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "hazelcast" .Values.hazelcast.nameOverride }}
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
{{- define "hazelcast.labels" -}}
{{ include "ctlplane.labels" . }}
{{ include "hazelcast.selectorLabels" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "hazelcast.selectorLabels" -}}
app: {{ include "hazelcast.appName" . }}
ampint.ctlplane: {{ include "hazelcast.name" . }}
release: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "hazelcast.serviceAccountName" -}}
{{- if .Values.hazelcast.serviceAccount.enabled }}
{{- default (include "hazelcast.fullname" .) .Values.hazelcast.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.hazelcast.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Custom templates start here 
*/}}

{{- define "hazelcast.appName" -}}
{{- $name := default "hazelcast" .Values.hazelcast.nameOverride -}}
{{- $env := default "hazelcast" .Values.global.appEnv -}}
{{- printf "%s-%s" $name $env  | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Image name
*/}}
{{- define "image.finalname" -}}
{{- printf "%s/%s:%s" .Values.hazelcast.image.server "hazelcast" .Chart.AppVersion }}
{{- end }}
