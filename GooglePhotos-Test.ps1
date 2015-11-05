### HELPER FUNCTIONS

function Connect-GPhotosAPI {
<#
    .SYNOPSIS
    Connects to the Google API using OAuth 2.0 and stores the access information in the $GPhotosAuthInfo variable.
#>

    [CmdletBinding()]
    #Please don't use this for other apps, or I'll have to revoke it and force users to put in their own. Thanks :)
    $clientId = "1053883683818-0g862dbhqqmpqeatuh1ig8jectagha9n.apps.googleusercontent.com"   
    $clientSecret = "TOorIeeepy2TrEDCQtWXCdJY"
    #$scope = "https://picasaweb.google.com/data/"
    $scope="https://www.googleapis.com/auth/userinfo%23email+https://mail.google.com/+https://www.googleapis.com/auth/photos+https://www.google.com/m8/feeds/+https://picasaweb.google.com/c/+https://www.googleapis.com/auth/plus.stream.write+https://www.googleapis.com/auth/plus.circles.read+https://www.googleapis.com/auth/plus.profiles.read+https://www.googleapis.com/auth/plus.me+https://www.googleapis.com/auth/plus.media.upload+https://www.googleapis.com/auth/plus.media.readonly+https://www.googleapis.com/auth/plus.settings+http://gdata.youtube.com"
    $redirectUri = "urn:ietf:wg:oauth:2.0:oob:auto"
    $authorizeUrl = "https://accounts.google.com/o/oauth2/auth?response_type=code&client_id=$clientId&scope=$scope&redirect_uri=$redirectUri"
    $accessTokenUrl = "https://accounts.google.com/o/oauth2/token"

    #If a token already exists and it is not expired, don't do anything
    if ($GPhotosAuthInfo) {
        if ($GPhotosAuthInfo.expirydate -lt (Get-Date)) { 
            write-debug "GAPI Auth Token $($GPhotosAuthInfo.AccessToken) is expired, refreshing..."
            $RefreshTokenResponse = Invoke-RestMethod -ErrorAction stop -Method Post -Uri $accessTokenUrl -ContentType "application/x-www-form-urlencoded" `
                -Body @{client_id=$clientId; client_secret=$clientSecret; redirect_uri=$redirectUri; grant_type="refresh_token"; refresh_token=$GPhotosAuthInfo.refreshToken} 
            $GPhotosAuthInfo.accessToken = $RefreshTokenResponse.access_token
            $GPhotosAuthInfo.expiryDate = (get-date).AddSeconds($RefreshTokenResponse.expires_in)
            write-debug "GAPI Token Refreshed and Token Updated"
            return
        }
        else {
            write-debug "GAPI Auth Token Exists and is current"
            return
        }
    }


    # step 1: make a GET request for authorization code (will need to log in Google account if not already logged in)
    Add-Type -AssemblyName System.Windows.Forms
    $form = New-Object -TypeName System.Windows.Forms.Form -Property @{Width=440; Height=640}
    $browser = New-Object -TypeName System.Windows.Forms.WebBrowser -Property @{Width=420; Height=600; Url=$authorizeUrl}

    $onDocumentCompleted = {
        if ($browser.DocumentTitle -match "code=([^&]*)") {
            $script:authorizationCode = $Matches[1]
            $form.Close()
        }
        elseif ($browser.Url.AbsoluteUri -match "error=") {
            $form.Close()
            throw "An error occured while authenticating"
        }
    }

    $browser.Add_DocumentCompleted($onDocumentCompleted)
    $form.Controls.Add($browser)
    $null = $form.ShowDialog()


    if ($authorizationCode -ne $null)
    {
        write-verbose "Authorization Code Obtained: $authorizationCode"

        # step 2: make a POST request to exchange authorization code for access token

        $response = Invoke-RestMethod -Method Post -Uri $accessTokenUrl -ContentType "application/x-www-form-urlencoded" `
            -Body @{client_id=$clientId; client_secret=$clientSecret; redirect_uri=$redirectUri; grant_type="authorization_code"; code=$authorizationCode}

        $accessToken = $response.access_token
        $refreshToken = $response.refresh_token
        $expiryDate = (get-date).AddSeconds($response.expires_in)

        # step 3: make future GET requests within this scope with the access token

        $requestHeader = @{
            "Authorization"="Bearer $accessToken"
            "User-Agent"="Google Photos Powershell Module"
        }


        # step x: make a POST request to refresh access token

  }

    $tokenProps =  [ordered]@{}
    $tokenProps.requestHeader = $requestHeader
    $tokenProps.refreshToken = $refreshToken
    $tokenProps.accessToken = $accessToken
    $tokenProps.expiryDate = $expiryDate

    New-Variable -Scope Script -Name GPhotosAuthInfo -Value (new-object PSCustomObject -property $tokenprops) -Force
}

function Merge-HashTable {
    param(
        [hashtable] $default, 
        [hashtable] $uppend
    )

    # clone for idempotence
    $default1 = $default.Clone() ;

    # remove any keys that exists in original set
    foreach ($key in $uppend.Keys) {
        if ($default1.ContainsKey($key)) {
            $default1.Remove($key) ;
        }
    }

    # union both sets
    return $default1 + $uppend ;
}

function Invoke-GPhotosRequest {
    <#
    .SYNOPSIS
    Helper function wrapper around invoke-restmethod to streamline requests and include error checking for token lifetime
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param (
        
        [Parameter(Mandatory=$true)]$GAPIPath,
        [HashTable]$Headers,
        $Body,
        $Method = "GET",
        $GAPIHost = "www.googleapis.com",
        $ContentType = "application/json; charset=utf-8",
        $UserAgent = $GPhotosAuthInfo.requestHeader.'User-Agent'
    )

    begin { Connect-GPhotosAPI }

    process {
        if ($Headers) {$Headers = Merge-HashTable $GPhotosAuthInfo.requestHeader $Headers}
        else {$Headers = $GPhotosAuthInfo.requestHeader}

        $RequestURI = "https://" + $GAPIHost + $GAPIPath
        $RESTRequestParams = @{
            Method = $Method;
            URI = $RequestURI;
            ContentType = $ContentType;
            UserAgent = $UserAgent;
            Headers = $Headers;
        }

        return invoke-restmethod @RESTRequestParams -Body $Body
    }
}

### USERSPACE FUNCTIONS







function Test-GPhotosPhotoUploaded {
    <#
    .SYNOPSIS
    Connects to the Google API using OAuth 2.0 and stores the access tokens in global variables.
    #>
    $uri = "https://picasaweb.google.com/data/feed/api/user/justingrote"

}
