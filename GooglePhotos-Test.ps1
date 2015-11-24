function Connect-GoogleAPI {
    <#
    .SYNOPSIS
    Connects to the Google API using OAuth 2.0 and stores the access tokens in global variables.
    #>

    $clientId = "1053883683818-0g862dbhqqmpqeatuh1ig8jectagha9n.apps.googleusercontent.com"   
    $clientSecret = "TOorIeeepy2TrEDCQtWXCdJY"
    $scope = "https://picasaweb.google.com/data/"
    $redirectUri = "urn:ietf:wg:oauth:2.0:oob:auto"

    # sign in form will appear only once
    $authorizeUrl = "https://accounts.google.com/o/oauth2/auth?response_type=code&client_id=$clientId&scope=$scope&redirect_uri=$redirectUri"

    # sign in form will appear every time
    # $authorizeUrl = "https://accounts.google.com/o/oauth2/auth?response_type=code&client_id=$clientId&redirect_uri=$redirectUri&state=$csrfToken&scope=$scope&approval_prompt=force"

    $accessTokenUrl = "https://accounts.google.com/o/oauth2/token"


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

        # step 3: make future GET requests within this scope with the access token

        $requestHeader = @{"Authorization"="Bearer $accessToken"}


        # step x: make a POST request to refresh access token

        #$response = Invoke-RestMethod -Method Post -Uri $accessTokenUrl -ContentType "application/x-www-form-urlencoded" `
        #    -Body @{client_id=$clientId; client_secret=$clientSecret; redirect_uri=$redirectUri; grant_type="refresh_token"; refresh_token=$refreshToken}
    }
}


function Get-GPhotosAlbum {
    $uri = "https://picasaweb.google.com/data/feed/api/user/justingrote"
}
