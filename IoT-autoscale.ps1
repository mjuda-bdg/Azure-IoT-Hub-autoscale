workflow iothubautoscaler
{
# Author: Marcin Juda mar.bydg@gmail.com



# Ensures you do not inherit an AzContext in your runbook
Disable-AzContextAutosave -Scope Process

# Connect to Azure with system-assigned managed identity
$AzureContext = (Connect-AzAccount -Identity).context

# set and store context
$AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext

InlineScript{

# Set IoT Hub Resource Group
$rg = "rg-SharedSvcs-dev-01"

# Set IoT Hub Name
$hubname = "iot-hub-dynatrace"

# Set Runbook name
$runbookName = "iotautoscalerprod"

# Set Automation Account Resource Group
$aa_rg = "rg-SharedSvcs-dev-01"

# Set Automation Account Name
$automationAccountName = "aa-northeurope-dev-02"



# Check current number of IoT Hub messages
$total_msg = Get-AzIotHubQuotaMetric -ResourceGroupName $rg -Name $hubname | select -ExpandProperty CurrentValue -First 1
$total_msg = $total_msg -as [int]

#Check IoT Hub quota
$quota = Get-AzIotHubQuotaMetric -ResourceGroupName $rg -Name $hubname | select -ExpandProperty MaxValue -First 1
$quota = $quota -as [int]
Write-Output "Current IoT Hub quota is: $quota"

# Set the IoT message threshold
$threshold = ($quota * 0.9)
Write-Output "Message threshold is set to: $threshold"

# Check current number of IoT Hub Units
$iot = Get-AzIotHub -ResourceGroupName $rg -Name $hubname
$capacity = $iot.Sku | Select-Object -Expand Capacity | ConvertTo-Json
$capacity = $capacity -as [int]
Write-Output "Current number of IoT Hub units: $capacity"

# Check for already running or new runbooks
$jobs = Get-AzAutomationJob -ResourceGroupName $aa_rg `
    -AutomationAccountName $automationAccountName `
    -RunbookName $runbookName `
    -DefaultProfile $AzureContext

# Check to see if it is already running
$runningCount = ($jobs.Where( { $_.Status -eq 'Running' })).count

if (($jobs.Status -contains 'Running' -and $runningCount -gt 1 ) -or ($jobs.Status -eq 'New')) {
    # Exit code
    Write-Output "Runbook $runbookName is already running"
    exit 1
} elseif ($total_msg -lt $threshold)
{
    Write-Output "Total number of messages: $total_msg is below threshold set to $threshold"
 exit
} else { 
 function incre() {
     # Do this incrementation
    $global:capacity++
 }
incre
Write-Output "Total number of messages: $total_msg is above threshold set to $threshold"

# Increase number of Units by incremented value
Set-AzIotHub -ResourceGroupName $rg -Name $hubname -SkuName S1 -Units $capacity
Write-Output "IoT hub Units upscaled to $capacity"

# Set time when message quota will be reset in IoT Hub, script will sleep until then to not scale up unnecessarily

$end = get-date "1:07am"
$end_post = $end.AddDays(1)
while ((get-date) -lt $end_post) {
    Write-Output "IoT hub was scaled up. Waiting for reset of IoT message quota at $end_post"
    start-sleep 10
}
}
}
}
