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
Shared resourceNames list of Valkey pod ordinals (valkey-0, valkey-1, ... up to
clusterSize-1), matching the StatefulSet's own pod naming convention. Used by
both the internal Role (templates/valkey/role.yaml, pods: get) and the
failover-controller Role (templates/valkey-failover-controller/role.yaml,
pods: delete) so this security-relevant name list is generated in exactly one
place and cannot drift between the two Roles or from the StatefulSet naming
convention. Callers must indent the emitted lines under their own
`resourceNames:` key, e.g. `{{- include "valkey.internal.podOrdinalResourceNames" . | nindent 6 }}`.
*/}}
{{- define "valkey.internal.podOrdinalResourceNames" -}}
{{- $names := list -}}
{{- range $i := until (int .Values.valkey.internal.clusterSize) -}}
{{- $names = append $names (printf "- %s-%d" (include "valkey.appName" $) $i) -}}
{{- end -}}
{{ join "\n" $names }}
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
{{- printf "%s" (.Values.clusterKey | b64dec | fromJson).clusterRefId }}
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
Valkey enabled + logging to a file -> rotate ourselves; fluent-bit already
rotating it -> skip, let it handle it.
*/}}
{{- define "valkey.internal.logRotateEnabled" -}}
{{- and (eq (include "valkey.internal.enabled" .) "true") .Values.logging.logFileEnabled (not (eq (include "logrotate.enabled" .) "true")) -}}
{{- end -}}

{{/*
Check if Valkey external is enabled
*/}}
{{- define "valkey.external.enabled" -}}
{{- and .Values.valkey.enabled .Values.valkey.external.enabled -}}
{{- end -}}

{{/*
Resolve the effective Valkey client security mode (NONE/ONLY_CA/STRICT/MTLS) - the single
source of truth for "is this deployment using mTLS/one-way-TLS/no security" for Valkey
connections. An explicit valkey.client.security_mode always wins; otherwise it's derived
from zerotrust.enabled. Used directly by common/configmap.yaml's datagrid_security_mode;
valkey-failover-controller's VALKEY_SECURITY_MODE (valkeyFailoverController.securityMode)
reduces this to its own narrower mtls/insecure vocabulary rather than reusing this value
as-is, since the controller is a higher-privilege component than the general datagrid
client and shouldn't silently inherit a mode override that wasn't chosen with it in mind.
*/}}
{{- define "valkey.client.securityMode" -}}
{{- if .Values.valkey.client.security_mode -}}
{{- .Values.valkey.client.security_mode -}}
{{- else if .Values.zerotrust.enabled -}}
MTLS
{{- else -}}
NONE
{{- end -}}
{{- end -}}

{{/*
Resolve the effective datagrid deployment model (standalone/clustered) - the Redisson
connector ConfigFactory.getDeploymentConfig() picks based on this value. An explicit
valkey.client.deployment_model always wins. Otherwise: for an external/managed Valkey
(valkey.external.enabled) this chart renders no server and can't infer its topology, so it
stays clustered - the only mode ever supported there. For the internal Valkey, it's derived
from valkey.internal.clusterSize: standalone when clusterSize:1 (valkey.internal.standalone
renders cluster-enabled no for that pod, and Redisson's cluster connector can't talk to a
Valkey with cluster support disabled), clustered otherwise - matching valkey.internal.enabled's
own rendering of the server side, so the client and server topology can never silently
disagree.
*/}}
{{- define "valkey.client.deploymentModel" -}}
{{- if .Values.valkey.client.deployment_model -}}
{{- .Values.valkey.client.deployment_model -}}
{{- else if and (eq (include "valkey.internal.enabled" .) "true") (eq (include "valkey.internal.standalone" .) "true") -}}
standalone
{{- else -}}
clustered
{{- end -}}
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
{{- if or (not $mem) (eq $mem "0") -}}
  {{- mul 512 $Mi -}}
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

{{/*
Total primary (master) count for the configured topology.
primaries = floor(clusterSize / (replicasPerMaster + 1))
*/}}
{{- define "valkey.internal.primaryCount" -}}
{{- div (int .Values.valkey.internal.clusterSize) (add1 (int .Values.valkey.internal.replicasPerMaster)) -}}
{{- end -}}

{{/*
True when clusterSize:1 - standalone/dev mode, cluster-enabled: no.
*/}}
{{- define "valkey.internal.standalone" -}}
{{- eq (int .Values.valkey.internal.clusterSize) 1 -}}
{{- end -}}

{{/*
True when the Lease-controller sub-quorum failover mechanism should be deployed:
internal Valkey is enabled AND not standalone AND computed primary count < 3.
Auto-failover is unconditional for sub-quorum topologies - there is no opt-in flag;
any sub-quorum cluster always gets the controller. At >=3 primaries native Valkey
quorum handles failover and the controller is not deployed; standalone
(clusterSize:1) has no HA at all. When internal Valkey is disabled (external/managed
Valkey, e.g. MemoryDB), there is no StatefulSet for the controller to manage, so it
must never be deployed regardless of clusterSize.
*/}}
{{- define "valkey.internal.subQuorumFailoverRequired" -}}
{{- if ne (include "valkey.internal.enabled" .) "true" -}}
false
{{- else if eq (include "valkey.internal.standalone" .) "true" -}}
false
{{- else if lt (int (include "valkey.internal.primaryCount" .)) 3 -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}

{{/*
Fixed portion of the preStop wrapper's timeout (templates/valkey/statefulset.yaml):
pre-stop.sh's own worst-case internal budget (wait_for_replication's 30s loop +
notify_controller_prepare's 5s curl) plus script-call overhead. Single source of truth
for the "50" so the preStop wrapper's timeout calculation and validateTopology's
fail-fast check below can never drift apart.
*/}}
{{- define "valkey.internal.preStopFixedBudgetSeconds" -}}
50
{{- end -}}

{{/*
kill_valkey_safely's own SIGTERM-then-SIGKILL escalation window (valkey/scripts/common-
functions.sh: 20s wait after SIGTERM before force-killing with SIGKILL). Single source of
truth used by validateTopology's fail-fast check below to ensure this window is still
guaranteed to run inside terminationGracePeriodSeconds after the preStop hook returns.
*/}}
{{- define "valkey.internal.killValkeySafelyEscalationSeconds" -}}
20
{{- end -}}

{{/*
Fail fast on invalid clusterSize/replicasPerMaster combinations.
*/}}
{{- define "valkey.internal.validateTopology" -}}
{{- $clusterSize := int .Values.valkey.internal.clusterSize -}}
{{- $replicasPerMaster := int .Values.valkey.internal.replicasPerMaster -}}
{{- if le $clusterSize 0 -}}
{{- fail (printf "valkey.internal.clusterSize must be >= 1 (got %d)" $clusterSize) -}}
{{- end -}}
{{- if ge $replicasPerMaster $clusterSize -}}
{{- fail (printf "valkey.internal.replicasPerMaster (%d) must be less than clusterSize (%d) - primary count would be 0" $replicasPerMaster $clusterSize) -}}
{{- end -}}
{{- if gt $replicasPerMaster 2 -}}
{{- fail (printf "valkey.internal.replicasPerMaster (%d) must not exceed 2" $replicasPerMaster) -}}
{{- end -}}
{{- if and (gt $replicasPerMaster 0) (ne (mod $clusterSize (add1 $replicasPerMaster)) 0) -}}
{{- fail (printf "valkey.internal.clusterSize (%d) must be evenly divisible by (replicasPerMaster + 1 = %d) for a uniform topology" $clusterSize (add1 $replicasPerMaster)) -}}
{{- end -}}
{{/*
Fail fast if the preStop wrapper's timeout (preStopFixedBudgetSeconds +
gracefulHandoffTimeoutSeconds) plus kill_valkey_safely's SIGTERM-then-SIGKILL escalation
window would not fit inside terminationGracePeriodSeconds. Otherwise the kubelet SIGKILLs
the pod mid-preStop before kill_valkey_safely's own escalation window ever runs - an
unclean Valkey stop, which is worse than the timeout this preStop wrapper was added to fix.
*/}}
{{- $preStopFixedBudget := int (include "valkey.internal.preStopFixedBudgetSeconds" .) -}}
{{- $killEscalation := int (include "valkey.internal.killValkeySafelyEscalationSeconds" .) -}}
{{- $gracefulHandoffTimeout := int .Values.valkey.internal.gracefulHandoffTimeoutSeconds -}}
{{- $terminationGrace := int .Values.valkey.internal.terminationGracePeriodSeconds -}}
{{- $requiredBudget := add (add $preStopFixedBudget $gracefulHandoffTimeout) $killEscalation -}}
{{- if gt $requiredBudget $terminationGrace -}}
{{- fail (printf "valkey.internal.gracefulHandoffTimeoutSeconds (%d) is too high for valkey.internal.terminationGracePeriodSeconds (%d): the preStop wrapper's timeout (%d fixed + %d gracefulHandoffTimeoutSeconds = %ds) plus kill_valkey_safely's %ds SIGTERM-then-SIGKILL escalation window requires %ds total, which exceeds terminationGracePeriodSeconds - the kubelet would SIGKILL the pod mid-preStop before kill_valkey_safely's escalation window ever runs" $gracefulHandoffTimeout $terminationGrace $preStopFixedBudget $gracefulHandoffTimeout (add $preStopFixedBudget $gracefulHandoffTimeout) $killEscalation $requiredBudget) -}}
{{- end -}}
{{/*
Fail fast if zerotrust is disabled but valkey.client.security_mode still demands some form
of TLS against INTERNAL Valkey. Internal Valkey's TLS listener is gated purely on
zerotrust.enabled (configmap-config.yaml: tls-port/cluster-announce-tls-port are only
rendered when zerotrust.enabled is true) - it has no independent TLS mechanism of its own.
So with zerotrust disabled, ONLY_CA/STRICT/MTLS all resolve to a client attempting a TLS
handshake against a plaintext port, which fails outright at runtime rather than at chart
render time. This check only applies here because valkey.internal.validateTopology is only
ever included from a callsite already gated on valkey.internal.enabled (statefulset.yaml) -
an external/managed Valkey (e.g. AWS MemoryDB) terminates its own TLS independently of
zerotrust/SPIRE and is unaffected regardless of this setting.
*/}}
{{- $resolvedSecurityMode := include "valkey.client.securityMode" . -}}
{{- if and (not .Values.zerotrust.enabled) (ne $resolvedSecurityMode "NONE") -}}
{{- fail (printf "valkey.client.security_mode resolves to %q but zerotrust.enabled is false: internal Valkey never opens a TLS listener unless zerotrust.enabled is true, so every datagrid client would attempt a TLS handshake against a plaintext port. Set valkey.client.security_mode to \"\" or \"NONE\", or enable zerotrust." $resolvedSecurityMode) -}}
{{- end -}}
{{/*
Fail fast if the primary's self-fencing grace period (valkey.internal.fenceGraceSeconds)
would be zero or negative - i.e. fenceSafetyMarginSeconds is not smaller than
the controller's own detection time (primaryDetectionSeconds = intervalSeconds x
unhealthyThreshold). Only meaningful when the sub-quorum controller is actually deployed,
so guarded by subQuorumFailoverRequired.
*/}}
{{- if eq (include "valkey.internal.subQuorumFailoverRequired" .) "true" -}}
{{- if le (int (include "valkey.internal.fenceGraceSeconds" .)) 0 -}}
{{- fail (printf "valkeyFailoverController.primaryHealthCheck.fenceSafetyMarginSeconds (%d) must be less than primaryDetectionSeconds (%d = intervalSeconds x unhealthyThreshold) - the primary must always fence before the controller promotes" (int .Values.valkey.internal.failoverController.primaryHealthCheck.fenceSafetyMarginSeconds) (int (include "valkeyFailoverController.primaryDetectionSeconds" .))) -}}
{{- end -}}
{{/*
Fail fast if the data-plane replication-lag self-fence (min-replicas-max-lag)
would be silently disabled by a zero value - min-replicas-to-write/min-replicas-max-lag
both need to be non-zero for Valkey to actually enforce the check (valkey-io/valkey
src/config.c).
*/}}
{{- if le (int .Values.valkey.internal.minReplicasMaxLagSeconds) 0 -}}
{{- fail (printf "valkey.internal.minReplicasMaxLagSeconds (%d) must be > 0 - a zero value silently disables Valkey's min-replicas-to-write/min-replicas-max-lag write-rejection self-fence entirely" (int .Values.valkey.internal.minReplicasMaxLagSeconds)) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Minimum time (seconds) for PrimaryHealthMonitor to detect a dead primary and trigger
CLUSTER FAILOVER TAKEOVER: unhealthyThreshold consecutive failed checks at intervalSeconds
apart. Single source of truth - both the controller's own @Scheduled cadence/threshold and
the primary's self-fencing grace period (below) derive from this same computation, so they
can never silently drift apart again (they previously did: fence at 30s vs. promote at ~15s).
*/}}
{{- define "valkeyFailoverController.primaryDetectionSeconds" -}}
{{- mul (int .Values.valkey.internal.failoverController.primaryHealthCheck.intervalSeconds) (int .Values.valkey.internal.failoverController.primaryHealthCheck.unhealthyThreshold) -}}
{{- end -}}

{{/*
The primary's own self-fencing grace period - must be strictly less than
primaryDetectionSeconds so the old primary always stops accepting writes before the
controller promotes the replica, with fenceSafetyMarginSeconds of margin against
scheduling/network jitter on either side.
*/}}
{{- define "valkey.internal.fenceGraceSeconds" -}}
{{- sub (int (include "valkeyFailoverController.primaryDetectionSeconds" .)) (int .Values.valkey.internal.failoverController.primaryHealthCheck.fenceSafetyMarginSeconds) -}}
{{- end -}}
