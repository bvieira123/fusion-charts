{{- define "fluent-bit.name" -}}
{{- default "fluent-bit" .Values.fluentBit.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "fluent-bit.appName" -}}
{{- $name := default "fluent-bit" .Values.fluentBit.nameOverride -}}
{{- $env := default "fluent-bit" .Values.global.appEnv -}}
{{- printf "%s-%s" $name $env  | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Common labels
*/}}
{{- define "fluent-bit.labels" -}}
{{ include "ctlplane.labels" . }}
{{ include "fluent-bit.selectorLabels" . }}
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "fluent-bit.selectorLabels" -}}
app.kubernetes.io/name: {{ include "fluent-bit.name" . }}
app: {{ include "fluent-bit.appName" . }}
ampint.ctlplane: "fluent-bit"
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
{{ default .Values.global.image.repository .Values.fluentBit.image.repository }}/{{ .Values.fluentBit.image.name }}:{{ .Values.fluentBit.image.buildTag | default .Chart.AppVersion }}
{{- end -}}

