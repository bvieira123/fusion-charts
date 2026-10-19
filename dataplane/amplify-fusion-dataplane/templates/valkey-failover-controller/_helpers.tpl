{{- define "valkeyFailoverController.name" -}}
valkey-failover-controller
{{- end -}}

{{- define "valkeyFailoverController.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "valkeyFailoverController.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "valkeyFailoverController.appName" -}}
{{- printf "%s-%s" (include "valkeyFailoverController.name" .) .Values.appEnv | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "valkeyFailoverController.labels" -}}
{{ include "dataplane.labels" . }}
{{ include "valkeyFailoverController.selectorLabels" . }}
{{- end -}}

{{- define "valkeyFailoverController.selectorLabels" -}}
app.kubernetes.io/name: {{ include "valkeyFailoverController.name" . }}
app: {{ include "valkeyFailoverController.name" . }}
dplane: "valkey-failover-controller"
{{- end -}}

{{- define "valkeyFailoverController.serviceAccountName" -}}
{{- if .Values.valkey.internal.failoverController.serviceAccount.enabled -}}
{{- default (include "valkeyFailoverController.fullname" .) .Values.valkey.internal.failoverController.serviceAccount.name -}}
{{- else -}}
default
{{- end -}}
{{- end -}}

{{/*
Only insecure or mtls - never one-way tls (ValkeyClusterClient.buildAdmin() has no support
and throws). Must derive from zerotrust.enabled directly, not valkey.client.securityMode -
that's an override for other datagrid clients only, while configmap-config.yaml (which
actually decides whether Valkey enforces TLS) reads zerotrust.enabled alone. Deriving from
the override instead could desync the two: mtls against a Valkey with no TLS (crash-loop on
a missing cert), or insecure against a TLS-only Valkey (silently broken connections).
*/}}
{{- define "valkeyFailoverController.securityMode" -}}
{{- if .Values.zerotrust.enabled -}}
mtls
{{- else -}}
insecure
{{- end -}}
{{- end -}}

{{/*
Must be >= leaseDurationSeconds so a crash-looping new-version replica is caught before the
rollout touches the last replica. Derived directly from leaseDurationSeconds rather than a
separate value, so the two can't drift apart if an operator changes it.
*/}}
{{- define "valkeyFailoverController.minReadySeconds" -}}
{{- .Values.valkey.internal.failoverController.leaderElection.leaseDurationSeconds -}}
{{- end -}}
