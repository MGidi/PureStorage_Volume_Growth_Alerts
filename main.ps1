$PureCred = Import-Clixml -Path "C:\folder\folder\file_$($env:USERNAME).xml" 
<#
The following line is used to create the file used in the line above.
To use it and create the cred file, you must use the same windows account that will be used for running the script
Get-Credential | Export-Clixml -Path "C:\folder\folder\file_$($env:USERNAME).xml" 
#>
#$PureCred = Get-Credential # for this to be used when running the script manually

$PureClusters = "PureArray1.company.com","PureArray2.company.com"
$DaysSinceCommissioningToReportAfter = 14
$TimeFrameToCompareWith = "24h" #accepts ['1h', '3h', '24h', '7d', '30d', '90d', '1y']
$GrowthPercentTrhsold = 10
$DoNotRportGrowthOfLessThan = 10 #GB
$DoNotRportVolSmallerThan  =  100GB 
$PureVolThatBreachTheGrowthPercentTrhsold = @()

foreach ($PureCluster in $PureClusters)
{
    $FlashArray = New-PfaArray -EndPoint $PureCluster -Credentials $PureCred -IgnoreCertificateError -ErrorVariable myerror -ErrorAction SilentlyContinue
    $PureVolDetails = (Get-PfaVolumes $FlashArray  -ErrorVariable myerror -ErrorAction SilentlyContinue)
    $PureVolDetailsExcludingNewAndSmall = $PureVolDetails | ? size -gt $DoNotRportVolSmallerThan | ? {(get-date $_.created) -lt (Get-Date).AddDays(-$DaysSinceCommissioningToReportAfter)}
    $PureVolDetailsExcludingNewAndSmall = $PureVolDetailsExcludingNewAndSmall | 
    % {
        $VolumeSpaceMetrics = Get-PfaVolumeSpaceMetricsByTimeRange -VolumeName $_.name -TimeRange $TimeFrameToCompareWith -Array  $FlashArray
        $_ | Add-Member NoteProperty -PassThru -force -Name "GrowthPercentage" -Value  $([math]::Round((($VolumeSpaceMetrics | select -last 1).volumes / (1KB+($VolumeSpaceMetrics | select -first 1).volumes)),2))  | ` # 1KB+ appended to avoid devide by 0 errors
        Add-Member NoteProperty -PassThru -force -Name "GrowthInGB" -Value  $([math]::Round(((($VolumeSpaceMetrics | select -last 1).volumes - ($VolumeSpaceMetrics | select -first 1).volumes) / 1GB),2))  | `
        Add-Member NoteProperty -PassThru -force -Name "ArrayName" -Value $PureCluster 
    }
    $PureVolThatBreachTheGrowthPercentTrhsold += $PureVolDetailsExcludingNewAndSmall | ? {$_.GrowthPercentage -gt $GrowthPercentTrhsold -and $_.GrowthInGB -gt $DoNotRportGrowthOfLessThan}
}
if ($PureVolThatBreachTheGrowthPercentTrhsold)
{
    $Emailto = "user1@.company.com","user2@.company.com"
    $EmailFrom = "PureAlerts@.company.com"
    $EmailSMTPserver = "smtp.company.com"
    $EmailSubject = "Volume Growth warning on Pure"
    $EmailBody ="$EmailSubject <br><br> Note that the following volumes grown in the last $TimeFrameToCompareWith above the $GrowthPercentTrhsold Percent of thier previous sizes: <br><br>" + ($($PureVolThatBreachTheGrowthPercentTrhsold | select name,ArrayName,GrowthInGB,GrowthPercentage) | ConvertTo-Html) + " <br><br> Regards<br>Storage Admin <br><br><br><br><br> * the script currently configured to ignore volumes created in the last $DaysSinceCommissioningToReportAfter days, volumes smaller than $($DoNotRportVolSmallerThan / 1GB) GB, and growth lower than $DoNotRportGrowthOfLessThan GB"
    Send-MailMessage -SmtpServer $EmailSMTPserver -FROM $EmailFrom -to $EmailTo -Subject $EmailSubject -BodyAsHtml  $([string]$EmailBody) -ErrorVariable myerror  -ErrorAction SilentlyContinue 
}
