# TP-Link MR400/MR6400 Utilities for MikroTik RouterOS

A collection of MikroTik scripts for managing TP-Link LTE modems via web interface.

## Scripts

### 📨 sms-fetch.rsc
Polls the modem for unread SMS messages and forwards them to a webhook endpoint.

**Features:**
- Automatic SMS polling (every 10 seconds)
- Marks messages as read after successful delivery
- Maintains session between runs
- Sends SMS data as JSON to webhook

**Setup:**
```routeros
# Configure in the script
:local simID "my.awesome.modem"
:local webhookURL "https://my.awesome.url/sms"
:local tplinkIP "192.168.1.1"
:local authString "Basic YWRtaW46MjEyMzJmMjk3YTU3YTVhNzQzODk0YTBlNGE4MDFmYzM="

# Create scheduler
/system scheduler add name=sms-checker interval=10s on-event="/import sms-fetch.rsc"
```

### 🔄 modem-reboot.rsc
Automatically reboots the modem on schedule (e.g., daily).

**Features:**
- Fresh login on each run
- Retry logic (3 attempts with 5s delay)
- Session validation before reboot
- Clean logging

**Setup:**
```routeros
# Configure in the script
:local tplinkIP "192.168.1.1"
:local authString "Basic YWRtaW46MjEyMzJmMjk3YTU3YTVhNzQzODk0YTBlNGE4MDFmYzM="

# Create scheduler for daily reboot at 03:00
/system scheduler add name=modem-daily-reboot interval=1d on-event="/import modem-reboot.rsc" start-time=03:00:00
```

## Configuration

### Authentication String

Both scripts use Basic Auth with MD5-hashed password. Default is `admin:admin`.

**To generate for different credentials:**

```python
import hashlib
import base64

username = "admin"
password = "mypassword"
password_hash = hashlib.md5(password.encode()).hexdigest()
auth_string = f"{username}:{password_hash}"
encoded = base64.b64encode(auth_string.encode()).decode()
print(f"Basic {encoded}")
```

Or using bash:
```bash
echo -n "mypassword" | md5sum
# Use the hash to create: admin:hash_here
# Then encode to Base64 and add "Basic " prefix
```

### Example: SMS Checker with Maintenance Window

To pause SMS checking during modem reboot:

```routeros
# Enable SMS checker at 02:58
/system scheduler add name=sms-start interval=1d on-event="/system scheduler enable sms-checker" start-time=02:58:00

# Disable SMS checker at 03:02
/system scheduler add name=sms-stop interval=1d on-event="/system scheduler disable sms-checker" start-time=03:02:00

# Reboot modem at 03:00
/system scheduler add name=modem-reboot interval=1d on-event="/import modem-reboot.rsc" start-time=03:00:00

# SMS checker (disabled during reboot)
/system scheduler add name=sms-checker interval=10s on-event="/import sms-fetch.rsc" disabled=yes
```

## Testing

**Test SMS fetcher:**
```routeros
/import sms-fetch.rsc
/log print where topics~"sms"
```

**Test modem reboot:**
```routeros
/import modem-reboot.rsc
/log print where topics~"modem-reboot"
```

## Troubleshooting

### Login Failed
- Verify `authString` is correct
- Check modem is reachable: `/tool fetch url="http://192.168.1.1" mode=http`
- Ensure no other admin is logged in

### SMS Not Forwarding
- Check webhook URL is accessible
- Verify network connectivity
- Review logs for error messages

### Modem Not Rebooting
- Wait 2-3 minutes (reboot takes time)
- Try manual reboot via browser
- Check logs for "reboot command sent successfully"

## Compatibility

- **Modems:** TP-Link TL-MR400 v4, TL-MR6400 v4 (should work on similar models)
- **RouterOS:** 6.x and 7.x

## How It Works

Both scripts use the TP-Link web interface API:

1. **Login:** GET `/userRpm/LoginRpm.htm?Save=Save` with Basic Auth cookie → returns `hashlogin` token
2. **API Calls:** POST/GET to `/{hashlogin}/userRpm/...` endpoints with Cookie and Referer headers
3. **Session:** SMS fetcher maintains session globally; reboot script creates fresh session each run

## License

MIT

## Author

Vibecoded with ❤️ for reliable LTE connections and automated SMS notifications