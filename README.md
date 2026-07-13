# Strutis

## Ruby version

4.0.5 (see `.ruby-version`)

## Setup

```
bundle install
bin/rails db:create db:migrate
```

## Credentials / tokens

All secrets live in Rails credentials, not env vars or `.kamal/secrets` directly.

```
EDITOR="code --wait" bin/rails credentials:edit
```

Keys used by `.kamal/secrets`:

```yaml
kamal:
  registry_password: <GitHub PAT, scope write:packages + read:packages>
postgres:
  password: <strong random value, e.g. output of `openssl rand -hex 32`>
```

## Deployment (Kamal)

Builds happen on the production server itself (`builder.remote` in `config/deploy.yml`), not locally.

```
bin/kamal setup      # first time only
bin/kamal deploy     # every deploy after
```

Shortcuts (defined in `config/deploy.yml` under `aliases`):

```
bin/kamal console    # Rails console on the server
bin/kamal shell      # bash shell in the app container
bin/kamal logs       # tail app logs
bin/kamal dbc        # rails dbconsole
```

Accessory (Postgres) management:

```
bin/kamal accessory boot db
bin/kamal accessory reboot db   # destroys and recreates the container
bin/kamal accessory logs db
bin/kamal accessory details db
```

## Docker cleanup (production)

Two separate caches accumulate on the server over repeated deploys and need separate cleanup:

**Kamal's own old images/containers** (keeps last 5 by default) — run manually from your machine when you think of it, since it needs the local repo + Kamal gem + SSH key:

```
bin/kamal prune all
```

**BuildKit's build cache** — not touched by `kamal prune`, grows separately since builds run via the remote SSH builder. Automated via a weekly cron job on the server (root crontab):

```
0 4 * * 0 docker exec $(docker ps -qf name=buildx_buildkit_kamal-remote) buildctl prune --keep-storage 5000 --all 2>&1 | logger -t buildkit-prune
```

Check it ran: `journalctl -t buildkit-prune`
