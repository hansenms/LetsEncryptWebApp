Azure Web App with Let's Encrypt Certificate
--------------------------------------------

This repository contains example code for creating an [Azure Web App](https://azure.microsoft.com/en-us/services/app-service/web/) with a [Let's Encrypt](https://letsencrypt.org/) SSL Certificate. It uses the [ACMESharp](https://github.com/ebekker/ACMESharp) Powershell module. You can install the ACMESharp Module in Powershell with:

```
Install-Module ACMESharp -AllowClobber
```

All the code needed to set up a Web App, generate the certificate, and bind the certificate is contained in the [CreateLetsEncryptWebApp.ps1](CreateLetsEncryptWebApp.ps1) script. The script does the following:

1. Creates a Web App with an App Service plan, if it doesn't exist already.
2. Pauses to allow the user to set a CNAME to point to the Web App. It is important to complete this step before continuing or the Web App will not allow the custom DNS name.
3. Creates an ACME Vault and registration (if it doesn't exist).
4. Generates a new ACME identifier for the DNS name.
5. Starts an HTTP challenge.
6. Uploads appropriate challenge reponse to the Web App.
7. Submits the challenge. 
8. Waits for challenge validation.
9. Generates certificate.
10. Binds certificate to the Web App

If the Web App already exists, it will simple generate a new cert and bind it, effectively renewing the certificate. 

To call the script:

```
.\CreateLetsEncryptWebApp.ps1 -ResourceGroupName "RESOURCE-GROUP-NAME" `
-WebAppName "WEB-APP-NAME" -Fqdn "DOMAIN NAME" -Location "LOCATION" `
-ContactEmail "EMAIL ADDRESS FOR REGISTRATION"
```

