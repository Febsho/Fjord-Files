# Fjord patch

This source is based on `github.com/duxlabs-dev/dux-go` at
`v1.6.3-0.20261113025848-c9b121458954`, recorded in `core/go.mod` and
`core/go.sum`. The original LICENSE is retained.

Fjord adds `Service.SetIsolatedImageThumbnailer`. When configured by the Fjord
daemon, native image thumbnails are decoded by Fjord's short-lived image worker
with the same seccomp restrictions and dimension limits as the large image
viewer. Other Dux Files APIs and thumbnail cache behavior are unchanged.
