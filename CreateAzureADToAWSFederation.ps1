#requires -module Az.PortalAPI
<#
.SYNOPSIS
Creates a ready-to-go Azure AD AWS Module
#>

param (
    #The name of your AWS Account, will be used for naming in AD. Recommend to name it the same as the account, or leave blank
    $Name,
    #Email Address to be notified of SAML Certificate Expirations and Role Sync failures
    [Parameter(Mandatory)]$notifyEmail,
    #The API key and credential of an AWS user with at least IAM:Listroles privileges
    $Credential = (Get-Credential -Message "Enter the API Key and Secret of an AWS User with at least IAM:ListRoles privileges. This will be saved in the application and used to discover AWS Roles"),
    #How long an AWS session will last before requiring another login, in seconds. Maximum is 43200
    $awsSessionTime = 43200
)

$ErrorActionPreference = 'Stop'

#This script automates the process in this article: 
#https://docs.microsoft.com/en-us/azure/active-directory/saas-apps/amazon-web-service-tutorial 

write-host -nonewline -f Cyan "Creating AWS Enterprise App $(if ($Name) {"named $Name"})..."
$awsapp = Get-AzPortalGalleryApp "Amazon Web Services" | Add-AzPortalGalleryApp -Name $Name
if ($awsApp) {
    write-host -f Green "OK!"
} else {
    throw "Something went wrong when creating the AWS Enterprise App"
}


$AwsAppObjectID = $awsapp.objectId
$AwsAppID = $awsapp.appId

$awsSAMLProfile = @"
{
    "objectId": "$AwsAppObjectID",
    "identifierUris": [
        "https://signin.aws.amazon.com/saml"
    ],
    "certificateNotificationEmail": "$notifyEmail",
    "signOnUrl": "",
    "logoutUrl": "",
    "replyUrls": [
        "https://signin.aws.amazon.com/saml"
    ],
    "relayState": "https://console.aws.amazon.com/console/home",
    "idpIdentifier": "https://signin.aws.amazon.com/saml",
    "idpReplyUrl": "https://signin.aws.amazon.com/saml",
    "defaultClaimIssuancePolicy": {
        "version": 1,
        "defaultTokenType": "SAML",
        "allowPassThruUsers": "true",
        "includeBasicClaimSet": "true",
        "claimsSchema": [
            {
                "samlClaimType": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier",
                "samlNameIdFormat": "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress",
                "source": "User",
                "extensionID": null,
                "id": "userprincipalname",
                "value": null,
                "transformationId": null
            },
            {
                "samlClaimType": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname",
                "source": "User",
                "extensionID": null,
                "id": "givenname",
                "value": null,
                "transformationId": null
            },
            {
                "samlClaimType": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname",
                "source": "User",
                "extensionID": null,
                "id": "surname",
                "value": null,
                "transformationId": null
            },
            {
                "samlClaimType": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress",
                "source": "User",
                "extensionID": null,
                "id": "mail",
                "value": null,
                "transformationId": null
            },
            {
                "samlClaimType": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name",
                "source": "User",
                "extensionID": null,
                "id": "userprincipalname",
                "value": null,
                "transformationId": null
            },
            {
                "samlClaimType": "https://aws.amazon.com/SAML/Attributes/Role",
                "samlNameIdFormat": null,
                "source": "user",
                "extensionID": null,
                "id": "assignedroles",
                "value": null,
                "transformationId": null
            },
            {
                "samlClaimType": "https://aws.amazon.com/SAML/Attributes/RoleSessionName",
                "samlNameIdFormat": null,
                "source": "user",
                "extensionID": null,
                "id": "userprincipalname",
                "value": null,
                "transformationId": null
            },
            {
                "samlClaimType": "https://aws.amazon.com/SAML/Attributes/SessionDuration",
                "samlNameIdFormat": null,
                "source": null,
                "extensionID": null,
                "id": null,
                "value": "$awsSessionTime",
                "transformationId": null
            }
        ],
        "claimsTransformations": []
    },
    "claimNameIdentifier": "userprincipalname",
    "claimExtensionNameIdentifier": null,
    "claimMethodNameIdentifier": "mail",
    "claimMethodDomainName": null,
    "tokenIssuancePolicy": {
        "version": 1,
        "signingAlgorithm": "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256",
        "tokenResponseSigningPolicy": "TokenOnly",
        "samlTokenVersion": "2.0"
    },
    "tokenIssuancePolicySource": "default"
}
"@

write-host -n -f Cyan "Configuring AWS Enterprise App SAML Settings..."
Invoke-AzPortalRequest "ApplicationSso/$AwsAppObjectID" "FederatedSsoConfigV2" -method POST -body $awsSAMLProfile > $null
Invoke-AzPortalRequest "ApplicationSso/$AwsAppObjectID" "FederatedSsoClaimsPolicyV2" -method POST -body $awsSAMLProfile > $null
write-host -f Green "OK!"

write-host -f Cyan "Sleeping for 10 seconds before enabling SingleSignOn"
sleep 10

write-host -n -f Cyan "Enabling SAML Federation..."
Invoke-AZPortalRequest "ApplicationSso/$AwsAppObjectID" "SingleSignOn" -method POST -body '{"currentSingleSignOnMode":"federated","signInUrl":null}' > $null
write-host -f Green "OK!"

write-host -n -f Cyan "Validating AWS Provisioning Credentials work and have at least IAM:ListRoles privilege..."

$credTestRequest = @"
    {
        "galleryApplicationId": "8b1025e4-1dd2-430b-a150-2ef79cd700f5",
        "templateId": "aws",
        "fieldValues": {
            "clientsecret": "$($awsCred.username)",
            "secrettoken": "$($awsCred.GetNetworkCredential().password)"
        },
        "fieldConfigurations": {
            "clientsecret": {
                "defaultHelpText": null,
                "defaultLabel": null,
                "defaultValue": null,
                "hidden": false,
                "name": "clientsecret",
                "optional": false,
                "readOnly": false,
                "secret": true,
                "validationRegEx": null,
                "extendedProperties": null
            },
            "secrettoken": {
                "defaultHelpText": null,
                "defaultLabel": null,
                "defaultValue": null,
                "hidden": false,
                "name": "secrettoken",
                "optional": false,
                "readOnly": false,
                "secret": true,
                "validationRegEx": null,
                "extendedProperties": null
            }
        },
        "oAuthEnabled": false,
        "oAuth2AuthorizeUrl": null,
        "notificationEmail": null,
        "sendNotificationEmails": false,
        "galleryApplicationKey": "aws",
        "synchronizationLearnMoreIbizaFwLink": "",
        "syncAll": false
    }
"@

$credTestResult = Invoke-AZPortalRequest "UserProvisioning/$AwsAppObjectID/$AwsAppId" "validateCredentials/false" -method POST -body $credTestRequest
if ($credTestResult.success) {
    write-host -f Green "OK!"
} else {
    throw $credTestResult.localizedErrorMessage
}

write-host -f Cyan -n "Saving Provisioning Settings"

write-host -f Cyan -n "Enabling Provisioning (Sync AWS IAM Roles with Application Roles)"