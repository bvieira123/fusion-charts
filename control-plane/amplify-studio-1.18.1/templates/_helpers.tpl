{{- define "parent.ctlplaneMode" -}}
{{- (eq .Values.clusterKey "") | ternary "shared" (printf "%s" (.Values.clusterKey | b64dec | fromJson).mode) }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "ctlplane.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "ctlplane.labels" -}}
helm.sh/chart: {{ include "ctlplane.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- end }}

