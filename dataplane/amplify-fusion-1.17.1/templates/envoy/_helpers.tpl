{{/*
Envoy.
*/}}
{{- define "envoy.name" -}}
{{- default "envoy" .Values.envoy.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "envoy.fullname" -}}
{{- if .Values.envoy.fullnameOverride }}
{{- .Values.envoy.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "envoy" .Values.envoy.nameOverride }}
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
{{- define "envoy.labels" -}}
{{ include "dataplane.labels" . }}
{{ include "envoy.selectorLabels" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "envoy.selectorLabels" -}}
app.kubernetes.io/name: {{ include "envoy.name" . }}
app: {{ include "envoy.appName" . }}
dplane: "envoy"
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "envoy.serviceAccountName" -}}
{{- if .Values.envoy.serviceAccount.create }}
{{- default (include "envoy.fullname" .) .Values.envoy.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.envoy.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "envoy.appName" -}}
{{- $name := default "envoy" .Values.envoy.nameOverride -}}
{{- $env := default "envoy" .Values.global.appEnv -}}
{{- printf "%s-%s" $name $env  | trunc 63 | trimSuffix "-" -}}
{{- end }}