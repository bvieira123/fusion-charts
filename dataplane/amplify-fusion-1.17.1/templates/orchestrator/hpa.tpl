{{- define "orchestrator.hpa" -}}
{{- if .Values.orchestrator.autoscaling.enabled  -}}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ template "orchestrator.appName" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "orchestrator.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ template "orchestrator.appName" . }}
  minReplicas: {{ .Values.orchestrator.autoscaling.minReplicas }}
  maxReplicas: {{ .Values.orchestrator.autoscaling.maxReplicas }}
  metrics:
    {{- if .Values.orchestrator.autoscaling.targetCPUUtilizationPercentage }}
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ .Values.orchestrator.autoscaling.targetCPUUtilizationPercentage }}
    {{- end }}
    {{- if .Values.orchestrator.autoscaling.targetMemoryUtilizationPercentage }}
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: {{ .Values.orchestrator.autoscaling.targetMemoryUtilizationPercentage }}
    {{- end }}
{{- end }}
{{- end -}}