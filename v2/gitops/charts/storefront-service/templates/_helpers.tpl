{{- define "svc.name" -}}
{{- required "values.service is required" .Values.service -}}
{{- end -}}

{{- define "svc.labels" -}}
app.kubernetes.io/name: {{ include "svc.name" . }}
app.kubernetes.io/part-of: storefront
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "svc.selector" -}}
app.kubernetes.io/name: {{ include "svc.name" . }}
app.kubernetes.io/part-of: storefront
{{- end -}}

{{- define "svc.image" -}}
{{ .Values.image.repository }}:{{ required "values.image.tag is required" .Values.image.tag }}
{{- end -}}

{{- define "svc.env" -}}
- name: DEPLOY_ENV
  value: {{ .Release.Namespace | quote }}
- name: RESILIENCE_MODE
  value: {{ .Values.resilienceMode | quote }}
- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: {{ .Values.otelEndpoint | quote }}
- name: OTEL_TRACES_SAMPLER
  value: parentbased_traceidratio
- name: OTEL_TRACES_SAMPLER_ARG
  value: {{ .Values.tracesSampleRatio | quote }}
- name: K8S_POD_NAME
  valueFrom: {fieldRef: {fieldPath: metadata.name}}
- name: K8S_NODE_NAME
  valueFrom: {fieldRef: {fieldPath: spec.nodeName}}
- name: OTEL_RESOURCE_ATTRIBUTES
  value: "k8s.pod.name=$(K8S_POD_NAME),k8s.node.name=$(K8S_NODE_NAME),k8s.namespace.name={{ .Release.Namespace }}"
{{- range $name, $value := .Values.env }}
- name: {{ $name }}
  value: {{ $value | quote }}
{{- end }}
{{- range $name, $ref := .Values.secretEnv }}
- name: {{ $name }}
  valueFrom: {secretKeyRef: {name: {{ $ref.secret }}, key: {{ $ref.key }}}}
{{- end }}
{{- end -}}

{{- define "svc.securityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
runAsNonRoot: true
runAsUser: 10001
capabilities: {drop: [ALL]}
seccompProfile: {type: RuntimeDefault}
{{- end -}}
