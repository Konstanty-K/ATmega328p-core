'(
##############################################################################
ZEGAR Z PRZERWANIEM + UPTIME COUNTER + TIME_RELAY SCHEDULER
Clock_v3 - FINAL VERSION
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
Const Loop_time = 200
Const Timer1_prescale = 1024
Const Timer1_target_sec = 977
Const Sync_minutes = 6
Const Hour_seconds = 3600
Const Minute_seconds = 60
Const Day_hours = 24

' === TIME_RELAY CONSTANTS ===
Const Max_relays = 5
Const Relay_disabled = 2147483647

' === DECLARE SUBROUTINES ===
Declare Sub Register_time_relay(Byval Id As Byte , Byval Interval_seconds As Long)
Declare Sub Check_time_relays()
Declare Sub Execute_relay_callback(Byval Relay_id As Byte)

' === TIMER1 ===
Config Timer1 = Timer , Prescale = Timer1_prescale
On Timer1 Timer1_Isr Nosave
Enable Timer1
Enable Interrupts

' === TIMER0 ===
Config Timer0 = Timer , Prescale = 64

' === ZMIENNE CZASU (UPTIME) ===
Dim Day As Long
Dim Hour As Byte
Dim Minute As Byte
Dim Second As Byte
Dim Loop_Time_Ms As Word
Dim Idle_Time As Word
Dim Sync_Flag As Bit
Dim Remainder As Byte
Dim Isr_Counter As Word
Dim Isr_Counter_Total As Long

' === TIME_RELAY STATE ===
Dim Total_seconds As Long
Dim Relay_interval_seconds(Max_relays) As Long
Dim Relay_last_trigger(Max_relays) As Long
Dim Relay_enabled(Max_relays) As Byte
Dim Relay_index As Byte
Dim Relay_id As Byte

' === Utility Variables ===
Dim Temp_Value As Single
Dim Input_State As Byte
Dim Output_State As Byte

' === STRINGI DLA DISPLAY ===
Dim Day_str As String * 10
Dim Hour_str As String * 2
Dim Minute_str As String * 2
Dim Second_str As String * 2
Dim Isr_str As String * 5

' === INICJALIZACJA ===
Cls
Lcd "Inicjalizacja..."
Wait 1
Timer1 = 65536 - Timer1_target_sec
Start Timer1
Day = 0
Hour = 0
Minute = 0
Second = 0
Sync_Flag = 0
Loop_Time_Ms = 0
Isr_Counter = 0
Isr_Counter_Total = 0
Total_seconds = 0

' === INITIALIZE RELAYS ===
For Relay_index = 0 To Max_relays - 1
  Relay_interval_seconds(Relay_index) = Relay_disabled
  Relay_last_trigger(Relay_index) = 0
  Relay_enabled(Relay_index) = 0
Next Relay_index

' === REJESTRACJA TIME_RELAYS ===
' Relay 0: Co 10 sekund (test)
Call Register_time_relay(0 , 10)

' Relay 1: Co 1 godzinie (3600 sekund)
Call Register_time_relay(1 , 3600)

' Relay 2: Co 1 dniu (86400 sekund)
Call Register_time_relay(2 , 86400)

' === GŁÓWNA PĘTLA ===
Do
  Timer0 = 0
  Start Timer0

  Gosub Check_Inputs
  Gosub Execute_Logic
  Gosub Update_Outputs

  ' === SPRAWDŹ TIME_RELAY ===
  Call Check_time_relays()

  If Sync_Flag = 1 Then
    Sync_Flag = 0
    Gosub Sync_With_Sim800l
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
  Incr Isr_Counter_Total
  Incr Second
  Incr Total_seconds                ' ‹ Licznik dla time_relay

  If Second >= Minute_seconds Then
    Second = 0
    Incr Minute

    If Minute >= Minute_seconds Then
      Minute = 0
      Incr Hour

      If Hour >= Day_hours Then
        Hour = 0
        Incr Day
      End If
    End If
  End If

  Remainder = Minute Mod Sync_minutes
  If Remainder = 0 And Second = 0 Then
    Sync_Flag = 1
  End If
Return

' ============================================================
' === TIME_RELAY FUNCTIONS ===
' ============================================================

Sub Register_time_relay(Byval Id As Byte , Byval Interval_seconds As Long)
  ' Zarejestruj nowy relay
  ' Id: 0-4 (Max_relays)
  ' Interval_seconds: co ile sekund uruchomić?

  If Id >= Max_relays Then
    Return
  End If

  Relay_interval_seconds(Id) = Interval_seconds
  Relay_last_trigger(Id) = 0
  Relay_enabled(Id) = 1
End Sub

Sub Check_time_relays()
  ' Sprawdź czy jakiś relay powinien się uruchomić
  Dim Seconds_since_last_trigger As Long

  For Relay_index = 0 To Max_relays - 1
    If Relay_enabled(Relay_index) = 1 Then
      If Relay_interval_seconds(Relay_index) <> Relay_disabled Then
        Seconds_since_last_trigger = Total_seconds - Relay_last_trigger(Relay_index)

        If Seconds_since_last_trigger >= Relay_interval_seconds(Relay_index) Then
          Relay_last_trigger(Relay_index) = Total_seconds
          Call Execute_relay_callback(Relay_index)
        End If
      End If
    End If
  Next Relay_index
End Sub


Sub Execute_relay_callback(Byval Relay_id As Byte)
  ' Callback dla konkretnego relay'a

  Select Case Relay_id
    Case 0
      ' Relay 0: Co 10 sekund (test)
      Locate 4 , 1
      Lcd "RELAY 0: 10s trigger"
      Wait 1
      ' TODO: Call External_function_10s()

    Case 1
      ' Relay 1: Co 1 godzinie
      Locate 4 , 1
      Lcd "RELAY 1: 1h trigger "
      Wait 1
      ' TODO: Call External_function_1h()

    Case 2
      ' Relay 2: Co 1 dniu
      Locate 4 , 1
      Lcd "RELAY 2: 1d trigger "
      Wait 1
      ' TODO: Call External_function_1d()

    Case Else
  End Select

  Locate 4 , 1
  Lcd "                    "
End Sub

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
  Day_str = Str(Day)
  Hour_str = Str(Hour)
  Minute_str = Str(Minute)
  Second_str = Str(Second)
  Isr_str = Str(Isr_Counter)

  ' Linia 1: UPTIME - Dni:Godziny:Minuty:Sekundy
  Locate 1 , 1
  Lcd "UP: " ; Day_str ; "d " ; Format(Hour_str , "00") ; ":" ; Format(Minute_str , "00") ; ":" ; Format(Second_str , "00")

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
