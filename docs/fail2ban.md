---
title: Fail2Ban
description: Use Fail2Ban to ban IP addresses that repeatedly fail OpenSIPS SIP
  authentication.
---

Fail2Ban can watch OpenSIPS authentication logs and temporarily ban source IP
addresses that repeatedly fail SIP authentication.  The configuration below
keeps the OpenSIPS logging facility as-is and makes the Fail2Ban side adapt to
the logging and firewall backend used by the operating system.

## OpenSIPS Script

Keep your current `syslog_facility` value, such as the default `LOG_LOCAL0`.
The important part is to log a stable marker when authentication fails because
of an invalid user or invalid password.  Those are the `www_authorize()`
negative return codes `-1` and `-2`.

```opensips
if (is_method("REGISTER")) {
    $var(auth_code) = www_authorize("", "subscriber");

    if ($var(auth_code) == -1 || $var(auth_code) == -2) {
        xlog("L_NOTICE", "FAIL2BAN_AUTH failed auth for $fU@$fd from $si code=$var(auth_code)\n");
    }

    if ($var(auth_code) < 0) {
        www_challenge("", "auth");
        exit;
    }
}
```

The Fail2Ban rule below uses `$si`, so the banned address is the network source
IP seen by OpenSIPS, not a SIP header value.

## Install Fail2Ban

Install Fail2Ban from the OS package repository.  The package name is usually
`fail2ban`, but the package manager is OS dependent:

```bash
# Debian / Ubuntu
apt install fail2ban

# Fedora / RHEL-compatible distributions
dnf install fail2ban

# openSUSE / SLES
zypper install fail2ban

# Arch Linux
pacman -S fail2ban
```

Avoid editing `/etc/fail2ban/jail.conf` directly.  Distribution updates may
replace it, so keep local configuration in `/etc/fail2ban/jail.d/*.local` and
filters in `/etc/fail2ban/filter.d/`.

## OpenSIPS Log Source

Fail2Ban can read either a regular log file or the systemd journal.  Pick the
one that matches how OpenSIPS logs on your host.

### Syslog File

If your OS writes OpenSIPS syslog messages to a file, use that file as
`logpath`.  If you want a dedicated OpenSIPS log file, add an rsyslog rule for
the facility you already use.  For example, when OpenSIPS already uses
`LOG_LOCAL0`:

```text
# /etc/rsyslog.d/30-opensips.conf
local0.*    /var/log/opensips.log
```

Then reload rsyslog:

```bash
systemctl reload rsyslog
```

Use the resulting file path in the Fail2Ban jail:

```ini
logpath = /var/log/opensips.log
backend = auto
```

### systemd Journal

If OpenSIPS logs to the journal, use the `systemd` backend and do not set
`logpath` for this jail:

```ini
backend = systemd
journalmatch = SYSLOG_IDENTIFIER=opensips
```

Check the exact journal identifier on your system with:

```bash
journalctl -o short-iso -g FAIL2BAN_AUTH
```

## Fail2Ban Filter

Create `/etc/fail2ban/filter.d/opensips.conf`:

```ini
[Definition]
failregex = ^.*FAIL2BAN_AUTH failed auth for \S+ from <ADDR> code=-(?:1|2)\b
ignoreregex =
```

The marker string keeps the match narrow, while `<ADDR>` lets Fail2Ban extract
IPv4 and IPv6 source addresses from the OpenSIPS log line.

## Fail2Ban Jail

Create `/etc/fail2ban/jail.d/opensips.local`.  The example below uses a
file-based log path and bans both UDP and TCP SIP traffic using the OS selected
`banaction`.

```ini
[opensips]
enabled = true
filter = opensips
logpath = /var/log/opensips.log
backend = auto
maxretry = 5
findtime = 10m
bantime = 1h

action = %(banaction)s[actname=opensips-udp, name=opensips-udp, port="5060,5061", protocol=udp]
         %(banaction)s[actname=opensips-tcp, name=opensips-tcp, port="5060,5061", protocol=tcp]
```

For a journal-based setup, replace `logpath` and `backend` with:

```ini
backend = systemd
journalmatch = SYSLOG_IDENTIFIER=opensips
```

If your distribution does not select the right firewall backend by default, set
it in `/etc/fail2ban/jail.d/defaults.local` rather than hard-coding an action
inside the OpenSIPS jail:

```ini
[DEFAULT]
# nftables based systems
banaction = nftables

# legacy iptables based systems
# banaction = iptables
```

Check the action files shipped by your package under
`/etc/fail2ban/action.d/`; some distributions also ship firewalld-specific
actions.

## Validate and Start

Test the filter against real OpenSIPS log lines before enabling the jail:

```bash
fail2ban-regex /var/log/opensips.log /etc/fail2ban/filter.d/opensips.conf
```

For journal-based deployments:

```bash
fail2ban-regex systemd-journal /etc/fail2ban/filter.d/opensips.conf
```

Restart Fail2Ban and check the jail:

```bash
systemctl restart fail2ban
fail2ban-client status opensips
```

To test the full path, generate a failed REGISTER attempt and confirm that the
line appears in the selected log source with the `FAIL2BAN_AUTH` marker.  After
`maxretry` matches within `findtime`, Fail2Ban should report the source IP in
the `opensips` jail status.
