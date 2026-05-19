{{- define "helpers.mapToArgs" -}}
{{- $args := list }}{{ range $key, $value := . }}{{ $args = append $args (printf "--%s=%s" $key $value) }}{{ end }}{{ toYaml $args -}}
{{- end }}

{{- define "helpers.envFromMap" -}}
{{- $env := list }}{{ range $key, $value := . }}{{ $env = append $env (dict "name" $key "value" $value) }}{{ end }}{{ toYaml $env -}}
{{- end }}

{{- define "helpers.portsFromMap" -}}
{{- $ports := list }}{{ range $name, $port := . }}{{ $ports = append $ports (dict "containerPort" ($port.containerPort | int) "name" $name "protocol" ($port.protocol | default "TCP")) }}{{ end }}{{ toYaml $ports -}}
{{- end }}

{{- define "helpers.volumeMountsFromMap" -}}
{{- $mounts := list }}{{ range $name, $mount := . }}{{ $entry := dict "name" $name "mountPath" $mount.mountPath }}{{ if $mount.subPath }}{{ $entry = set $entry "subPath" $mount.subPath }}{{ end }}{{ if $mount.readOnly }}{{ $entry = set $entry "readOnly" true }}{{ end }}{{ $mounts = append $mounts $entry }}{{ end }}{{ toYaml $mounts -}}
{{- end }}

{{- define "helpers.volumesFromMap" -}}
{{- $vols := list }}{{ range $name, $vol := . }}{{ $entry := dict "name" $name }}{{ $vols = append $vols (merge $entry $vol) }}{{ end }}{{ toYaml $vols -}}
{{- end }}

{{- define "helpers.probeSpec" -}}
{{- $probe := dict }}{{ if .httpGet }}{{ $probe = set $probe "httpGet" .httpGet }}{{ end }}{{ if .exec }}{{ $probe = set $probe "exec" .exec }}{{ end }}{{ if .grpc }}{{ $probe = set $probe "grpc" .grpc }}{{ end }}{{ if .tcpSocket }}{{ $probe = set $probe "tcpSocket" .tcpSocket }}{{ end }}{{ if hasKey . "initialDelaySeconds" }}{{ $probe = set $probe "initialDelaySeconds" .initialDelaySeconds }}{{ end }}{{ if hasKey . "timeoutSeconds" }}{{ $probe = set $probe "timeoutSeconds" .timeoutSeconds }}{{ end }}{{ if hasKey . "periodSeconds" }}{{ $probe = set $probe "periodSeconds" .periodSeconds }}{{ end }}{{ if hasKey . "successThreshold" }}{{ $probe = set $probe "successThreshold" .successThreshold }}{{ end }}{{ if hasKey . "failureThreshold" }}{{ $probe = set $probe "failureThreshold" .failureThreshold }}{{ end -}}
{{ toYaml $probe -}}
{{- end }}
