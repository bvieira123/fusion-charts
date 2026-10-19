{{- define "domainCertWatch.appName" -}}
{{- $name := default "domain-cert-watch" .Values.tls.domainCertWatch.nameOverride -}}
{{- $env := default "env" .Values.appEnv -}}
{{- printf "%s-%s" $name $env  | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "domainCertWatch.serviceAccountName" -}}
{{- if .Values.tls.domainCertWatch.serviceAccount.enabled -}}
    {{ default "domain-cert-watch" .Values.tls.domainCertWatch.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.tls.domainCertWatch.serviceAccount.name }}
{{- end -}}
{{- end -}}


{{- define "domainCertWatch.domainCertHash" -}}
{{- $secret := (lookup "v1" "Secret" .Release.Namespace "domain-certificate") -}}
{{- if $secret -}}
{{- $secretData := $secret.data -}}
{{- $json := toJson $secretData -}}
{{- printf "%s" $json | sha1sum -}}
{{- else -}}
{{- "UNINITIALIZED" -}}
{{- end -}}
{{- end -}}


{{- define "domainCertWatch.sshCertHash" -}}
{{- $secret := (lookup "v1" "Secret" .Release.Namespace "ssh-domain-certificate") -}}
{{- if $secret -}}
{{- $secretData := $secret.data -}}
{{- $json := toJson $secretData -}}
{{- printf "%s" $json | sha1sum -}}
{{- else -}}
{{- "UNINITIALIZED" -}}
{{- end -}}
{{- end -}}


