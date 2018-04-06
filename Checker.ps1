# путь до рабочей папки
$Path = Split-Path -Path ($MyInvocation.MyCommand.Path) -Parent
$GlobalScopeConfigFile = "$Path\config.csv"

# конфиг в котором хранятся настройки данного бота (для непрерывной интеграции)
if (test-path variable:\Config) { Remove-Variable Config }
New-Variable -Name Config -Option AllScope -Value ( Import-Csv -Path $GlobalScopeConfigFile )

#Пороговые значения для проверки GPU
$temp_limit=$Config | where { $_.Parameter -eq "temp_limit" } | select -ExpandProperty Text
$util_limit=$Config | where { $_.Parameter -eq "util_limit" } | select -ExpandProperty Text
$NvidiaPath=$Config | where { $_.Parameter -eq "NvidiaPath" } | select -ExpandProperty Text
#Настройки почты
if ( $($Config | where { $_.Parameter -eq "MailEnable" } | select -ExpandProperty Text) -eq "1" ) { $MailEnable=$true }
else { $MailEnable = $false }
$MailFrom=$Config | where { $_.Parameter -eq "MailFrom" } | select -ExpandProperty Text
$MailPassword=$Config | where { $_.Parameter -eq "MailPassword" } | select -ExpandProperty Text
$MailTo=$Config | where { $_.Parameter -eq "MailTo" } | select -ExpandProperty Text
$MailSmtpServer=$Config | where { $_.Parameter -eq "MailSmtpServer" } | select -ExpandProperty Text
$MailPort=$Config | where { $_.Parameter -eq "MailPort" } | select -ExpandProperty Text
# токен бота
$token=$Config | where { $_.Parameter -eq "token" } | select -ExpandProperty Text
# ID чата
$MyChatID=$Config | where { $_.Parameter -eq "MyChatID" } | select -ExpandProperty Text

# файл лога
$logFile = "$Path\log.txt"

<############################################################################################
    Евент на проверку видеокарт - устарело
###########################################################################################
#Создаем таймер 
$timer = New-Object Timers.Timer
$timer.Interval = 600000 # время срабатывания 600000 сек = 10 мин
$timer.AutoReset = $true  # включаем таймер заново, после срабатывания
$timer.Enabled = $true

#Регистрируем циклический эвент для запуска функции проверки карт
Register-ObjectEvent -InputObject $timer -EventName Elapsed -SourceIdentifier CheckGPU -Action {CheckGPU}
Unregister-Event -SourceIdentifier CheckGPU #Удаляем евент
#>

<############################################################################################
    логер
#>###########################################################################################
function log {
	param ( [parameter(Mandatory = $true)] [string]$Message )
	
    # проверка на длину лога
    #if ( ($(Get-ChildItem $logFile).Length / 1mb) -gt 20 ) { Clear-Content $logFile }

	$DT = Get-Date -Format "yyyy.MM.dd HH:mm:ss"
	$MSGOut = $DT + "`t" + $Message
	Out-File -FilePath $logFile -InputObject $MSGOut -Append -encoding unicode
}

<############################################################################################
    отправляет сообщение
#>###########################################################################################
function BotSay {
    param(  [string]$text = $(Throw "'-text' argument is mandatory"), [switch]$markdown)

    if($markdown) { $markdown_mode = "Markdown" } else {$markdown_mode = ""}

    $payload = @{ "parse_mode" = "$markdown_mode";
                  "disable_web_page_preview" = "True";
                }
    $URL = "https://api.telegram.org/bot$token/sendMessage?chat_id=$MyChatID&text=$text"
    
    $request = Invoke-WebRequest -Uri $URL -Method Post -ContentType "application/json;charset=utf-8" `
                    -Body (ConvertTo-Json -Compress -InputObject $payload)
}

<############################################################################################
    проверка видеокарт и отправка письма, если есть проблемы
#>###########################################################################################
function CheckGPU {
$temp_warning=$NULL
$util_warning=$NULL

$style = "<style>BODY{font-family: Arial; font-size: 10pt;}"
$style = $style + "TABLE{border: 1px solid black; border-collapse: collapse;}"
$style = $style + "TH{border: 1px solid black; background: #ADD8E6; padding: 5px; }"
$style = $style + "TD{border: 1px solid black; padding: 5px; }"
$style = $style + "TD.warning{background: #FF0000; border: 1px solid black; padding: 5px; }"
$style = $style + "</style>"

$full_stat= (& $NvidiaPath --query-gpu=index,name,temperature.gpu,fan.speed,utilization.gpu,power.draw --format=csv,nounits)  -replace '\[|\]' | ConvertFrom-Csv
$Body = $full_stat | ConvertTo-HTML -Head $style | Out-String

$full_stat | where{[int]$_.'temperature.gpu' -ge $temp_limit} | foreach {
                                                                         $temp_warning+=@($($_.'temperature.gpu'))
                                                                         log "Проблемы с температурой на GPU $($_.index) $($_.name) temp=$($_.'temperature.gpu') fan=$($_.'fan.speed %')% util=$($_.'utilization.gpu %')% power=$($_.'power.draw W')"
                                                                         BotSay -text "*$env:COMPUTERNAME* Проблемы с температурой на *GPU $($_.index)* $($_.name) temp=*$($_.'temperature.gpu')* fan=$($_.'fan.speed %')%" -markdown
                                                                        }
$full_stat | where{[int]$_.'utilization.gpu %' -lt $util_limit} | foreach {
                                                                           $util_warning+=@($($_.'utilization.gpu %'))
                                                                           log "Проблемы с утилизацией на GPU $($_.index) $($_.name) temp=$($_.'temperature.gpu') fan=$($_.'fan.speed %')% util=$($_.'utilization.gpu %')% power=$($_.'power.draw W')"
                                                                           BotSay -text "*$env:COMPUTERNAME* Проблемы с утилизацией на *GPU $($_.index)* $($_.name) util=*$($_.'utilization.gpu %')*% power=$($_.'power.draw W')"-markdown
                                                                          }
if ((($temp_warning -ne $NULL) -or ($util_warning -ne $NULL)) -and ($MailEnable)) {
    $temp_warning | ForEach-Object {$Body=$Body -replace "</td><td>$_</td>","</td><td class=warning>$_</td>"}
    $util_warning | ForEach-Object {$Body=$Body -replace "</td><td>$_</td>","</td><td class=warning>$_</td>"}
    $Password = ConvertTo-SecureString -String $MailPassword -AsPlainText -Force
    $Cred = New-Object System.Management.Automation.PSCredential $MailFrom, $Password
    Send-MailMessage –SmtpServer $MailSmtpServer -From $MailFrom -To $MailTo -Subject "$env:COMPUTERNAME Warning" -BodyAsHtml -Body $Body -Port $MailPort -Credential $Cred -UseSSL
}
else {log "Проверка GPU пройдена успешно!"}
}

function CheckConnect {
$ping = Test-Connection 8.8.8.8 -Quiet
if (!$ping) {Write-Host "Fail"}
else {Write-Host "Success"}
}

CheckGPU