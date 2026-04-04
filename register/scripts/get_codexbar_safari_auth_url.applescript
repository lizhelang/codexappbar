on matches_codexbar_oauth(candidate_url)
	if candidate_url is missing value then return false
	set url_text to candidate_url as text
	if url_text does not start with "https://auth.openai.com/oauth/authorize?" then return false
	if url_text does not contain "redirect_uri=http://localhost:1455/auth/callback" then return false
	if url_text does not contain "client_id=" then return false
	if url_text does not contain "state=" then return false
	return true
end matches_codexbar_oauth

on run argv
	if application "Safari" is not running then error "Safari is not running"
	
	tell application "Safari"
		repeat with w in windows
			repeat with t in tabs of w
				try
					set candidate_url to URL of t
					if my matches_codexbar_oauth(candidate_url) then
						return candidate_url
					end if
				end try
			end repeat
		end repeat
	end tell
	
	error "No Codexbar OAuth authorization URL found in Safari tabs"
end run
