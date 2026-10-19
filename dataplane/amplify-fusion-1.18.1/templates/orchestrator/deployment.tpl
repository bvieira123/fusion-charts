{{- define "orchestrator.deployment" -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ template "orchestrator.appName" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "orchestrator.labels" . | nindent 4 }}
spec:
  {{- if not .Values.orchestrator.autoscaling.enabled }}
  replicas: {{ .Values.orchestrator.replicaCount }}
  {{- end }}
  strategy:
    type: {{ .Values.orchestrator.strategy.type }}
    rollingUpdate:
      maxSurge: {{ .Values.orchestrator.strategy.rollingUpdate.maxSurge }}
      maxUnavailable: {{ .Values.orchestrator.strategy.rollingUpdate.maxUnavailable }}
  selector:
    matchLabels:
      {{- include "orchestrator.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      annotations:
        checksum/java-security: {{ include (print $.Template.BasePath "/common/configmap-java-security.yaml") . | sha256sum }}
      {{- with .Values.orchestrator.podAnnotations }}
        {{- toYaml . | nindent 8 }}
      {{- end }}
      labels:
        {{- include "orchestrator.selectorLabels" . | nindent 8 }}
        {{- if .Values.zerotrust.enabled }}
        {{ .Values.zerotrust.managedLabel }}: "true"
        {{- end }}
    spec:
      terminationGracePeriodSeconds: {{ .Values.orchestrator.terminationGracePeriodSeconds }}
      {{- with .Values.image.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- if .Values.orchestrator.serviceAccount.enabled }}
      serviceAccountName: {{ include "orchestrator.serviceAccountName" . }}
      {{- end }}
      {{- if .Values.orchestrator.podSecurityContextEnabled }}
      securityContext: {{- toYaml .Values.orchestrator.podSecurityContext| nindent 8 }}
      {{- end }}
      dnsConfig:
        options:
          - name: use-vc
      initContainers:
        - name: {{ .Chart.Name }}-init
          securityContext:
            {{- toYaml .Values.orchestrator.securityContext | nindent 12 }}
          image: "{{ default .Values.image.repository .Values.image.alpinetools.image.repository }}/{{ .Values.image.alpinetools.image.name }}:{{ .Values.image.alpinetools.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          volumeMounts:
            - name: {{ .Values.storage.volumeStorageName }}
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
            - "/bin/sh"
            - "-c"
            - |
              {{- if .Values.valkey.internal.enabled }}
              {{ include "dataplane.commonInit" (dict "context" . "buildTag" .Values.orchestrator.image.buildTag "internal" true "replicas" .Values.valkey.internal.clusterSize) | nindent 14 }}
              {{- else if .Values.valkey.external.enabled }}
              {{ include "dataplane.commonInit" (dict "context" . "buildTag" .Values.orchestrator.image.buildTag) | nindent 14 }}
              {{- end }}

              {{- if .Values.fluentBit.enabled }}
              {{ include "dataplane.createLogDirectory" (dict "serviceName" "ir" "efsRoot" "${efs_root}" "podName" "${POD_NAME}" "additionalPathParam" "") | nindent 14 }}
              {{- end }}
          {{- with .Values.image.initContainers.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
        - name: java-security-init
          securityContext:
            {{- toYaml .Values.orchestrator.securityContext | nindent 12 }}
          image: "{{ default .Values.image.repository .Values.image.alpinetools.image.repository }}/{{ .Values.image.alpinetools.image.name }}:{{ .Values.image.alpinetools.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          command:
            - /bin/sh
            - -c
            - cp /java-security-config/java.security /java-security/java.security
          volumeMounts:
            - name: fusion-java-security-config
              mountPath: /java-security-config
              readOnly: true
            - name: fusion-java-security
              mountPath: /java-security
        {{- include "amplify-fusion.zerotrust.initContainers" . | nindent 8 }}
      containers:
        - name: {{ template "orchestrator.appName" . }}
          securityContext:
            {{- toYaml .Values.orchestrator.securityContext | nindent 12 }}
          image: "{{ default .Values.image.repository .Values.orchestrator.image.repository }}/{{ .Values.orchestrator.image.name }}:{{ .Values.orchestrator.image.buildTag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          envFrom:
            - secretRef:
                name: {{ .Values.secrets.clusterDetails.name }}
            {{- if .Values.email.authentication }}
            - secretRef:
                name: {{ .Values.email.credentials.name }}
            {{- end }}
            {{- if eq .Values.orchestrator.aws.enabled true }}
            - secretRef:
                name: {{ .Values.secrets.orchestratorAws.name }}
            {{- end }}
            - configMapRef:
                name: {{ template "orchestrator.appName" . }}
            - configMapRef:
                name: configmap-common
            {{- if .Values.valkey.enabled }}
            - secretRef:
                name: {{ .Values.secrets.datagrid.name }}
            {{- end }}
          env:
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  apiVersion: v1
                  fieldPath: metadata.name
            - name: local_ip
              valueFrom:
                fieldRef:
                  apiVersion: v1
                  fieldPath: status.podIP
            - name: orchestrator_service
              value: orchestrator-{{ .Values.appEnv }}.{{ .Release.Namespace }}.svc.cluster.local
            {{- with include "encryptAtRest.passwordEnv" (dict "cfg" .Values.orchestrator.encryptAtRest "encryption" .Values.encryption) }}
            {{- . | nindent 12 }}
            {{- end }}
            {{- with .Values.orchestrator.env }}
              {{- toYaml . | nindent 12 }}
            {{- end }}
          ports:
            - containerPort: 1919
              name: internal
              protocol: TCP
            - containerPort: 8181
              name: management
              protocol: TCP
            - containerPort: 50051
              name: grpc
              protocol: TCP
            - containerPort: 50052
              name: sse
              protocol: TCP
          volumeMounts:
            - name: fusion-java-security
              mountPath: /etc/fusion-java-security/java.security
              subPath: java.security
              readOnly: true
            - name: {{ .Values.storage.volumeStorageName }}
              mountPath: /efs
            - name: tmpdir
              mountPath: /tmp
            {{- if .Values.orchestrator.hostPath.enabled }}
            - name: payloads-txn-data
              mountPath: "{{ .Values.orchestrator.ebs_root }}"
            - name: txn-log-base-path
              mountPath: "{{ .Values.orchestrator.txn_log_base_path }}"
            {{- end }}
            {{- if .Values.orchestrator.connectors.nfs.enabled }}
            {{- range $index, $volume := .Values.orchestrator.connectors.nfs.volumes -}}
            {{- with $volume }}
            - name: "connector-nfs-{{ $index }}"
              mountPath: "/connectors/nfs/{{ .name }}"
            {{- end }}
            {{- end }}
            {{- end }}
            {{- with include "encryptAtRest.keystoreVolumeMount" (dict "cfg" .Values.orchestrator.encryptAtRest "encryption" .Values.encryption) }}
            {{- . | nindent 12 }}
            {{- end }}
            {{- include "amplify-fusion.zerotrust.workloadVolumeMounts" . | nindent 12 }}
          resources:
            {{- toYaml .Values.orchestrator.resources | nindent 12 }}
          livenessProbe: {{- toYaml .Values.orchestrator.livenessProbe | nindent 12 }}
          startupProbe: {{- toYaml .Values.orchestrator.startupProbe | nindent 12 }}
          readinessProbe: {{- toYaml .Values.orchestrator.readinessProbe | nindent 12 }}
      volumes:
      - name: fusion-java-security-config
        configMap:
          name: {{ .Release.Name }}-java-security
      - name: fusion-java-security
        emptyDir: {}
      {{- include "amplify-fusion.zerotrust.workloadVolumes" . | nindent 6 }}
      - name: tmpdir
        emptyDir: {}
      {{- if .Values.orchestrator.hostPath.enabled }}
      - name: payloads-txn-data
        hostPath:
          path: /local/dx-data/data
          type: DirectoryOrCreate
      - name: txn-log-base-path
        hostPath:
          path: /local/dx-data/logs
          type: DirectoryOrCreate
      {{- end }}
      - name: {{ .Values.storage.volumeStorageName }}
        persistentVolumeClaim:
          claimName: {{ .Release.Namespace }}-{{ .Values.storage.claimName }}
      {{- with include "encryptAtRest.keystoreVolume" (dict "cfg" .Values.orchestrator.encryptAtRest "encryption" .Values.encryption) }}
      {{- . | nindent 6 }}
      {{- end }}
      {{- if .Values.orchestrator.connectors.nfs.enabled }}
      {{- range $index, $volume := .Values.orchestrator.connectors.nfs.volumes -}}
      {{- with $volume }}
      - name: "connector-nfs-{{ $index }}"
        persistentVolumeClaim:
          claimName: "ampint-connector-nfs-pvc-{{ .name }}"
      {{- end }}
      {{- end }}
      {{- end }}
      {{- with .Values.orchestrator.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.orchestrator.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.orchestrator.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
{{- end -}}
