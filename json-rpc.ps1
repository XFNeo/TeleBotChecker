function JSON-RPC
{
$tcpConnection = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 2222)
$tcpStream = $tcpConnection.GetStream()
$reader = New-Object System.IO.StreamReader($tcpStream)
$writer = New-Object System.IO.StreamWriter($tcpStream)
$writer.AutoFlush = $true

$command='{"id":1, "method":"getstat"}'
$command=$command | ConvertTo-Json

$writer.WriteLine($command)
$response=$reader.ReadToEnd()
$JSONResponce = $response | ConvertFrom-Json

$reader.Close()
$writer.Close()
$tcpConnection.Close()
}
JSON-RPC
($JSONResponce.result.latency | Measure -Average).Average

$ts =  [timespan]::fromseconds($JSONResponce.uptime)

function Format-TimeSpan
{
    PARAM (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [TimeSpan]$TimeSpan
    )
        
    #By including the delimiters in the formatting string it's easier when we contatenate in the end
    $days = $TimeSpan.Days.ToString("00")
    $hours = $TimeSpan.Hours.ToString("\:00")
    $minutes = $TimeSpan.Minutes.ToString("\:00")
    $seconds = $TimeSpan.Seconds.ToString("\:00")
    $milliseconds = $TimeSpan.Milliseconds.ToString("\,000")

    Write-Output ($days + $hours + $minutes + $seconds)
}
$ts | Format-TimeSpan