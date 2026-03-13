{{- define "venues-ms.fullname" -}}
{{- printf "%s-%s" .Release.Name "venues-ms" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "venues-ms.labels" -}}
app.kubernetes.io/name: venues-ms
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
{{- end }}

{{- define "venues-ms.selectorLabels" -}}
app.kubernetes.io/name: venues-ms
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "venues-ms.jwtAuthMiddleware" -}}
{{ .Release.Name }}-jwt-auth
{{- end }}

{{- define "venues-ms.apiStripMiddleware" -}}
{{ .Release.Name }}-api-strip
{{- end }}

{{- define "venues-ms.rlProtectedMiddleware" -}}
{{ .Release.Name }}-rl-protected
{{- end }}
