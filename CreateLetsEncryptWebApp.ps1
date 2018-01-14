#Requires -Modules ACMESharp, AzureRm

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [String]$Fqdn,
    
    [Parameter(Mandatory = $true)]
    [String]$Location,

    [Parameter(Mandatory = $true)]
    [String]$ContactEmail,

    [Parameter(Mandatory = $false)]
    [String]$WebAppName
)

$timeStamp = get-date -uformat %Y%m%d%H%M%S

if ([string]::IsNullOrEmpty($WebAppName)) {
    $WebAppName = "LEDemo$timeStamp"
}

$azcontext = Get-AzureRmContext
if ([string]::IsNullOrEmpty($azcontext.Account)) {
    throw "You must be logged into Azure to use this script"       
}

$grp = Get-AzureRmResourceGroup -Name $ResourceGroupName -ErrorVariable NotPresent -ErrorAction 0

if ($NotPresent) {
    $grp = New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location
}

$aspName = "$WebAppName-asp"

$asp = Get-AzureRmAppServicePlan -Name $aspName -ResourceGroupName $ResourceGroupName -ErrorVariable NotPresent -ErrorAction 0
if ($NotPresent) {
    $asp = New-AzureRmAppServicePlan -Name $aspName -ResourceGroupName $ResourceGroupName -Location $Location -Tier Standard
}

$app = Get-AzureRmWebApp -Name $WebAppName -ResourceGroupName $ResourceGroupName -ErrorVariable NotPresent -ErrorAction 0
if ($NotPresent) {
    $app = New-AzureRmWebApp -Name $WebAppName -ResourceGroupName $ResourceGroupName -Location $Location -AppServicePlan $asp.Id
}

Write-Host "Please ad a DNS CNAME entry from $Fqdn to " + $app.DefaultHostName
Read-Host "Hit enter when completed."

$hosts = $app.HostNames
if (!$hosts.Contains($Fqdn)) {
    $hosts.Add($Fqdn)
    Set-AzureRmWebApp -Name $app.Name -ResourceGroupName $ResourceGroupName -HostNames $hosts
}

$vault = Get-ACMEVault
if ([String]::IsNullOrEmpty($vault)) {
    Initialize-ACMEVault
    $vault = Get-ACMEVault
}

$reg = Get-ACMERegistration -ErrorVariable NotPresent -ErrorAction 0
if ($NotPresent) {
    $reg = New-ACMERegistration -Contacts mailto:$ContactEmail -AcceptTos
}

$alias = $Fqdn.replace('.','-')
$ident =  Get-ACMEIdentifier -IdentifierRef $alias -ErrorAction 0 -ErrorVariable NotPresent
if ($NotPresent) {
    $ident = New-ACMEIdentifier -Dns $Fqdn -Alias $alias
}

Complete-ACMEChallenge -IdentifierRef $alias -ChallengeType http-01 -Handler manual

$challengeFile = $($ident.Challenges[0].HandlerHandleMessage -match "File Path:[^\[]+\[([^\]]+)\]" | Out-Null; $Matches[1])
$challengeContent = $($ident.Challenges[0].HandlerHandleMessage -match "File Content:[^\[]+\[([^\]]+)\]" | Out-Null; $Matches[1])

<#
        $binding = New-AzureRmWebAppSSLBinding `
            -WebAppName $webAppName `
            -ResourceGroupName $ResourceGroupName `
            -Name $Fqdn `
            -CertificateFilePath $CertificatePath `
            -CertificatePassword (New-Object PSCredential "user",$CertificatePassword).GetNetworkCredential().Password `
            -SslState SniEnabled
    }
#>
