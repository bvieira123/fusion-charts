{{- define "valkey.name" -}}
{{- default "valkey" .Values.valkey.internal.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "valkey.fullname" -}}
{{- if .Values.valkey.internal.fullnameOverride }}
{{- .Values.valkey.internal.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "valkey" .Values.valkey.internal.nameOverride }}
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
{{- define "valkey.labels" -}}
{{ include "dataplane.labels" . }}
{{ include "valkey.selectorLabels" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "valkey.selectorLabels" -}}
app.kubernetes.io/name: {{ include "valkey.name" . }}
app: {{ include "valkey.appName" . }}
dplane: "valkey"
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "valkey.serviceAccountName" -}}
{{- if .Values.valkey.internal.serviceAccount.enabled }}
{{- default (include "valkey.fullname" .) .Values.valkey.internal.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.valkey.internal.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Custom templates start here 
*/}}

{{- define "valkey.appName" -}}
{{- if .Values.valkey.internal.nameOverride -}}
{{- .Values.valkey.internal.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "valkey" -}}
{{- end -}}
{{- end }}

{{/*
Image name
*/}}
{{- define "image.finalname" -}}
{{- printf "%s/%s:%s" .Values.valkey.internal.image.server "valkey" .Chart.AppVersion }}
{{- end }}

{{/*
clusterRefId
*/}}
{{- define "valkey.clusterRefId" -}}
{{- printf "%s" (.Values.global.clusterKey | b64dec | fromJson).clusterRefId }}
{{- end }}

{{/*
Check if Valkey internal is enabled
*/}}
{{- define "valkey.internal.enabled" -}}
{{- and .Values.valkey.enabled .Values.valkey.internal.enabled -}}
{{- end -}}


{{/*
Check if Valkey PDB is enabled
*/}}
{{- define "valkey.internal.pdb.enabled" -}}
{{- and (include "valkey.internal.enabled" .) .Values.valkey.internal.podDisruptionBudget.enabled -}}
{{- end -}}

{{/*
Check if Valkey service account is enabled
*/}}
{{- define "valkey.internal.sa.enabled" -}}
{{- and (include "valkey.internal.enabled" .) .Values.valkey.internal.serviceAccount.enabled -}}
{{- end -}}

{{/*
Check if Valkey external is enabled
*/}}
{{- define "valkey.external.enabled" -}}
{{- and .Values.valkey.enabled .Values.valkey.external.enabled -}}
{{- end -}}

{{/*
Calculate maxmemory based on resources.limits.memory with tiered approach
resources.limits.memory not set -> default to 64MB
resource.limits.memory set -> calculate maxmemory based on tiers
Tier 1: Small (≤2GB) - 75% - 64MB
Tier 2: Medium (2-8GB) - 85% - 128MB
Tier 3: Large (8-32GB) - 90% - 256MB
Tier 4: XLarge (>32GB) - 92% - 512MB
Minimum result: 64MB

Formula Explained:
1) Determine the memory limit in bytes.
2) Convert bytes to GB for tier classification
3) Apply the percentage based on the tier.
4) Subtract the fixed overhead based on the tier.
5) Ensure the final maxmemory is at least 64MB.

*/}}

{{- define "valkey.maxmemory" -}}
{{- $mem := .Values.valkey.internal.resources.limits.memory | default "" -}}
{{- $Mi := 1048576 -}}
{{- $Gi := 1073741824 -}}
{{- if not $mem -}}
  {{- mul 64 $Mi -}}
{{- else -}}
  {{- $bytes := 0 -}}
  {{- if hasSuffix "Ki" $mem -}}
    {{- $bytes = int (mulf (trimSuffix "Ki" $mem | float64) 1024) -}}
  {{- else if hasSuffix "Mi" $mem -}}
    {{- $bytes = int (mulf (trimSuffix "Mi" $mem | float64) $Mi) -}}
  {{- else if hasSuffix "Gi" $mem -}}
    {{- $bytes = int (mulf (trimSuffix "Gi" $mem | float64) $Gi) -}}
  {{- else if hasSuffix "Ti" $mem -}}
    {{- $bytes = int (mulf (trimSuffix "Ti" $mem | float64) 1099511627776) -}}
  {{- else -}}
    {{- $bytes = $mem | int -}}
  {{- end -}}

  {{- $t1 := mul 2 $Gi -}}
  {{- $t2 := mul 8 $Gi -}}
  {{- $t3 := mul 32 $Gi -}}

  {{- $max := 0 -}}
  {{- if le $bytes $t1 -}}
    {{- $max = sub (div (mul $bytes 75) 100) (mul 64 $Mi) -}}
  {{- else if le $bytes $t2 -}}
    {{- $max = sub (div (mul $bytes 85) 100) (mul 128 $Mi) -}}
  {{- else if le $bytes $t3 -}}
    {{- $max = sub (div (mul $bytes 90) 100) (mul 256 $Mi) -}}
  {{- else -}}
    {{- $max = sub (div (mul $bytes 92) 100) (mul 512 $Mi) -}}
  {{- end -}}

  {{- if lt $max (mul 64 $Mi) -}}
    {{- $max = mul 64 $Mi -}}
  {{- end -}}
  {{- $max -}}
{{- end -}}
{{- end -}}

{{/*
Generate Valkey save configuration from rdbSnapshots array
*/}}
{{- define "valkey.saveConfig" -}}
{{- if .Values.valkey.internal.persistence.rdbSnapshots -}}
{{- $saveConfig := list -}}
{{- range .Values.valkey.internal.persistence.rdbSnapshots -}}
{{- $saveConfig = append $saveConfig (printf "%d %d" (int .seconds) (int .keyChanges)) -}}
{{- end -}}
{{- if $saveConfig -}}
save {{ join " " $saveConfig }}
{{- else -}}
save ""
{{- end -}}
{{- else -}}
save ""
{{- end -}}
{{- end -}}
