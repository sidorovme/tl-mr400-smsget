# ====================================================================
# TP-Link SMS Checker Script for MikroTik RouterOS
# Polls TP-Link router for unread SMS and triggers external webhook
# ====================================================================

# Configuration
:local simID "my.awesome.modem"

# this is basic auth string for admin:admin credentials
:local authString "Basic YWRtaW46MjEyMzJmMjk3YTU3YTVhNzQzODk0YTBlNGE4MDFmYzM="

# endpoint to trigger
:local webhookURL "https://my.awesome.url/sms"

# modem address address
:local tplinkIP "192.168.1.1"

:local loginPath "/userRpm/LoginRpm.htm?Save=Save"
:local statusAction "/userRpm/lteWebCfg"
:local statusPath "/userRpm/StatusRpm.htm"

# Build authentication cookie header
:local auth ("Cookie: Authorization=" . $authString . "; Domain=" . $tplinkIP . "; Path=/")

# Global variable to store session hash (persists between script runs)
:global tplinkHashlogin

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
# Parse unread SMS count from JSON response
# Returns: number of unread messages or -1 if parsing failed
# ====================================================================
:local parseUnreadCount do={
    :local jsonResponse $1
    
    :local unreadPos [:find $jsonResponse "\"unreadMessages\":"]
    
    :if ($unreadPos >= 0) do={
        # Skip past the key name to the value (17 chars = length of "unreadMessages":")
        :set unreadPos ($unreadPos + 17)
        
        # Extract substring containing the number
        :local substring [:pick $jsonResponse $unreadPos ($unreadPos + 10)]
        
        # Parse digits until first non-digit character
        :local numEnd 0
        :for i from=0 to=([:len $substring] - 1) do={
            :local char [:pick $substring $i ($i + 1)]
            
            # Check if character is a digit (0-9)
            :if ($char = "0" || $char = "1" || $char = "2" || $char = "3" || \
                 $char = "4" || $char = "5" || $char = "6" || $char = "7" || \
                 $char = "8" || $char = "9") do={
                :set numEnd ($i + 1)
            } else={
                # Stop at first non-digit
                :set i ([:len $substring])
            }
        }
        
        # Extract and return the numeric value
        :local unreadCount [:pick $substring 0 $numEnd]
        :if ([:len $unreadCount] > 0) do={
            :return [:tonum $unreadCount]
        }
    }
    
    # Return -1 if parsing failed
    :return -1
}

# ====================================================================
# Fetch list of SMS messages
# Parameters: $1 - tplinkIP, $2 - hashlogin, $3 - auth header
# Returns: JSON response with message list or empty string on error
# ====================================================================
:local fetchUnreadMessages do={
    :local tplinkIP $1
    :local hashlogin $2
    :local auth $3
    
    :local statusURL "http://$tplinkIP/$hashlogin/userRpm/lteWebCfg"
    :local statusPath "/userRpm/StatusRpm.htm"
    :local refererURL "http://$tplinkIP/$hashlogin$statusPath"
    :local postData "{\"module\":\"message\",\"action\":2,\"pageNumber\":1,\"amountPerPage\":50,\"box\":0}"
    
    :do {
        :local result [/tool fetch url=$statusURL http-method=post \
                       http-header="$auth,Referer: $refererURL,Content-Type: application/json" \
                       http-data=$postData output=user as-value]
        
        :if ($result->"status" = "finished") do={
            :return ($result->"data")
        }
    } on-error={
        :log error "check-sms: failed to fetch messages"
    }
    
    :return ""
}

# ====================================================================
# Mark SMS message as read
# Parameters: $1 - tplinkIP, $2 - hashlogin, $3 - auth header, $4 - message index
# Returns: true if successful, false otherwise
# ====================================================================
:local markMessageRead do={
    :local tplinkIP $1
    :local hashlogin $2
    :local auth $3
    :local msgIndex $4
    
    :local statusURL "http://$tplinkIP/$hashlogin/userRpm/lteWebCfg"
    :local statusPath "/userRpm/StatusRpm.htm"
    :local refererURL "http://$tplinkIP/$hashlogin$statusPath"
    :local postData ("{\"module\":\"message\",\"action\":6,\"markReadMessage\":" . $msgIndex . "}")
    
    :do {
        :local result [/tool fetch url=$statusURL http-method=post \
                       http-header="$auth,Referer: $refererURL,Content-Type: application/json" \
                       http-data=$postData output=user as-value]
        
        :if ($result->"status" = "finished") do={
            :return true
        }
    } on-error={
        :log error ("check-sms: failed to mark message " . $msgIndex . " as read")
    }
    
    :return false
}

# ====================================================================
# Parse and send individual unread messages
# Parameters: $1 - webhook URL, $2 - simID, $3 - JSON response with message list
#             $4 - tplinkIP, $5 - hashlogin, $6 - auth, $7 - markMessageRead function
# ====================================================================
:local processUnreadMessages do={
    :local webhookURL $1
    :local simID $2
    :local messagesJson $3
    :local tplinkIP $4
    :local hashlogin $5
    :local auth $6
    :local markReadFunc $7
    
    # Parse JSON using built-in deserialize
    :local jsonData [:deserialize from=json value=$messagesJson]
    :local messages ($jsonData->"messageList")
    :local messagesSize [:len $messages]

    :log info ("Found: " . $messagesSize . " messagaes (read + unread)")

    # Bubble-sorting (by index)
    :for i from=0 to=($messagesSize - 2) do={
        :for j from=0 to=($messagesSize - 2 - $i) do={
            :if ((($messages->$j)->"index") > (($messages->($j + 1))->"index")) do={
                :local temp ($messages->$j)
                :set ($messages->$j) ($messages->($j + 1))
                :set ($messages->($j + 1)) $temp
            }
        }
    }

    :foreach message in=$messages do={
        :local unread ($message->"unread")
        :if ($unread = true) do={

            :local index ($message->"index")
            :log info ("check-sms: sending message index=" . $index)
            
            # Serialize message back to JSON for webhook
            :local msgJson [:serialize to=json value=$message]
            :local payload ("{\"simID\":\"" . $simID . "\",\"message\":" . $msgJson . "}")
            
            :do {
                :local fetchResult [/tool fetch url=$webhookURL mode=https http-method=post \
                        http-header-field="Content-Type: application/json" \
                        http-data=$payload output=user as-value]
                
                # If webhook succeeded, mark message as read
                :if (($fetchResult->"status") = "finished") do={
                    :log info ("check-sms: marking message index " . $index . " as read")
                    [$markReadFunc $tplinkIP $hashlogin $auth $index]
                    :log info "check-sms: sent to webhook"
                }
            } on-error={
                :log error "check-sms: webhook failed, message not marked as read"
            }
        }
    }
    
    :log info ("check-sms: processed " . $msgCount . " unread messages")
}

# ====================================================================
# Check if we have valid session hash, if not - perform login
# ====================================================================
:if ([:typeof $tplinkHashlogin] = "nothing" || [:len $tplinkHashlogin] = 0) do={
    :log info "check-sms: logging in to TP-Link router"
    :set tplinkHashlogin [$doLogin tplinkIP=$tplinkIP loginPath=$loginPath auth=$auth]
    
    :if ([:len $tplinkHashlogin] = 0) do={
        :log error "check-sms: login failed"
        :error "Login failed"
    }
    
    :log info ("check-sms: login successful, hashlogin=" . $tplinkHashlogin)
}

# ====================================================================
# Check SMS status via TP-Link API
# ====================================================================
:local statusURL "http://$tplinkIP/$tplinkHashlogin$statusAction"
:local refererURL "http://$tplinkIP/$tplinkHashlogin$statusPath"
:local postData "{\"module\":\"status\",\"action\":0}"

:do {
    # Make POST request to get router status (includes SMS count)
    :local result [/tool fetch url=$statusURL http-method=post \
                   http-header="$auth,Referer: $refererURL,Content-Type: application/json" \
                   http-data=$postData output=user as-value]
    
    :if ($result->"status" = "finished") do={
        :local response ($result->"data")
        :log info "check-sms: received status response"
        
        # Parse unread messages count using dedicated function
        :local unreadCount [$parseUnreadCount $response]
        
        :if ($unreadCount >= 0) do={
            :log info ("check-sms: unread messages count = " . $unreadCount)
            
            # Fetch and process individual messages if there are unread ones
            :if ($unreadCount > 0) do={
                :log info "check-sms: fetching unread messages"
                :local messagesJson [$fetchUnreadMessages $tplinkIP $tplinkHashlogin $auth]
                
                :if ([:len $messagesJson] > 0) do={
                    [$processUnreadMessages $webhookURL $simID $messagesJson $tplinkIP $tplinkHashlogin $auth $markMessageRead]
                }
            }
        } else={
            :log warning "check-sms: failed to parse unreadMessages from response"
        }
    }
    
} on-error={
    # If status check fails, clear hashlogin to force re-login on next run
    :log warning "check-sms: status check failed, session may have expired"
    :log info "check-sms: clearing hashlogin, will re-login on next run"
    :set tplinkHashlogin ""
}