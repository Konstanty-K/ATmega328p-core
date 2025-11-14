'(
##############################################################################
ZEGAR Z PRZERWANIEM - CZYSTY KOD
##############################################################################
')

$regfile = "m328pdef.dat"
$crystal = 1000000
$baud = 4800
$hwstack = 32
$swstack = 640
$framesize = 64

Config Lcdpin = Pin , Db4 = Portb.2 , Db5 = Portb.3 , Db6 = Portb.4 , Db7 = Portb.5 , E = Portb.1 , Rs = Portb.0
Config Lcd = 20x4
Config Serialin = Buffered , Size = 160
Config 1Wire = PortD.4

' === CONSTANTS ===
Const Loop_time = 200               ' Target loop time in ms (PLC-like cycle)
Const Timer1_prescale = 1024        ' Timer1 prescaler
Const Timer1_target_sec = 977       ' Ticks for ~1 second at 1MHz, prescale 1024
Const Sync_minutes = 6              ' Synchronize every 6 minutes
Const Hour_seconds = 3600           ' Seconds in 1 hour
Const Minute_seconds = 60           ' Seconds in 1 minute

' === TIMER1 ===
Config Timer1 = Timer , Prescale = Timer1_prescale
On Timer1 Timer1_Isr Nosave
Enable Timer1
Enable Interrupts

' === TIMER0 ===
Config Timer0 = Timer , Prescale = 64

' === ZMIENNE ===
Dim Second As Byte
Dim Minute As Byte
Dim Hour As Byte
Dim Loop_Time_Ms As Word
Dim Idle_Time As Word
Dim Sync_Flag As Bit
Dim Hour_Done As Bit
Dim Remainder As Byte
Dim Isr_Counter As Word

' === Utility Variables ===
Dim Temp_Value As Single
Dim Input_State As Byte
Dim Output_State As Byte

' === INICJALIZACJA ===
Cls
Lcd "Inicjalizacja..."
Wait 1
Timer1 = 65536 - Timer1_target_sec
Start Timer1
Second = 0
Minute = 0
Hour = 0
Sync_Flag = 0
Hour_Done = 0
Loop_Time_Ms = 0
Isr_Counter = 0

' === G£ÓWNA PÊTLA ===
Do
  Timer0 = 0
  Start Timer0

  Gosub Check_Inputs
  Gosub Execute_Logic
  Gosub Update_Outputs

  If Sync_Flag = 1 Then
    Sync_Flag = 0
    Gosub Sync_With_Sim800l
  End If

  If Hour_Done = 1 Then
    Hour_Done = 0
    Locate 4 , 1
    Lcd "*** GODZINA! ***"
    Wait 2
    Locate 4 , 1
    Lcd "                "
  End If

  Gosub Display_Clock

  Stop Timer0
  Loop_Time_Ms = Timer0
  Loop_Time_Ms = Loop_Time_Ms * 64
  Loop_Time_Ms = Loop_Time_Ms / 1000

  If Loop_Time_Ms < Loop_time Then
    Idle_Time = Loop_time - Loop_Time_Ms
    Config Powermode = Idle
    Waitms Idle_Time
  End If
Loop

' === PRZERWANIE TIMER1 (~1 s) ===
Timer1_Isr:
  Timer1 = 65536 - Timer1_target_sec
  Incr Isr_Counter
  Incr Second

  If Second >= Minute_seconds Then
    Second = 0
    Incr Minute

    If Minute >= Minute_seconds Then
      Minute = 0
      Incr Hour
      If Hour >= 24 Then Hour = 0
      Hour_Done = 1
    End If
  End If

  ' === SYNCHRONIZACJA CO 6 MINUT ===
  Remainder = Minute Mod Sync_minutes
  If Remainder = 0 And Second = 0 Then
    Sync_Flag = 1
  End If
Return

' === SUBROUTINES ===
Check_Inputs:
  Input_State = Pind
  Temp_Value = 25.5
  Waitms 10
Return

Execute_Logic:
  If Temp_Value > 30 Then
    Output_State = 1
  Else
    Output_State = 0
  End If
  Waitms 20
Return

Update_Outputs:
  Waitms 10
Return

Sync_With_Sim800l:
  Locate 4 , 1
  Lcd "SYNC: SIM800L..."
  Wait 3
  Locate 4 , 1
  Lcd "                "
Return

Display_Clock:
  Dim Hour_str As String * 2
  Dim Minute_str As String * 2
  Dim Second_str As String * 2
  Dim Isr_str As String * 5

  Hour_str = Str(Hour)
  Minute_str = Str(Minute)
  Second_str = Str(Second)
  Isr_str = Str(Isr_Counter)

  ' Linia 1: Zegar HH:MM:SS (centered)
  Locate 1 , 6
  Lcd Format(Hour_str , "00") ; ":" ; Format(Minute_str , "00") ; ":" ; Format(Second_str , "00")

  ' Linia 2: ISR counter + Loop time
  Locate 2 , 1
  Lcd "ISR: " ; Isr_str ; " Loop: " ; Loop_Time_Ms ; "ms"

  ' Linia 3: Sync status
  Locate 3 , 1
  If Sync_Flag = 1 Then
    Lcd "Sync: ACTIVE        "
  Else
    Lcd "Sync: idle " ; Idle_Time ; "ms     "
  End If
Return
