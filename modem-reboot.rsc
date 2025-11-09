# ====================================================================
# TP-Link Modem Reboot Script for MikroTik RouterOS
# Reboots TP-Link MR400 modem via web interface
# ====================================================================

# Configuration
# this is basic auth string for admin:admin credentials
:local authString "Basic YWRtaW46MjEyMzJmMjk3YTU3YTVhNzQzODk0YTBlNGE4MDFmYzM="

# modem address
:local tplinkIP "192.168.1.1"

:local loginPath "/userRpm/LoginRpm.htm?Save=Save"
:local rebootPath "/userRpm/SysRebootRpm.htm?Reboot=Reboot"

# Build authentication cookie header
:local auth ("Cookie: Authorization=" . $authString . "; Domain=" . $tplinkIP . "; Path=/")

# ====================================================================
# Login function - authenticates and extracts session hash
# ====================================================================
:local doLogin do={
    :local url "http://$tplinkIP$loginPath"
    :local result [/tool fetch url=$url http-method=get http-header=$auth output=user as-value]
    
    :if ($result->"status" = "finished") do={
        :local response ($result->"data")
        
        # Parse hashlogin from response (format: http://IP/HASHLOGIN/userRpm/...)
        :local searchString "$tplinkIP/"
        :local startPos [:find $response $searchString]
        :if ($startPos >= 0) do={
            :set startPos ($startPos + [:len $searchString])
            :local endPos [:find $response "/userRpm" $startPos]
            :if ($endPos >= 0) do={
                :return [:pick $response $startPos $endPos]
            }
        }
    }
    :return ""
}

# ====================================================================
# Always perform fresh login for daily reboot
# ====================================================================
:local hashlogin ""
:local loginAttempts 3
:local attemptDelay 5s

:for i from=1 to=$loginAttempts do={
    :if ([:len $hashlogin] = 0) do={
        :log info ("modem-reboot: login attempt " . $i . " of " . $loginAttempts)
        :set hashlogin [$doLogin tplinkIP=$tplinkIP loginPath=$loginPath auth=$auth]
        
        :if ([:len $hashlogin] > 0) do={
            :log info ("modem-reboot: login successful, hashlogin=" . $hashlogin)
        } else={
            :if ($i < $loginAttempts) do={
                :log warning ("modem-reboot: login attempt " . $i . " failed, retrying in " . $attemptDelay)
                :delay $attemptDelay
            } else={
                :log error "modem-reboot: all login attempts failed"
                :error "Login failed after all attempts"
            }
        }
    }
}

# ====================================================================
# Check session validity by requesting status
# ====================================================================
:local statusAction "/userRpm/lteWebCfg"
:local statusPath "/userRpm/StatusRpm.htm"
:local statusURL "http://$tplinkIP/$hashlogin$statusAction"
:local refererURL "http://$tplinkIP/$hashlogin$statusPath"
:local postData "{\"module\":\"status\",\"action\":0}"

:local sessionValid false

:do {
    :log info "modem-reboot: checking session validity"
    :local result [/tool fetch url=$statusURL http-method=post \
                   http-header="$auth,Referer: $refererURL,Content-Type: application/json" \
                   http-data=$postData output=user as-value]
    
    :if ($result->"status" = "finished") do={
        :local response ($result->"data")
        :log info "modem-reboot: session is valid"
        :set sessionValid true
    }
    
} on-error={
    :log error "modem-reboot: session validation failed"
}

:if ($sessionValid = false) do={
    :log error "modem-reboot: cannot proceed without valid session"
    :error "Session validation failed"
}

# ====================================================================
# Reboot the modem
# ====================================================================
:local rebootURL "http://$tplinkIP/$hashlogin$rebootPath"
:local refererReboot "http://$tplinkIP/$hashlogin/userRpm/SysRebootRpm.htm"

:do {
    :log info "modem-reboot: sending reboot command to modem"
    # Reboot request with both Cookie and Referer headers
    :local result [/tool fetch url=$rebootURL http-method=get http-header="$auth,Referer: $refererReboot" output=user as-value]
    
    :if ($result->"status" = "finished") do={
        :log info "modem-reboot: reboot command sent successfully"
    } else={
        :log warning "modem-reboot: reboot command may have failed"
    }
    
} on-error={
    :log error "modem-reboot: reboot request failed"
    :error "Reboot failed"
}
