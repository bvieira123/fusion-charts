{{- define "parent.dataplaneMode" -}}
{{- (eq .Values.clusterKey "") | ternary "shared" (printf "%s" (.Values.clusterKey | b64dec | fromJson).mode) }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "dataplane.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "dataplane.labels" -}}
helm.sh/chart: {{ include "dataplane.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- end }}

{{/*
Defines a reusable initContainer for the dataplane, responsible for creating a log directory for the included service in the EFS volume before the main container starts.
Usage:
{{ include "dataplane.createLogDirectoryInitContainer" (dict "root" . "serviceName" "my-service" "securityContext" ".Values.<my-service>.securityContext" "additionalPathParam" "additional-path-param" ) }}
*/}}

{{- define "dataplane.createLogDirectoryInitContainer" -}}
initContainers:
- name: {{ .root.Chart.Name }}-init
  securityContext:
    {{- toYaml .securityContext | nindent 4 }}
  image: "{{ default .root.Values.image.repository .root.Values.image.alpinetools.image.repository }}/{{ .root.Values.image.alpinetools.image.name }}:{{ .root.Values.image.alpinetools.image.tag }}"
  imagePullPolicy: {{ .root.Values.image.pullPolicy }}
  volumeMounts:
    - name: {{ .root.Values.storage.volumeStorageName }}
      mountPath: /efs
  env:
    - name: POD_NAME
      valueFrom:
        fieldRef:
          apiVersion: v1
          fieldPath: metadata.name
  envFrom:
    - configMapRef:
        name: configmap-common
  command:
    - sh
    - -c
    - >
     {{ include "dataplane.createLogDirectory" (dict "serviceName" .serviceName "efsRoot" "${efs_root}" "podName" "${POD_NAME}" "additionalPathParam" .additionalPathParam) }}
{{- end }}

{{/*
Creates a static log directory for the service pod in the EFS volume.
*/}}

{{- define "dataplane.createLogDirectory" -}}
      mkdir -p "{{ .efsRoot}}/logs/{{ .serviceName}}/{{ .podName}}/{{ .additionalPathParam}}" || {
        echo "Failed to create log directory: {{ .efsRoot}}/logs/{{ .serviceName}}/{{ .podName}}/{{ .additionalPathParam}}" >&2;
        exit 1;
      }
{{- end}}


{{/*
Common init script waits for Valkey and pre-deploy.
Usage:
- Full script: {{ include "dataplane.commonInit" (dict "context" . "buildTag" .Values.someService.image.buildTag) }}
- External Valkey only: {{ include "dataplane.commonInit" (dict "context" . "valkeyOnly" true) }}
- Internal Valkey: {{ include "dataplane.commonInit" (dict "context" . "valkeyOnly" true "internal" true "replicas" 3) }}
*/}}
{{- define "dataplane.commonInit" -}}
{{- if not .context -}}
{{- fail "dataplane.commonInit: context is required" -}}
{{- end -}}
{{- if and (not .buildTag) (not .valkeyOnly) -}}
{{- fail "dataplane.commonInit: either buildTag or valkeyOnly=true is required" -}}
{{- end -}}
{{- if and .internal (not .replicas) -}}
{{- fail "dataplane.commonInit: replicas is required when internal=true" -}}
{{- end -}}
{{- if .internal -}}
{{- include "dataplane.internalValkeyInit" . -}}
{{- else -}}
{{- include "dataplane.externalValkeyInit" . -}}
{{- end -}}
{{- if .buildTag }}
version="{{ .buildTag }}" ;
predeploy_version="{{ .buildTag }}" ;
{{- end }}
{{- end -}}

{{/*
Internal Valkey initialization - expects a headless service and will resolve each address within.
Usage: Called internally by dataplane.commonInit with full context dict
*/}}
{{- define "dataplane.internalValkeyInit" -}}
expected_replicas={{ .replicas }};
start_time=$(date +%s);
max_duration=300;
valkey_ready=false;
echo "Starting Valkey readiness check. Waiting for ${expected_replicas} replicas to be resolved and reachable within ${max_duration} minutes..."

until [ $(($(date +%s) - start_time)) -ge ${max_duration} ]; do
  # Resolve the hostnames
  all_resolved="";
  {{- range .context.Values.valkey.hosts }}
  host={{ .hostname }};
  host_port={{ .port | default 6379 }};
  # Use a timeout for nslookup itself to prevent it from hanging
  host_ips=$(nslookup -timeout=2 ${host} 2>/dev/null | awk '/^Address: / {print $2}');
  echo "  Host '${host}' resolved to IPs: ${host_ips:-'none'}";
  for ip in $host_ips; do
    all_resolved="${all_resolved} ${ip}:${host_port}";
  done
  {{- end }}

  # Check valid number of hosts
  unique_endpoints=$(echo "$all_resolved" | tr ' ' '\n' | grep . | sort -u);
  unique_count=$(echo "${unique_endpoints}" | wc -l);
  echo "Found ${unique_count} unique endpoints. Expecting ${expected_replicas}."

  if [ "${unique_count}" -ne "${expected_replicas}" ]; then
    echo "Endpoint count does not match expected count. Retrying in 5 seconds..."
    sleep 5;
    continue;
  fi

  # Check port connectivity
  echo "Endpoint count is correct. Checking connectivity..."
  reachable_count=0;
  for entry in $unique_endpoints; do
    ip=$(echo $entry | cut -d: -f1);
    port=$(echo $entry | cut -d: -f2);
    if nc -w 2 -z ${ip} ${port} >/dev/null 2>&1; then
      echo "[SUCCESS] Connectivity to ${ip}:${port} is OK."
      reachable_count=$((reachable_count + 1));
    else
      echo "[FAILED]  Could not connect to ${ip}:${port}."
    fi;
  done;

  # Check all endpoints were reachable

  if [ $reachable_count -eq $expected_replicas ]; then
    echo "[SUCCESS] All ${expected_replicas} Valkey replicas are resolved and reachable."
    valkey_ready=true;
    break;
  fi;
  echo "Only ${reachable_count} of ${expected_replicas} endpoints were reachable. Retrying in 5 seconds..."
  sleep 5;
done;
if [ "${valkey_ready}" != "true" ]; then
  echo "[ERROR] Timed out after ${max_duration} seconds. Could not confirm readiness of all Valkey replicas."
  exit 1;
fi;
{{- end -}}


{{/*
External Valkey initialization - Takes the hosts at face value, no DNS checks.
Usage: Called internally by dataplane.commonInit with full context dict
*/}}
{{- define "dataplane.externalValkeyInit" -}}
# External Valkey mode - direct host connectivity check
c=0;
x={{ len .context.Values.valkey.hosts }};

until [ $c -eq $x ]; do
  c=0;
  {{- range .context.Values.valkey.hosts }}
  host={{ .hostname }};
  port={{ .port | default 6379 }};
  echo "Checking connectivity to ${host}:${port}";
  if nc -w 3 -v ${host} ${port}; then
    c=$((c+1));
  fi;
  {{- end }}
  if [ $c -ne $x ]; then
    echo "Only $c out of $x hosts are reachable, retrying...";
    sleep 2;
  fi;
done;
echo "All ${x} Valkey hosts are reachable";
{{- end -}}


{{/*
Renders the encrypt-at-rest configmap entries for a component.
Usage:
  {{ include "encryptAtRest.configmap" (dict "cfg" .Values.inboundWorker.encryptAtRest "encryption" .Values.encryption "awsRegion" .Values.awsRegion) }}
  {{ include "encryptAtRest.configmap" (dict "cfg" .Values.orchestrator.encryptAtRest "encryption" .Values.encryption "awsRegion" .Values.awsRegion) }}
*/}}
{{- define "encryptAtRest.configmap" -}}
{{- if .cfg.enabled }}
{{- $provider := .encryption.encryptAtRest.provider }}
{{- if eq $provider "aws" }}
{{- if not .encryption.encryptAtRest.kmsKeyArn }}
{{- fail "encryption.encryptAtRest.kmsKeyArn must be set when encryption.encryptAtRest.provider is 'aws'" }}
{{- end }}
{{- if not .awsRegion }}
{{- fail "awsRegion must be set when encryption.encryptAtRest.provider is 'aws'" }}
{{- end }}
{{/* kmsKeyArn is a non-sensitive resource identifier. AWS credentials are provided via IRSA. */}}
CRYPTO_CLUSTER_ROOT_KEY_ID: {{ .encryption.encryptAtRest.kmsKeyArn | quote }}
AWS_REGION: {{ .awsRegion | quote }}
{{- else if eq $provider "localcrk" }}
{{- $local := .encryption.encryptAtRest.localcrk }}
{{- if not $local.alias }}
{{- fail "encryption.encryptAtRest.localcrk.alias must be set when encryption.encryptAtRest.provider is 'localcrk'" }}
{{- end }}
{{- if contains ":" $local.alias }}
{{- fail (printf "encryption.encryptAtRest.localcrk.alias must not contain a colon (got %q) — it is combined into CRYPTO_CLUSTER_ROOT_KEY_ID as localcrk:<alias>" $local.alias) }}
{{- end }}
{{/* The keystore path and alias are non-sensitive. The keystore file itself is projected into
     the container from the localcrk-keystore secret — see "encryptAtRest.keystoreVolume" — and
     the password reaches it as CRYPTO_LOCALCRK_KEYSTORE_PASSWORD from that same secret — see
     "encryptAtRest.passwordEnv". Neither is ever placed here. */}}
CRYPTO_CLUSTER_ROOT_KEY_ID: {{ printf "localcrk:%s" $local.alias | quote }}
CRYPTO_LOCALCRK_KEYSTORE_PATH: {{ include "encryptAtRest.keystorePath" . | quote }}
{{- else }}
{{- fail (printf "encryption.encryptAtRest.provider must be 'aws' or 'localcrk' (got %q)" $provider) }}
{{- end }}
CRYPTO_KEK_DURATION: {{ .cfg.kekDurationMinutes | quote }}
CRYPTO_DEK_DURATION: {{ .cfg.dekDurationMinutes | quote }}
CRYPTO_KEK_ROTATION_PERCENTAGE: {{ .cfg.kekRotationPercentage | quote }}
{{- if gt (int .cfg.kekRotationIntervalMinutes) 0 }}
CRYPTO_KEK_ROTATION_INTERVAL: {{ .cfg.kekRotationIntervalMinutes | quote }}
{{- end }}
{{- end }}
{{- end }}

{{/*
True when the given component has encryption at rest enabled AND the 'localcrk' provider is
the one selected. Used to gate the keystore password env var on the component deployments.
Usage: {{ if eq (include "encryptAtRest.localEnabled" (dict "cfg" .Values.orchestrator.encryptAtRest "encryption" .Values.encryption)) "true" }}
*/}}
{{- define "encryptAtRest.localEnabled" -}}
{{- if and .cfg.enabled (eq .encryption.encryptAtRest.provider "localcrk") -}}
true
{{- end -}}
{{- end }}

{{/*
Where the 'localcrk' keystore file is projected inside the component containers. The chart owns
this location — it is not configurable, because the only thing a user could do with an override
is point CRYPTO_LOCALCRK_KEYSTORE_PATH somewhere the volume is not mounted.
"encryptAtRest.keystoreDir" is the mount point of the secret volume; "encryptAtRest.keystorePath"
is the file within it and must stay in step with the key projected by
"encryptAtRest.keystoreVolume".
*/}}
{{- define "encryptAtRest.keystoreDir" -}}
/localcrk
{{- end }}

{{- define "encryptAtRest.keystorePath" -}}
{{ include "encryptAtRest.keystoreDir" . }}/keystore.p12
{{- end }}

{{/*
Renders the keystore password env var for a component, from the localcrk-keystore secret.
Emits nothing unless the 'localcrk' provider is active for that component.
Usage:
  {{ include "encryptAtRest.passwordEnv" (dict "cfg" .Values.orchestrator.encryptAtRest "encryption" .Values.encryption) }}
*/}}
{{- define "encryptAtRest.passwordEnv" -}}
{{- if eq (include "encryptAtRest.localEnabled" (dict "cfg" .cfg "encryption" .encryption)) "true" -}}
- name: CRYPTO_LOCALCRK_KEYSTORE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: localcrk-keystore
      key: password
{{- end -}}
{{- end }}

{{/*
Renders the pod volume carrying the 'localcrk' keystore file, from the localcrk-keystore secret.
Emits nothing unless the 'localcrk' provider is active for that component.
Usage:
  {{ include "encryptAtRest.keystoreVolume" (dict "cfg" .Values.orchestrator.encryptAtRest "encryption" .Values.encryption) }}
*/}}
{{- define "encryptAtRest.keystoreVolume" -}}
{{- if eq (include "encryptAtRest.localEnabled" (dict "cfg" .cfg "encryption" .encryption)) "true" -}}
- name: localcrk-keystore
  secret:
    secretName: localcrk-keystore
    {{- /* 'password' is deliberately not projected: it reaches the container only as an env var. */}}
    items:
      - key: keystore.p12
        path: keystore.p12
{{- end -}}
{{- end }}

{{/*
Renders the container volume mount for the 'localcrk' keystore file. The keystore is only ever
read (see CrkKeyStore in the crypto module), so a read-only secret volume is sufficient.
Emits nothing unless the 'localcrk' provider is active for that component.
Usage:
  {{ include "encryptAtRest.keystoreVolumeMount" (dict "cfg" .Values.orchestrator.encryptAtRest "encryption" .Values.encryption) }}
*/}}
{{- define "encryptAtRest.keystoreVolumeMount" -}}
{{- if eq (include "encryptAtRest.localEnabled" (dict "cfg" .cfg "encryption" .encryption)) "true" -}}
- name: localcrk-keystore
  mountPath: {{ include "encryptAtRest.keystoreDir" . | quote }}
  readOnly: true
{{- end -}}
{{- end }}

{{/*
Get the Unique ports in a list of hosts with an optional port field.
Usage: {{ include "dataplane.collectPorts" (dict "hosts" .Values.valkey.hosts "defaultPort" 6379) }}
*/}}
{{- define "dataplane.collectPorts" -}}
{{- $hosts := .hosts -}}
{{- $defaultPort := .defaultPort -}}
{{- $ports := dict -}}
{{- range $hosts -}}
{{- $port := .port | default $defaultPort -}}
{{- $_ := set $ports ($port | toString) true -}}
{{- end -}}
{{- range $portValue, $_ := $ports }}
- {{ $portValue }}
{{- end -}}
{{- end -}}

{{/*
Zero-trust generic dispatch helpers.

These helpers form the entire surface that dataplane templates depend on. Each one is
inert unless `zerotrust.enabled` is true, in which case it includes the matching
implementation for the active provider:

  amplify-fusion.zerotrust.provider.<provider>.<helper>

Provider-specific implementations live with the provider (e.g. templates/spire/_helpers.tpl).

All helpers receive the chart context directly:
  {{- include "amplify-fusion.zerotrust.workloadVolumes" . | nindent 6 }}
*/}}

{{- define "amplify-fusion.zerotrust.podLabels" -}}
{{- if .Values.zerotrust.enabled }}
{{ .Values.zerotrust.managedLabel }}: "true"
{{- end -}}
{{- end -}}

{{- define "amplify-fusion.zerotrust.workloadVolumes" -}}
{{- if .Values.zerotrust.enabled -}}
{{- include (printf "amplify-fusion.zerotrust.provider.%s.workloadVolumes" .Values.zerotrust.provider) . -}}
{{- end -}}
{{- end -}}

{{- define "amplify-fusion.zerotrust.workloadVolumeMounts" -}}
{{- if .Values.zerotrust.enabled -}}
{{- include (printf "amplify-fusion.zerotrust.provider.%s.workloadVolumeMounts" .Values.zerotrust.provider) . -}}
{{- end -}}
{{- end -}}

{{- define "amplify-fusion.zerotrust.initContainers" -}}
{{- if .Values.zerotrust.enabled -}}
{{- include (printf "amplify-fusion.zerotrust.provider.%s.initContainers" .Values.zerotrust.provider) . -}}
{{- end -}}
{{- end -}}

{{/* True when fluent-bit's own log rotation is active. */}}
{{- define "logrotate.enabled" -}}
{{- and .Values.fluentBit.enabled .Values.fluentBit.logrotate.enabled -}}
{{- end -}}

{{/* Fixed, non-configurable conventions for the Valkey log-rotation CronJob. */}}
{{- define "dataplane.logRotate.fileSuffix" -}}.%Y-%m-%d-%H-%M{{- end -}}
{{- define "dataplane.logRotate.retention" -}}30{{- end -}}
{{- define "dataplane.logRotate.jobTtl" -}}3600{{- end -}}

{{/*
Maps a log-rotation "frequency" value (values.schema.json enum) to the cron
expression a CronJob needs.
*/}}
{{- define "dataplane.logRotate.cronSchedule" -}}
{{- if eq . "15m" -}}*/15 * * * *
{{- else if eq . "30m" -}}*/30 * * * *
{{- else if eq . "hourly" -}}0 * * * *
{{- else if eq . "6h" -}}0 */6 * * *
{{- else if eq . "12h" -}}0 */12 * * *
{{- else if eq . "daily" -}}0 0 * * *
{{- else -}}
{{- fail (printf "unsupported log-rotation frequency %q (expected one of: 15m, 30m, hourly, 6h, 12h, daily)" .) -}}
{{- end -}}
{{- end -}}