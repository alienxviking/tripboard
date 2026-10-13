{{- define "tripboard.fullname" -}}
{{- printf "%s" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "tripboard.labels" -}}
app.kubernetes.io/name: tripboard
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "tripboard.selector" -}}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{- define "tripboard.secretName" -}}
{{- if .Values.postgres.existingSecret -}}{{ .Values.postgres.existingSecret }}{{- else -}}{{ include "tripboard.fullname" . }}-db{{- end -}}
{{- end -}}

{{/* container settings that satisfy the "restricted" Pod Security Standard */}}
{{- define "tripboard.containerSecurity" -}}
allowPrivilegeEscalation: false
capabilities:
  drop: ["ALL"]
{{- end -}}
