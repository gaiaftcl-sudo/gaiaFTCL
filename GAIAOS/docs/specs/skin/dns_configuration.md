# GaiaFTCL DNS Configuration for GoDaddy

## Mail Records (Required)

### MX Records
```
Type: MX
Name: @
Priority: 10
Value: mail.gaiaftcl.com
TTL: 1 Hour

Type: MX
Name: @
Priority: 20
Value: backup-mx.gaiaftcl.com
TTL: 1 Hour
```

### A Records for Mail Servers
```
Type: A
Name: mail
Value: 37.120.187.247
TTL: 1 Hour

Type: A
Name: backup-mx
Value: 77.42.85.60
TTL: 1 Hour
```

### SPF Record
```
Type: TXT
Name: @
Value: v=spf1 mx ip4:37.120.187.247 ip4:77.42.85.60 ip4:135.181.88.134 ip4:77.42.32.156 ip4:77.42.88.110 ip4:37.27.7.9 ip4:152.53.91.220 ip4:152.53.88.141 ip4:37.120.187.174 ~all
TTL: 1 Hour
```

### DMARC Record
```
Type: TXT
Name: _dmarc
Value: v=DMARC1; p=quarantine; rua=mailto:dmarc@gaiaftcl.com; ruf=mailto:dmarc@gaiaftcl.com; fo=1
TTL: 1 Hour
```

### DKIM Record
```
Type: TXT
Name: dkim._domainkey
Value: [GET FROM MAILCOW ADMIN UI -> Configuration -> ARC/DKIM keys]
TTL: 1 Hour
```

### Autodiscover Records
```
Type: CNAME
Name: autodiscover
Value: mail.gaiaftcl.com
TTL: 1 Hour

Type: CNAME
Name: autoconfig
Value: mail.gaiaftcl.com
TTL: 1 Hour
```

### SRV Records (for email clients)
```
Type: SRV
Name: _submission._tcp
Priority: 0
Weight: 1
Port: 587
Target: mail.gaiaftcl.com
TTL: 1 Hour

Type: SRV
Name: _imap._tcp
Priority: 0
Weight: 1
Port: 143
Target: mail.gaiaftcl.com
TTL: 1 Hour

Type: SRV
Name: _imaps._tcp
Priority: 0
Weight: 1
Port: 993
Target: mail.gaiaftcl.com
TTL: 1 Hour
```

---

## GoDaddy API Script (Automated)

```bash
#!/bin/bash
# update_dns_godaddy.sh
# Requires GODADDY_KEY and GODADDY_SECRET env vars

DOMAIN="gaiaftcl.com"
API_URL="https://api.godaddy.com/v1/domains/${DOMAIN}/records"

# Auth header
AUTH="Authorization: sso-key ${GODADDY_KEY}:${GODADDY_SECRET}"

# MX Records
curl -X PUT "${API_URL}/MX/@" \
  -H "${AUTH}" \
  -H "Content-Type: application/json" \
  -d '[
    {"data": "mail.gaiaftcl.com", "priority": 10, "ttl": 3600},
    {"data": "backup-mx.gaiaftcl.com", "priority": 20, "ttl": 3600}
  ]'

# A Records
curl -X PUT "${API_URL}/A/mail" \
  -H "${AUTH}" \
  -H "Content-Type: application/json" \
  -d '[{"data": "37.120.187.247", "ttl": 3600}]'

curl -X PUT "${API_URL}/A/backup-mx" \
  -H "${AUTH}" \
  -H "Content-Type: application/json" \
  -d '[{"data": "77.42.85.60", "ttl": 3600}]'

# SPF
curl -X PUT "${API_URL}/TXT/@" \
  -H "${AUTH}" \
  -H "Content-Type: application/json" \
  -d '[{"data": "v=spf1 mx ip4:37.120.187.247 ip4:77.42.85.60 ~all", "ttl": 3600}]'

# DMARC
curl -X PUT "${API_URL}/TXT/_dmarc" \
  -H "${AUTH}" \
  -H "Content-Type: application/json" \
  -d '[{"data": "v=DMARC1; p=quarantine; rua=mailto:dmarc@gaiaftcl.com", "ttl": 3600}]'

# CNAME for autodiscover
curl -X PUT "${API_URL}/CNAME/autodiscover" \
  -H "${AUTH}" \
  -H "Content-Type: application/json" \
  -d '[{"data": "mail.gaiaftcl.com", "ttl": 3600}]'

curl -X PUT "${API_URL}/CNAME/autoconfig" \
  -H "${AUTH}" \
  -H "Content-Type: application/json" \
  -d '[{"data": "mail.gaiaftcl.com", "ttl": 3600}]'

echo "DNS records updated"
```

---

## Verification Commands

After DNS propagation (wait 1-24 hours):

```bash
# Check MX records
dig MX gaiaftcl.com +short

# Check SPF
dig TXT gaiaftcl.com +short

# Check DMARC
dig TXT _dmarc.gaiaftcl.com +short

# Check DKIM
dig TXT dkim._domainkey.gaiaftcl.com +short

# Test mail delivery
echo "Test" | mail -s "Test from $(hostname)" test@gaiaftcl.com
```

---

## Migration Timeline

1. **T-24h**: Lower TTL to 300 seconds on existing records
2. **T-0**: Update MX, A records to new Mailcow servers
3. **T+1h**: Verify mail flow to new servers
4. **T+24h**: Increase TTL back to 3600 seconds
5. **T+48h**: Disable old mail server (Maddy)
