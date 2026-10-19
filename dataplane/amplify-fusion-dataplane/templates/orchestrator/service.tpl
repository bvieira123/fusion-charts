{{- define "orchestrator.service" -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ template "orchestrator.appName" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "orchestrator.labels" . | nindent 4 }}
spec:
  clusterIP: None
  selector:
    {{- include "orchestrator.selectorLabels" . | nindent 4 }}
  ports:
    {{- range $port := .Values.orchestrator.service.ports }}
    - name: {{ $port.name }}
      protocol: {{ $port.protocol }}
      port: {{ $port.port }}
      targetPort: {{ $port.targetPort }}
    {{- end }}
{{- end -}}