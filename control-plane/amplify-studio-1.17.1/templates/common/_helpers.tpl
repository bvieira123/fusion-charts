{{- define "common.name" -}}
{{- default "common" .Values.common.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "common.appName" -}}
{{- $name := default "common" .Values.common.nameOverride -}}
{{- $env := default "common" .Values.global.appEnv -}}
{{- printf "%s-%s" $name $env  | trunc 63 | trimSuffix "-" -}}
{{- end }}
