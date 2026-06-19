# Authelia SSO

Single sign-on authentication layer in front of all Bernal Labs services.

- Authentication backend: file-based (users_database.yml, not committed for security)
- Access control: all *.josephbernal.com subdomains require one_factor auth
- Storage: local SQLite
- Notifier: filesystem (no SMTP configured yet)

## Setup notes
Generate secrets before deploying:openssl rand -hex 32  # session secret

openssl rand -hex 32  # encryption key

openssl rand -hex 32  # JWT secret
Generate a user password hash:docker run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password 'yourpassword'
eof
