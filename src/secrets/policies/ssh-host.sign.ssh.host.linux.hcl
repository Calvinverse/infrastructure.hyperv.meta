# Allow tokens to read and renew the credentials
# The name of the credential to read ('ssh.host.linux') points to the
# role with the same name
path "ssh-host/sign/ssh.host.linux" {
    capabilities = ["read", "update"]
}
