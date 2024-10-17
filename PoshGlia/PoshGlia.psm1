
#region Core Functions


function Get-GliaCredential {

    try {

        Write-Verbose -Message 'Retrieving Glia API Credentials'

        if (!$Global:gliaID) {

            $Global:gliaID = Read-Host 'Enter Glia API Key ID (push ctrl + c to exit)'
        }

        if (!$Global:gliaSecret) {

            $Global:gliaSecret = Read-Host 'Enter Glia API Secret (push ctrl + c to exit)'
        }

        @{
            'ApiID'     = $Global:gliaID
            'ApiSecret' = $Global:gliaSecret
        }

        Write-Verbose -Message 'Retrieved API Credentials'
    }
    catch {

        Write-Error -Message 'Problem getting Glia credential variables'
    }
}

function Get-GliaToken {

    [CmdletBinding()]
    param (

        [Parameter(Mandatory, HelpMessage = 'The API ID from the Glia API credential')]
        [String] $ApiID,

        [Parameter(HelpMessage = 'The API secret from the Glia API credential')]
        [String] $ApiSecret
    )

    $currentProtocol = [Net.ServicePointManager]::SecurityProtocol

    if ($currentProtocol.ToString().Split(',').Trim() -notcontains 'Tls12') {

        [Net.ServicePointManager]::SecurityProtocol += [Net.SecurityProtocolType]::Tls12
    }

    $tokenUri = 'https://api.glia.com/sites/tokens'

    $headers = @{}
    $headers.Add("accept", "application/vnd.salemove.v1+json")
    $headers.Add("content-type", "application/json")

    $body = @{

        api_key_id     = $ApiID
        api_key_secret = $ApiSecret
    }

    $body = $body | ConvertTo-Json

    try {

        $response = Invoke-RestMethod -Uri $tokenUri -Headers $headers -Body $body -Method Post
    }
    catch {

        throw 'Error requesting bearer token: {0}' -f $_
    }

    if ($response.access_token) {

        $Script:authDetails = [PSCustomObject]@{
            accessToken    = $response.access_token
            tokenExpiresAt = (Get-Date).AddMinutes(60)
        }
    }

    $Script:authDetails
}

function New-GliaHeaders {

    if ($Script:authDetails.tokenExpiresAt -lt (Get-Date)) {

        $gliaCredentials = Get-GliaCredential

        $null = Get-GliaToken -ApiID $gliaCredentials.ApiID -ApiSecret $gliaCredentials.ApiSecret
    }

    $Script:gliaHeaders = @{

        "accept"        = "application/vnd.salemove.v1+json"
        "content-type"  = "application/json"
        "authorization" = 'Bearer {0}' -f $Script:authDetails.accessToken
    }

    $Script:gliaHeaders
}

function Invoke-GliaRestMethod {

    [CmdletBinding()]
    param (

        [Parameter(Mandatory)]
        [Microsoft.PowerShell.Commands.WebRequestMethod] $Method,

        [Parameter(Mandatory)]
        [Uri] $Uri,

        $Body
    )

    $currentProtocol = [Net.ServicePointManager]::SecurityProtocol

    if ($currentProtocol.ToString().Split(',').Trim() -notcontains 'Tls12') {

        [Net.ServicePointManager]::SecurityProtocol += [Net.SecurityProtocolType]::Tls12
    }

    New-GliaHeaders

    try {

        if ($Body) {

            $response = Invoke-RestMethod -Uri $Uri -Headers $Script:gliaHeaders -Body $Body -Method $Method
        }
        else {

            $response = Invoke-RestMethod -Uri $Uri -Headers $Script:gliaHeaders -Method $Method
        }
    }
    catch {

        $responseError = $_

        $errorDetails = ConvertFrom-Json -InputObject $responseError.ErrorDetails.Message

        throw $errorDetails.message
    }

    $response
}


#endregion

#region Reporting Functions


function Get-GliaEngagements {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory, HelpMessage = 'The Site ID located in the Admin Console under Settings>General>SiteID.')]
        [string] $SiteID,

        [Parameter(HelpMessage = 'The from_start_time in ISO-8601 format. Engagements starting before this time will not be part of the search result.')]
        [datetime] $From,

        [Parameter(HelpMessage = 'The to_start_time in ISO-8601 format. Engagements starting after this time will not be part of the search result. Must refer to a later time than from_start_time.')]
        [datetime] $To
    )

    begin {

        $uri = 'https://api.glia.com/engagements/search'

        $requestBody = @{

            site_ids = @($SiteID)
            per_page = 100
        }

        switch ($PSBoundParameters.Keys) {

            'From' {

                [string] $fromDate = $From.ToString('yyyy-MM-ddTHH:mm:ssZ')

                $requestBody += @{

                    from_start_time = $fromDate
                }
            }
            'To' {

                [string] $toDate = $To.ToString('yyyy-MM-ddTHH:mm:ssZ')

                $requestBody += @{

                    to_start_time = $toDate
                }
            }
        }

        $initialRequestBody = $requestBody | ConvertTo-Json

        $initialResponse = Invoke-GliaRestMethod -Uri $uri -Method Post -Body $initialRequestBody

        if ($initialResponse.ErrorCode) {

            $initialResponse
        }
        else {

            $pageToken = $initialResponse.next_page_token

            $returnObject = @()

            $returnObject += $initialResponse.engagements
        }
    }

    process {

        while ($pageToken) {

            $requestBody = @{

                page_token = $pageToken
            }

            $continuedRequestBody = $requestBody | ConvertTo-Json

            $continuedResponse = Invoke-GliaRestMethod -Uri $uri -Method Post -Body $continuedRequestBody

            $pageToken = $continuedResponse.next_page_token

            $returnObject += $continuedResponse.engagements
        }
    }

    end {

        $returnObject
    }
}


#endregion