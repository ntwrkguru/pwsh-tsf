
Clear-Host

# Collect the variables
$device = Read-Host "IP or Hostname of Device"
$user = Read-Host "Username"
$pass = Read-Host "Password" -AsSecureString
$endpoint = "https://$device/api"


function Get-Apikey {
    # We must convert the SecureString variable $pass to plain text for the API call
    $password = ConvertFrom-SecureString $pass -AsPlainText

    # Create the API body object for key retrieval
    $body = @{
        "type"="keygen"
        "user"=$user
        "password"=$password
    }
    $params = @{
        Uri     = $endpoint
        Method  = "Post"
        Body    = $body
    }
    # Retrieve the API key from the username and password for use in subsequent calls
    try {
        $ProgressPreference = 'SilentlyContinue'
        Write-Host "Generating XML API Key"
        $response = Invoke-WebRequest @params -SkipCertificateCheck
        # Parse the response to extract the API key value
        $sxParams = @{
            Content = $response
            XPath   = "//key"
        }
        $soParams = @{
            ExpandProperty  = Node
        }
        $keyValue = (Select-Xml @sxParams | Select-Object @soParams).InnerText
    }
    catch {
        throw $_.Exception

    }
    return $keyValue
}


function New-TechSupport {
    # Create the API body object for TSF generation
    $body = @{
        "key"=$apiKey
        "type"="export"
        "category"="tech-support"
    }
    # Make an API call to the device to generate a Tech Support File
    try {
        $ProgressPreference = 'SilentlyContinue'
        Write-Host "Sending request to generate a TSF"
        $params = @{
            Uri     = $endpoint
            Method  = "Post"
            Body    = $body
        }
        $response = Invoke-WebRequest @params -SkipCertificateCheck
    } catch {
        throw $_.Exception
    }
    # Retrieve the status and job id for status calls
    $status = Select-Xml -Content $response -XPath "/response/@status"
    $msg = Select-Xml -Content $response -XPath "//line"
    Write-Host $msg
    if ($status -notlike "success") {
        throw $msg
    }
    $jobID = (Select-Xml -Content $response -XPath "/response/result/job" | Select-Object -ExpandProperty Node).InnerText
    return $jobID
}


function Get-JobStatus {
    #Create the API body for the job query
    $body = @{
        "key"=$apiKey
        "type"="export"
        "category"="tech-support"
        "action"="status"
        "job-id"=$tsfJobid
    }
    # Define cmdlet parameters
    $params = @{
        Uri=$endpoint
        Method="Post"
        Body=$body
    }
    try {
        $ProgressPreference = 'SilentlyContinue'
        $jobStatusCall = Invoke-WebRequest @params -SkipCertificateCheck
    }
    catch {
       Write-Error "Communications error...retrying"
    }
    $xpathPrefix = "/response/result/job"
    $jobStatus = (Select-Xml -Content $jobStatusCall -XPath "$xpathPrefix/status" | Select-Object -ExpandProperty Node).InnerText
    $progressMessage = (Select-Xml -Content $jobStatusCall -XPath "$xpathPrefix/progress" | Select-Object -ExpandProperty Node).InnerText
    $jobResult = (Select-Xml -Content $jobStatusCall -XPath "$xpathPrefix/result" | Select-Object -ExpandProperty Node).InnerText
    $resultFile = (Select-Xml -Content $jobStatusCall -XPath "$xpathPrefix/resultfile" | Select-Object -ExpandProperty Node).InnerText
    if ($jobStatus -eq "FIN") {
        $jobComplete = "TRUE"
    } else {
        $jobComplete = "FALSE"
    }
    $statusObject = New-Object psobject -Property @{
        "Status"=$jobComplete
        "Progress"=$progressMessage
        "Result"=$jobResult
        "File"=$resultFile
    }
    return $statusObject
}


function Get-Techsupport {
    # Get the TSF
    Write-Host "Downloading TSF to $resultFile"
    $body = @{
        "key"=$apiKey
        "type"="export"
        "category"="tech-support"
        "action"="get"
        "job-id"=$tsfJobid
    }
    $params = @{
        Uri     = $endpoint
        Method  = "Post"
        Body    = $body
        OutFile = $resultFile
    }
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest @params -SkipCertificateCheck
}

function Stop-Job {
    # Stop the job if something happens
    $body = @{
        "key"=$apiKey
        "type"="export"
        "category"="tech-support"
        "action"="finish"
        "job-id"=$tsfJobid
    }
    $params = @{
        Uri     = $endpoint
        Method  = "Post"
        Body    = $body
    }
    try {
        Invoke-WebRequest @params -SkipCertificateCheck
    }
    catch {
        throw $_.Exception
    }
    
}

try {
    $apiKey = Get-Apikey
    $tsfJobid = New-TechSupport
    while ((Get-JobStatus).Status -eq "FALSE") {
        # Set the view of the progress bar
        $PSStyle.Progress.View = 'Minimal'
        $params = @{
            Activity            = "Generating Tech Support File"
            Status              = "$((Get-JobStatus).Progress)%"
            PercentComplete     = -1
            CurrentOperation    = "Generating..."
        }
        Write-Progress @params
        Start-Sleep -seconds 2
    }
    $result = $((Get-JobStatus).Result)
    Write-Host "Result: $result"
    $resultFile = $((Get-JobStatus).File)
    Get-Techsupport
}
catch {
    # Stop the job
    Stop-Job
    throw $_.Exception
}
finally {
    Write-Host "Completed"
}
