{{/*
Pod template shared by the Deployment and the Argo Rollout, so both render
exactly the same pods. Call it with the root context: include "demo-api.podTemplate" .
*/}}
{{- define "demo-api.podTemplate" -}}
metadata:
  labels:
    {{- include "demo-api.labels" . | nindent 4 }}
  annotations:
    # Changing the ConfigMap changes this hash, which rolls the pods.
    checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
    {{- if .Values.metricsAnnotations }}
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: /metrics
    {{- end }}
spec:
  serviceAccountName: {{ include "demo-api.fullname" . }}
  automountServiceAccountToken: false
  securityContext:
    {{- toYaml .Values.podSecurityContext | nindent 4 }}
  containers:
    - name: demo-api
      image: {{ include "demo-api.image" . | quote }}
      imagePullPolicy: {{ .Values.image.pullPolicy }}
      ports:
        - name: http
          containerPort: 8080
          protocol: TCP
      envFrom:
        - configMapRef:
            name: {{ include "demo-api.fullname" . }}
      readinessProbe:
        httpGet:
          path: /readyz
          port: http
        periodSeconds: 5
        failureThreshold: 3
      livenessProbe:
        httpGet:
          path: /healthz
          port: http
        initialDelaySeconds: 5
        periodSeconds: 10
        failureThreshold: 3
      resources:
        {{- toYaml .Values.resources | nindent 8 }}
      securityContext:
        {{- toYaml .Values.securityContext | nindent 8 }}
      volumeMounts:
        - name: tmp
          mountPath: /tmp
  volumes:
    - name: tmp
      emptyDir: {}
  {{- with .Values.nodeSelector }}
  nodeSelector:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- if .Values.affinity }}
  affinity:
    {{- toYaml .Values.affinity | nindent 4 }}
  {{- else if eq .Values.podAntiAffinityPreset "soft" }}
  affinity:
    # Prefer one pod per node; built from the selector labels so it works for any release name.
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            topologyKey: kubernetes.io/hostname
            labelSelector:
              matchLabels:
                {{- include "demo-api.selectorLabels" . | nindent 16 }}
  {{- end }}
  {{- with .Values.tolerations }}
  tolerations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end -}}
