{{- define "common.name" -}}
{{- default "common" .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "common.appName" -}}
{{- $name := default "common" .Values.nameOverride -}}
{{- $env := default "common" .Values.appEnv -}}
{{- printf "%s-%s" $name $env  | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Renders a livenessProbe/readinessProbe/startupProbe block, coercing its numeric
timing fields to real integers so a quoted-string override (e.g.
initialDelaySeconds: "300") still renders as an unquoted number. Kubernetes
requires int32 for these fields (not IntOrString like httpGet/tcpSocket.port,
which is left untouched here), so a quoted value passed straight through toYaml
fails API validation.
*/}}
{{- define "common.probe" -}}
{{- $probe := deepCopy . -}}
{{- range $field := list "initialDelaySeconds" "periodSeconds" "timeoutSeconds" "failureThreshold" "successThreshold" }}
{{- if hasKey $probe $field }}
{{- $_ := set $probe $field (int (get $probe $field)) }}
{{- end }}
{{- end }}
{{- toYaml $probe -}}
{{- end -}}
