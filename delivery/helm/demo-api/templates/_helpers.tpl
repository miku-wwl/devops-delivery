{{/* Chart name, truncated to the 63-character DNS label limit. */}}
{{- define "demo-api.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Fully qualified app name: the release name, unless it already contains the chart name. */}}
{{- define "demo-api.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/* Labels used to select pods - must never change after the first install. */}}
{{- define "demo-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "demo-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* Recommended Kubernetes labels for every object. */}}
{{- define "demo-api.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{ include "demo-api.selectorLabels" . }}
app.kubernetes.io/version: {{ include "demo-api.imageTag" . | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: devops-delivery
environment: {{ .Values.environment }}
{{- end -}}

{{- define "demo-api.imageTag" -}}
{{- .Values.image.tag | default .Chart.AppVersion -}}
{{- end -}}

{{/* Image reference: repository@digest when a digest is pinned, otherwise repository:tag. */}}
{{- define "demo-api.image" -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository (include "demo-api.imageTag" .) -}}
{{- end -}}
{{- end -}}
