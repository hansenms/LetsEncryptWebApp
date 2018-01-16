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
    [String]$WebAppName,

    [Parameter(Mandatory = $false)]
    [String]$VaultName,
    
    [Parameter(Mandatory = $false)]
    [String]$CertificatePath,

    [Parameter(Mandatory = $true)]
    [SecureString]$CertificatePassword
)

. .\WebAppFiles.ps1
Import-Module ACMESharp

#Check if the user is administrator
if (-not [bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544")) {

    throw "You must have administrator priveleges to run this script."

}

#Generate name for web app if none provided.
if ([string]::IsNullOrEmpty($WebAppName)) {
    $timeStamp = get-date -uformat %Y%m%d%H%M%S
    $WebAppName = "LEDemo$timeStamp"
}

#Make sure we are logged into Azure
$azcontext = Get-AzureRmContext
if ([string]::IsNullOrEmpty($azcontext.Account)) {
    throw "You must be logged into Azure to use this script"       
}

#Create Resource Group if it doesn't exsist
$grp = Get-AzureRmResourceGroup -Name $ResourceGroupName -ErrorVariable NotPresent -ErrorAction 0
if ($NotPresent) {
    $grp = New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location
}

#Create app service plan if it doesn't exists already
$aspName = "$WebAppName-asp"
$asp = Get-AzureRmAppServicePlan -Name $aspName -ResourceGroupName $ResourceGroupName -ErrorVariable NotPresent -ErrorAction 0
if ($NotPresent) {
    $asp = New-AzureRmAppServicePlan -Name $aspName -ResourceGroupName $ResourceGroupName -Location $Location -Tier Standard
}

#Create Web App if it doesn't exist already
$app = Get-AzureRmWebApp -Name $WebAppName -ResourceGroupName $ResourceGroupName -ErrorVariable NotPresent -ErrorAction 0
if ($NotPresent) {
    $app = New-AzureRmWebApp -Name $WebAppName -ResourceGroupName $ResourceGroupName -Location $Location -AppServicePlan $asp.Id
}

$message = "Please ad a DNS CNAME entry from $Fqdn to " + $app.HostNames[0]
Write-Host $message
Read-Host "Hit enter when completed."

#Add Fqdn to Web App
$hosts = $app.HostNames
if (!$hosts.Contains($Fqdn)) {
    $hosts.Add($Fqdn)
    Set-AzureRmWebApp -Name $app.Name -ResourceGroupName $ResourceGroupName -HostNames $hosts
}

#Create a VaultName if not supplied
if ([String]::IsNullOrEmpty($VaultName)) 
{
    $VaultName = $WebAppName
}

#Create the vault if it doesn't exist
if (-not $(Get-ACMEVaultProfile -ListProfiles) -contains $VaultName) 
{
    $vaultRootPath = "C:\CertificateVault\" + $vaultName
    $vaultPath = Join-Path -Path $vaultRootPath -ChildPath $vaultName
    $vaultParam = @{RootPath = $vaultPath.ToLower(); CreatePath = $true; BypassEFS = $true }
    Set-ACMEVaultProfile -ProfileName $VaultName -Provider local -VaultParameters $vaultParam -Force
    Initialize-ACMEVault -VaultProfile $VaultName -Force
    $vault = Get-ACMEVault -VaultProfile $VaultName
} else {
    $vault = Get-ACMEVault -VaultProfile $VaultName
}

$reg = New-ACMERegistration -VaultProfile $VaultName -Contacts mailto:$ContactEmail -AcceptTos

$alias = $Fqdn.replace('.','-')
$alias = $alias + $(Get-Random).ToString()

New-ACMEIdentifier -VaultProfile $VaultName -Dns $Fqdn -Alias $alias

Complete-ACMEChallenge -VaultProfile $VaultName -IdentifierRef $alias -Force -ChallengeType http-01 -Handler manual -Regenerate -RepeatHandler
$challenge = $(Update-ACMEIdentifier $alias -VaultProfile $VaultName -ChallengeType http-01).Challenges | Where-Object {$_.Type -eq "http-01"}

$challengeFile = $($challenge.HandlerHandleMessage -match "File Path:[^\[]+\[([^\]]+)\]" | Out-Null; $Matches[1])
$fileComp = $challengeFile.Split("/")
$challengeContent = $($challenge.HandlerHandleMessage -match "File Content:[^\[]+\[([^\]]+)\]" | Out-Null; $Matches[1])
$challengeContent | Out-File -Encoding ASCII -NoNewline -FilePath ".\ACMEChallengeFile.txt"

Create-WebAppDirectory -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName -Directory $fileComp[0]

$folder = $fileComp[0] + "/" + $fileComp[1]
Create-WebAppDirectory -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName -Directory $folder

$cred = Copy-FileToWebApp -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName -Destination $challengeFile -File ".\ACMEChallengeFile.txt"
$fileloc = $fileComp[0] + "/" + $fileComp[1] + "/web.config"
$cred = Copy-FileToWebApp -WebAppName $WebAppName -ResourceGroupName $ResourceGroupName -Destination $fileloc -File .\web.config -PublishingCredentials $cred

Start-Sleep -Seconds 10

$challenge = $(Update-ACMEIdentifier $alias -VaultProfile $VaultName -ChallengeType http-01).Challenges | Where-Object {$_.Type -eq "http-01"}

if ($challenge.Status -ne 'valid') {
    Submit-ACMEChallenge -VaultProfile $VaultName -IdentifierRef $alias -ChallengeType http-01
}

$challenge = $(Update-ACMEIdentifier $alias -VaultProfile $VaultName -ChallengeType http-01).Challenges | Where-Object {$_.Type -eq "http-01"}

$try = 0
while (($challenge.Status -eq 'pending') -and ($try -lt 10)) {
    Write-Host "Sleeping while waiting for challenge validation..."
    $challenge = $(Update-ACMEIdentifier $alias -VaultProfile $VaultName -ChallengeType http-01).Challenges | Where-Object {$_.Type -eq "http-01"}
    Start-Sleep -Seconds 10
    $try = $try + 1    
} 

if ($challenge.Status -ne 'valid') {
    throw 'Failed to validate challenge'
}

$certName = $alias + "-cert"
New-ACMECertificate $alias -VaultProfile $VaultName -Generate -Alias $certName
Submit-ACMECertificate -CertificateRef $certName -VaultProfile $VaultName

$cert = Update-ACMECertificate -CertificateRef $certName -VaultProfile $VaultName

while ([String]::IsNullOrEmpty($cert.IssuerSerialNumber)) {
    Write-Host "Waiting for certficate...."
    Start-Sleep -Seconds 10
    $cert = Update-ACMECertificate -CertificateRef $certName -VaultProfile $VaultName
}

if ([String]::IsNullOrEmpty($CertificatePath)) {
    $CertificatePath = "C:\temp\" + $certName + ".pfx"
}

Get-ACMECertificate $certName -ExportPkcs12 $CertificatePath -CertificatePassword (New-Object PSCredential "user",$CertificatePassword).GetNetworkCredential().Password -VaultProfile $VaultName

$binding = New-AzureRmWebAppSSLBinding `
    -WebAppName $WebAppName `
    -ResourceGroupName $ResourceGroupName `
    -Name $Fqdn `
    -CertificateFilePath $CertificatePath `
    -CertificatePassword (New-Object PSCredential "user",$CertificatePassword).GetNetworkCredential().Password `
    -SslState SniEnabled


Write-Host "All done."
