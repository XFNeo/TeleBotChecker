
<#######################
XFNeoBot
25.01.18
v 0.5
Добавлена отправка файлов - не работает.
Добавлена возможность делать скриншоты
Исправлено имя файла при получении
Все настройки вынесены в отдельный файл
CheckGPU вынесен в отдельный скрипт
#######################>

#############################
# Variables
#############################
# путь до рабочей папки
$Path = Split-Path -Path ($MyInvocation.MyCommand.Path) -Parent

$GlobalScopeConfigFile = "$Path\config.csv"
# конфиг в котором хранятся настройки данного бота (для непрерывной интеграции)
if (test-path variable:\Config) { Remove-Variable Config }
New-Variable -Name Config -Option AllScope -Value ( Import-Csv -Path $GlobalScopeConfigFile )

#Если скрипт запущен на нескольких ПК, то $MainBot должен быть включен только на одном.
if ( $($Config | where { $_.Parameter -eq "MainBot" } | select -ExpandProperty Text) -eq "1" ) { $MainBot=$true }
else { $MainBot = $false }
#Пути до программ
$NvidiaPath=$Config | where { $_.Parameter -eq "NvidiaPath" } | select -ExpandProperty Text
$MSIAfterburnerPath=$Config | where { $_.Parameter -eq "MSIAfterburnerPath" } | select -ExpandProperty Text
$TeamViewerPath=$Config | where { $_.Parameter -eq "TeamViewerPath" } | select -ExpandProperty Text
#Имена файлов для проверки запущенных процессов
$ProcessToCheck1=$Config | where { $_.Parameter -eq "ProcessToCheck1" } | select -ExpandProperty Text #Тут обязательно майнер
$ProcessToCheck2=$Config | where { $_.Parameter -eq "ProcessToCheck2" } | select -ExpandProperty Text
$ProcessToCheck3=$Config | where { $_.Parameter -eq "ProcessToCheck3" } | select -ExpandProperty Text
# токен бота
$token=$Config | where { $_.Parameter -eq "token" } | select -ExpandProperty Text
# ID чата
$MyChatID=$Config | where { $_.Parameter -eq "MyChatID" } | select -ExpandProperty Text

# путь до рабочей папки
$Path = Split-Path -Path ($MyInvocation.MyCommand.Path) -Parent

<####################################################
    создаем переменные в глобальном скопе
#>###################################################
# разрешение работать если станет true то программа прекратит работать
if (test-path variable:\ExitFlag) { Remove-Variable ExitFlag }
New-Variable -Name ExitFlag -Option AllScope -Value $false

# переменная сообщений, сделано чтобы не пробрасывать везде сообщение
if (test-path variable:\Msg) { Remove-Variable Msg }
New-Variable -Name MSG -Option AllScope -Value $false

# время ожидания сообщения по дефолту 1 секунда
$ChatTimeOut = 1
# всегда ноль
$botUpdateId = "0"

$ExitFlag = $false

# фраза при скачивании
$FDownload = "The file has been downloaded"

# файл лога
$logFile = "$Path\log.txt"
# символ новой строки
$br = "%0A"

<############################################################################################
    логер
#>###########################################################################################
function log {
	param ( [parameter(Mandatory = $true)] [string]$Message )
	
    # проверка на длину лога
    if ( ($(Get-ChildItem $logFile).Length / 1mb) -gt 20 ) { Clear-Content $logFile }

	$DT = Get-Date -Format "yyyy.MM.dd HH:mm:ss"
	$MSGOut = $DT + "`t" + $Message
	Out-File -FilePath $logFile -InputObject $MSGOut -Append -encoding unicode
}

<############################################################################################
    получаем сообщения от телеграмм бота, парсим json
#>###########################################################################################
function Bot-Listen {
    param(  [string]$ChatTimeOut,
            [string]$UpdateId
         )

    $URL = "https://api.telegram.org/bot$token/getUpdates?offset=$UpdateId&timeout=$ChatTimeout"

    $Request = Invoke-WebRequest -Uri ( $URL ) -Method Get
    $str = $Request.content
    $ok = ConvertFrom-Json $Request.content
    $str = $ok.result | select -First 1
    $UpdId = ($str).update_id
    $str = ($str).message

    $isJPG = $false
    $docFileName = "!"
    $docFileID = ""
    $docFileSize = 0

    # проверки на тип сообщения
    if ( $($str.document).mime_type -eq "image/jpeg" ) {  $isJPG = $true  }

    if ( $($str.document).file_name -ne $null ) {
        $docFileName = ($str.document).file_name
        $docFileID = ($str.document).file_id
        $docFileSize = ($str.document).file_size
    }

    $props = [ordered]@{    ok = $ok.ok
                            UpdateId = $UpdId
                            Message_ID = $str.message_id
                            first_name = ($str.from).first_name
                            last_name = ($str.from).last_name
                            chat_id = ($str.chat).id
                            text = $str.text
                            isJPG = $isJPG
                            docFileName = $docFileName
                            docFileID = $docFileID
                            docFileSize = $docFileSize
                       }

    $obj = New-Object -TypeName PSObject -Property $props

    return $obj
}

<############################################################################################
    отправляет сообщение
#>###########################################################################################
function BotSay {
    param(  [string]$text = $(Throw "'-text' argument is mandatory"), [switch]$markdown, [switch]$MyChat )

    if($markdown) { $markdown_mode = "Markdown" } else {$markdown_mode = ""}

    $payload = @{ "parse_mode" = "$markdown_mode";
                  "disable_web_page_preview" = "True";
                }
    if($MyChat){$URL = "https://api.telegram.org/bot$token/sendMessage?chat_id=$MyChatID&text=$text"}
    else {$URL = "https://api.telegram.org/bot$token/sendMessage?chat_id=$($Msg.Chat_id)&text=$text"}

    $request = Invoke-WebRequest -Uri $URL -Method Post -ContentType "application/json;charset=utf-8" `
                    -Body (ConvertTo-Json -Compress -InputObject $payload)
}

<############################################################################################
    получает файл
#>###########################################################################################
function BotDownload {

    if ( $Msg.docFileName -ne "!" ) {
        $FileID = $Msg.docFileID
        $FileName = $Msg.docFileName
        $URL = "https://api.telegram.org/bot$token/getFile?file_id=$FileID"
        $Request = Invoke-WebRequest -Uri $URL
        
        $JSON = ConvertFrom-Json $Request.Content
        foreach ( $JSON in $((ConvertFrom-Json $Request.Content).result) ){
            $FilePath = $json.file_path
            $URL = "https://api.telegram.org/file/bot$token/$FilePath"
            $OutputFile = "$Path\documents\$FileName"
            Invoke-WebRequest -Uri $URL -OutFile $OutputFile

            BotSay -text "$FDownload. File name is ""$($JSON.file_path)""; size $($json.file_size) kb"
            log "получен файл: $($JSON.file_path) от $($msg.first_name) $($msg.last_name)из чата №$($msg.chat_id)"
        }
    }
}

<############################################################################################
    отправляет файл
#>###########################################################################################
function BotUpload {
    param ( [string]$FileName )

    $file = Get-Content -Path $FileName
    $uri = "https://api.telegram.org/bot$token/sendDocument?chat_id=$($Msg.chat_id)&document"
    Invoke-RestMethod -Method Post -Uri $uri -ContentType 'multipart/form-data' -Body [byte]$file
}

<############################################################################################
    обработка событий тут
#>###########################################################################################
function logic {
    $text = $Msg.text
    Write-Host "Logic start. Text is $text" -ForegroundColor Yellow
    
    # если есть какойто файл то скачаем его
    if ($MainBot){BotDownload}
    
    Switch ( $text ) {
        "$env:COMPUTERNAME Exit" {   # отключаемся
                    $ExitFlag = $true
                    log "команда выход из $($Msg.chat_id) от $($msg.first_name) $($msg.last_name)- Бот отключен"
                    BotSay -text "*$env:COMPUTERNAME Bot stoped*" -markdown
                    break
                    }
        'Help' { # команды
                    if ($MainBot){
                    log "команда вывода списка команд из $($Msg.chat_id) от $($msg.first_name) $($msg.last_name)"
                    $Message = Get-Content "$Path\help.txt"
                    BotSay -text $Message -markdown
                    }
                    }
        "$env:COMPUTERNAME Stat" { # Статистика по видеокартам
                    log "команда проверки видеокарт из $($Msg.chat_id) от $($msg.first_name) $($msg.last_name)"
                    $full_stat= (& $NvidiaPath --query-gpu=index,name,temperature.gpu,fan.speed,utilization.gpu,power.draw --format=csv,nounits)  -replace '\[|\]' | ConvertFrom-Csv
                    $full_stat | ForEach-Object {BotSay -text "GPU $($_.index) $($_.name) temp=$($_.'temperature.gpu') fan=$($_.'fan.speed %')% util=$($_.'utilization.gpu %')% power=$($_.'power.draw W')" -markdown}
                    }
        "$env:COMPUTERNAME Proc"{ # Проверка 3х процессов
                    $PSsResult=$null
                    log "команда проверки процессов из $($Msg.chat_id) от $($msg.first_name) $($msg.last_name)"
                    Get-Process -Name $ProcessToCheck1,$ProcessToCheck2,$ProcessToCheck3 | ForEach-Object {$PSsResult+=@($_.ProcessName)}
                    BotSay -text "*Запущенные процессы:*$br$PSsResult" -markdown
                    }
        "$env:COMPUTERNAME Screen"{ # Делает скриншот и отправляет в чат
                    $DT = Get-Date -Format "dd.MM.yyyy_HH-mm-ss"
                    $SSName="screenshot_$DT.jpg"
                    $SSPath="$Path\documents\$SSname"
                    [void][Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
                    $size = [Windows.Forms.SystemInformation]::VirtualScreen
                    $bitmap = new-object Drawing.Bitmap $size.width, $size.height
                    $graphics = [Drawing.Graphics]::FromImage($bitmap)
                    $graphics.CopyFromScreen($size.location,[Drawing.Point]::Empty, $size.size)
                    $graphics.Dispose()
                    $bitmap.Save($SSPath)
                    $bitmap.Dispose()
                    BotSay -text  "$env:COMPUTERNAME Cделан скриншот"
                    BotUpload -FileName $SSPath
                    break
                    }
        "$env:COMPUTERNAME Restart MSI"{
                    $MSIKill=$null
                    $MSIStart=$null
                    log "команда перезапуска MSIAfterburner из $($Msg.chat_id) от $($msg.first_name) $($msg.last_name)"
                    Stop-Process -Name MSIAfterburner -Force -ErrorVariable MSIKill
                    if ($MSIKill -ne $null) {BotSay -text "Kill Error"} 
                    Start-Process MSIAfterburner.exe -WorkingDirectory $MSIAfterburnerPath -ErrorVariable MSIStart
                    if ($MSIStart -ne $null) {BotSay -text "Start Error"} 
                    else {BotSay -text "MSIAfterburner has been restarted"}
                    }
        "$env:COMPUTERNAME Restart Miner"{
                    $miner=$null
                    log "команда перезапуска майнера из $($Msg.chat_id) от $($msg.first_name) $($msg.last_name)"
                    Stop-Process -Name $ProcessToCheck1 -Force -ErrorVariable miner
                    if ($miner -ne $null) {BotSay -text "Error"} 
                    else {BotSay -text "Miner has been successfully restarted"}
                    }
        "$env:COMPUTERNAME Restart TW"{
                    $TeamViewerKill=$null
                    $TeamViewerStart=$null
                    log "команда перезапуска TeamViewer из $($Msg.chat_id) от $($msg.first_name) $($msg.last_name)"
                    Stop-Process -Name TeamViewer -Force -ErrorVariable TeamViewerKill
                    if ($TeamViewerKill -ne $null) {BotSay -text "Kill Error"} 
                    Start-Process TeamViewer.exe -WorkingDirectory $TeamViewerPath -ErrorVariable TeamViewerStart
                    if ($TeamViewerStart -ne $null) {BotSay -text "Start Error"} 
                    else {BotSay -text "TeamViewerStart has been restarted"}
                    }
        "$env:COMPUTERNAME Reboot PC"{
                    log "команда перезагрузка из $($Msg.chat_id) от $($msg.first_name) $($msg.last_name)- Бот отключен и ПК будет перезагружен"
                    shutdown /r /t 100
                    if($lastexitcode -eq 0){
                                            BotSay -text "*$env:COMPUTERNAME Bot stoped and Rig will be rebooted*" -markdown 
                                            $ExitFlag = $true
                                            log "ПЕРЕЗАГРУЗКА ПК"
                                            }
                    else {
                          BotSay -text "Error"
                          log "НЕУДАЧНАЯ ПОПЫТКА ПЕРЕЗАГРУЗКИ"
                         }
                    }
        "List" {
                $PCName='```' + $env:COMPUTERNAME + '```'
                BotSay -text $PCName -markdown
               }
        default {
                if (($MainBot) -and (($text -NotMatch "Exit|Stat|Proc|Screen|Restart\sMSI|Restart\sMiner|Restart\sTW|Reboot\sPC"))){
                BotSay -text "*Help* for help" -markdown
                } 
        }
    }
}

<############################################################################################
    Начало работы отсюда
#>###########################################################################################
Write-Host 'Bot start' -ForegroundColor Green
BotSay -text "*$env:COMPUTERNAME Bot start*" -markdown -MyChat
log "БОТ ЗАПУЩЕН"

# главный цикл, циклимся пока не будет сброс
while ($ExitFlag -eq $False) {
#########Write-Host "новый цикл обработки сообщений" -ForegroundColor Green
    
    # получаем сообщение с телеграмма для данного бота
    $Msg = Bot-Listen -ChatTimeOut $ChatTimeOutSeconds -UpdateId $botUpdateId
    
    if ($Msg.UpdateId -gt 1) {
        log "пришло сообщение: $($msg.text) от $($msg.first_name) $($msg.last_name)из чата №$($msg.chat_id)"
        Write-Host "     пришло сообщение: $($msg.text) от $($msg.first_name) $($msg.last_name)из чата №$($msg.chat_id)"  -ForegroundColor Magenta
        $botUpdateId = $msg.UpdateId + 1

        # Проверяем ID чата с которого принято сообщение
        if ( $($Msg.chat_id) -eq $MyChatID ) {
            
            # обработчик сообщений, взаимодейтсвие с ботом тут
            logic
        }
    }

    if ($ExitFlag -eq $true) {
        # один пустой прогон чтобы не осталось не сервере последней команды
        $Msg = Bot-Listen -ChatTimeOut $ChatTimeOutSeconds -UpdateId $botUpdateId
    }
    
    Start-Sleep -Seconds 1
}