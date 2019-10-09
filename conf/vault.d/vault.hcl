storage "consul" {
  address = "127.0.0.1:8500"
  path    = "vault/"
}

ui = true

listener "tcp" {
  address = "0.0.0.0:8322"
  tls_disable = 0
  tls_cert_file = "/etc/pki/tls/certs/hashistack-server.pem"
  tls_key_file = "/etc/pki/tls/private/hashistack-server-key.pem"
}
