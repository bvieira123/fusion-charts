{{- define "fluent-bit.name" -}}
{{- default "fluent-bit" .Values.fluentBit.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "fluent-bit.appName" -}}
{{- $name := default "fluent-bit" .Values.fluentBit.nameOverride -}}
{{- $env := default "fluent-bit" .Values.appEnv -}}
{{- printf "%s-%s" $name $env  | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Common labels
*/}}
{{- define "fluent-bit.labels" -}}
{{ include "dataplane.labels" . }}
{{ include "fluent-bit.selectorLabels" . }}
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "fluent-bit.selectorLabels" -}}
app.kubernetes.io/name: {{ include "fluent-bit.name" . }}
app: {{ include "fluent-bit.appName" . }}
dplane: "fluent-bit"
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "fluent-bit.serviceAccountName" -}}
{{- if .Values.fluentBit.serviceAccount.enabled -}}
    {{ default (include "fluent-bit.name" .) .Values.fluentBit.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.fluentBit.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Fluent-bit image with tag/digest
*/}}
{{- define "fluent-bit.image" -}}
{{ default .Values.image.repository .Values.fluentBit.image.repository }}/{{ .Values.fluentBit.image.name }}:{{ .Values.fluentBit.image.buildTag | default .Chart.AppVersion }}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "logrotate.serviceAccountName" -}}
{{- if .Values.fluentBit.logrotate.serviceAccount.enabled -}}
    {{ default "logrotate" .Values.fluentBit.logrotate.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.fluentBit.logrotate.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Value of efs_root based on the dataplane type
*/}}
{{- define "efs_root.value" -}}
{{- $dataplaneMode := include "parent.dataplaneMode" . -}}
{{- $clusterRefId := tpl .Values.clusterRefId . -}}
{{- if eq $dataplaneMode "shared" -}}/efs{{- else -}}/efs/clusters/{{ $clusterRefId }}{{- end -}}
{{- end -}}

{{/*
Return the URL scheme to use for Fluent Bit's communication with Spire, based on whether Spire is enabled or not. If Spire is enabled, use "https", otherwise use "http".
*/}}
{{- define "fluent-bit.urlScheme" -}}
{{- if .Values.zerotrust.enabled }}https{{ else }}http{{ end -}}
{{- end }}
