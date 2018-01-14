function Copy-FileToWebApp
{
    param(
        [Parameter(Mandatory)]
        [String]$ResourceGroupName,
        
        [Parameter(Mandatory)]
        [String]$WebAppName,
        
        [Parameter(Mandatory)]
        [String]$File, 
        
        [Parameter(Mandatory)]
        [String]$Destination,

        [Parameter(Mandatory=$false)]
        [System.Object]$PublishingCredentials
    )

    if ([String]::IsNullOrEmpty($PublishingCredentials)) {
        $PublishingCredentials = $(Get-WebAppPublishingCredentials -ResourceGroupName $ResourceGroupName -WebAppName $WebAppName)
    }

    $webclient = New-Object -TypeName System.Net.WebClient
    $webclient.Credentials = New-Object System.Net.NetworkCredential($PublishingCredentials.username,$PublishingCredentials.password)

    $uri = New-Object System.Uri($PublishingCredentials.url + "/$Destination")
    $webclient.UploadFile($uri, $(Get-ChildItem $File).FullName)
    $webclient.Dispose()

    return $PublishingCredentials
}

function Get-WebAppPublishingCredentials
{
    param(
        [Parameter(Mandatory)]
        [String]$ResourceGroupName,
                
        [Parameter(Mandatory)]
        [String]$WebAppName
    )

    $xml = [xml](Get-AzureRmWebAppPublishingProfile -Name $WebAppName -ResourceGroupName $ResourceGroupName)

    $username = $xml.SelectNodes("//publishProfile[@publishMethod=`"FTP`"]/@userName").value
    $password = $xml.SelectNodes("//publishProfile[@publishMethod=`"FTP`"]/@userPWD").value
    $url = $xml.SelectNodes("//publishProfile[@publishMethod=`"FTP`"]/@publishUrl").value

    return @{
        "username" = $username
        "password" = $password
        "url" = $url
    }
}

