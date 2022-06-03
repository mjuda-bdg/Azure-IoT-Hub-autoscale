workflow aaRunbookProdName
{

param(
  [Parameter (Mandatory= $false)]
  [String] $TenantId = "148fc4b5-9235-4b9e-96e4-ef3d7b7995af",

  [Parameter (Mandatory= $false)]
  [String] $Prod_SubscriptionId = "a7970eba-3a9e-48eb-93d3-76a992a64cff",

  [Parameter (Mandatory= $false)]
  [String] $Devops_SubscriptionId = "cc63bcf9-5c85-483e-916c-78e7092d2fbf"
)

# Ensures you do not inherit an AzContext in your runbook
Disable-AzContextAutosave -Scope Process

# Connect to Azure with system-assigned managed identity
$AzureContext = (Connect-AzAccount -TenantId $TenantId -SubscriptionId $Prod_SubscriptionId -Identity ).Context

# set and store context
$AzureContext = Set-AzContext -SubscriptionId $Prod_SubscriptionId -DefaultProfile $AzureContext


InlineScript{


$TenantId = "148fc4b5-9235-4b9e-96e4-ef3d7b7995af"
$Prod_SubscriptionId = "a7970eba-3a9e-48eb-93d3-76a992a64cff"
$Devops_SubscriptionId = "cc63bcf9-5c85-483e-916c-78e7092d2fbf"

# Set IoT Hub Resource Group
$rg = "md-p-euw-iot-rg"

# Set IoT Hub Name
$hubname = "md-p-euw-iot-ih"

# Set Runbook name
$runbookName = "aaRunbookProdName"

# Set Automation Account Resource Group
$aa_rg = "md-devops-euw-ops-rg"

# Set Automation Account Name
$automationAccountName = "md-devops-euw-ops-aa"


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

# switch to Devops Sub
$AzureContext = Set-AzContext -SubscriptionId $Devops_SubscriptionId -DefaultProfile $AzureContext
Set-AzContext -SubscriptionId $Devops_SubscriptionId -DefaultProfile $AzureContext

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
	Write-Output "Exit in 5 seconds"
	start-sleep 5
 exit
} else { 
 function incre() {
     # Do this incrementation
    $global:capacity++
 }
incre
Write-Output "Total number of messages: $total_msg is above threshold set to $threshold"

# switch to Int Sub

$AzureContext = Set-AzContext -SubscriptionId $Prod_SubscriptionId -DefaultProfile $AzureContext
Set-AzContext -SubscriptionId $Prod_SubscriptionId -DefaultProfile $AzureContext

# Increase number of Units by incremented value
Set-AzIotHub -ResourceGroupName $rg -Name $hubname -SkuName S1 -Units $capacity
Write-Output "IoT hub Units upscaled to $capacity"
Write-Output "Exit in 5 seconds"
start-sleep 5
}
}
}
