{{- define "orchestrator.podDisruptionBudget" -}}
{{- if .Values.orchestrator.podDisruptionBudget.enabled -}}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ template "orchestrator.appName" . }}
  namespace: {{ .Release.Namespace }}
spec:
  minAvailable: {{ .Values.orchestrator.podDisruptionBudget.minPods }}
  selector:
    matchLabels:
      {{- include "orchestrator.selectorLabels" . | nindent 6 }}
{{- end }}
{{- end -}}