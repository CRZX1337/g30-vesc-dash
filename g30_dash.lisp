; -> User parameters (change these to your needs)
(def software-adc 1)
(def min-adc-throttle 0.1)
(def min-adc-brake 0.1)

(def show-batt-in-idle 1)
(def min-speed 1)
(def button-safety-speed (/ 0.1 3.6)) ; disabling button above 0.1 km/h (due to safety reasons)
(def show-temp-when-idle 1) ; Show ESC temperature in error field when standing still
(def show-current-as-batt 1) ; Show motor current as battery percentage in secret mode when riding!
(def field-tweaking-blink-light 1) ; Enable blinking light during field tweaking mode (1 = enabled, 0 = disabled)

; Field tweaking mode variables
(def field-tweaking-mode 0) ; 0 = off, 1 = active
(def field-tweaking-value 0) ; The value being adjusted
(def brake-press-count 0) ; Count of full brake presses
(def last-brake-state 0) ; For detecting brake press edges
(def last-throttle-state 0) ; For detecting throttle press edges
(def brake-hold-start-time 0) ; Time when brake hold started for exit
(def brake-hold-duration 0) ; Current brake hold duration for exit
(def throttle-hold-start-time 0) ; Time when throttle hold started for decrease
(def throttle-hold-duration 0) ; Current throttle hold duration for decrease
(def light-blink-timer 0) ; Timer for blinking light in tweaking mode
(def light-blink-state 0) ; Current blink state (0 or 1)

; Speed modes (km/h, watts, current scale)
(def eco-speed (/ 7 3.6))
(def eco-current 0.6)
(def eco-watts 400)
(def eco-fw 0)
(def drive-speed (/ 17 3.6))
(def drive-current 0.7)
(def drive-watts 500)
(def drive-fw 0)
(def sport-speed (/ 21 3.6))
(def sport-current 1.0)
(def sport-watts 700)
(def sport-fw 0)

; Secret speed modes. To enable, press the button 2 times while holding break and throttle at the same time.
(def secret-enabled 1)
(def secret-eco-speed (/ 1000 3.6))
(def secret-eco-current 0.3)
(def secret-eco-watts 1250)
(def secret-eco-fw 0)
(def secret-drive-speed (/ 1000 3.6))
(def secret-drive-current 0.7)
(def secret-drive-watts 1500000)
(def secret-drive-fw 0)
(def secret-sport-speed (/ 1000 3.6)) ; 1000 km/h easy
(def secret-sport-current 1.0)
(def secret-sport-watts 1500000)
(def secret-sport-fw 0)

; -> Code starts here (DO NOT CHANGE ANYTHING BELOW THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING)

; Load VESC CAN code serer
(import "pkg@://vesc_packages/lib_code_server/code_server.vescpkg" 'code-server)
(read-eval-program code-server)

; Packet handling
(uart-start 115200 'half-duplex)
(gpio-configure 'pin-rx 'pin-mode-in-pu)
(define tx-frame (array-create 15))
(bufset-u16 tx-frame 0 0x5AA5) ;Ninebot protocol
(bufset-u8 tx-frame 2 0x06) ;Payload length is 5 bytes
(bufset-u16 tx-frame 3 0x2021) ; Packet is from ESC to BLE
(bufset-u16 tx-frame 5 0x6400) ; Packet is from ESC to BLE
(def uart-buf (array-create 64))

; Button handling

(def presstime (systime))
(def presses 0)

; Mode states

(def off 0)
(def lock 0)
(def speedmode 4)
(def light 0)
(def unlock 0)



; Sound feedback

(def feedback 0)

(if (= software-adc 1)
    (app-adc-detach 3 1)
    (app-adc-detach 3 0)
)

(defun adc-input(buffer) ; Frame 0x65
    {
        (let ((current-speed (* (get-speed) 3.6))
            (throttle (/(bufget-u8 uart-buf 5) 77.2)) ; 255/3.3 = 77.2
            (brake (/(bufget-u8 uart-buf 6) 77.2)))
            {
                (if (< throttle 0)
                    (setf throttle 0))
                (if (> throttle 3.3)
                    (setf throttle 3.3))
                (if (< brake 0)
                    (setf brake 0))
                (if (> brake 3.3)
                    (setf brake 3.3))

                ; Pass through throttle and brake to VESC
                (app-adc-override 0 throttle)
                (app-adc-override 1 brake)
            }
        )
    }
)

(defun handle-features()
    {
        (if (or (or (= off 1) (= lock 1) (< (* (get-speed) 3.6) min-speed)))
            (if (not (app-is-output-disabled)) ; Disable output when scooter is turned off
                {
                    (app-adc-override 0 0)
                    (app-adc-override 1 0)
                    (app-disable-output -1)
                    (set-current 0)
                    ;(loopforeach i (can-list-devs)
                    ;    (canset-current i 0)
                    ;)
                }

            )
            (if (app-is-output-disabled) ; Enable output when scooter is turned on
                (app-disable-output 0)
            )
        )

        (if (= lock 1)
            {
                (set-current-rel 0) ; No current input when locked
                (if (> (* (get-speed) 3.6) min-speed)
                    (set-brake-rel 1) ; Full power brake
                    (set-brake-rel 0) ; No brake
                )
            }
        )
        
        ; Handle field tweaking mode logic
        (handle-field-tweaking)
    }
)

(defun update-dash(buffer) ; Frame 0x64
    {
        (var current-speed (* (l-speed) 3.6))
        (var battery (*(get-batt) 100))
        
        ; Calculate current percentage for battery display when in secret mode
        (var current-percentage battery) ; Default to actual battery percentage
        (if (and (= show-current-as-batt 1) (= unlock 1) (> current-speed min-speed))
            {
                (var max-current (conf-get 'l-current-max))
                (var current-abs (abs (get-current)))
                (if (> max-current 0)
                    {
                        (var current-pct (round (* (/ current-abs max-current) 100)))
                        (if (> current-pct 100)
                            (set 'current-percentage 100)
                            (set 'current-percentage current-pct)
                        )
                    }
                )
            }
        )

        ; mode field (1=drive, 2=eco, 4=sport, 8=charge, 16=off, 32=lock)
        (if (= off 1)
            (bufset-u8 tx-frame 7 16)
            (if (= lock 1)
                (bufset-u8 tx-frame 7 32) ; lock display
                (if (or (> (get-temp-fet) 60) (> (get-temp-mot) 60)) ; temp icon will show up above 60 degree
                    (bufset-u8 tx-frame 7 (+ 128 speedmode))
                    (bufset-u8 tx-frame 7 speedmode)
                )
            )
        )

        ; batt field - show field tweaking value when in tweaking mode and standing still
        (if (and (= field-tweaking-mode 1) (= unlock 1) (<= current-speed min-speed))
            (bufset-u8 tx-frame 8 field-tweaking-value) ; Show tweaking value as battery percentage
            (if (and (= show-batt-in-idle 1) (= unlock 1) (<= current-speed min-speed))
                (bufset-u8 tx-frame 8 battery) ; Show real battery when idle in secret mode
                (bufset-u8 tx-frame 8 current-percentage) ; Normal battery display
            )
        )

        ; light field - blink during field tweaking mode (if enabled)
        (if (= off 0)
            (if (and (= field-tweaking-mode 1) (= field-tweaking-blink-light 1))
                {
                    ; Blink light every 500ms when in field tweaking mode
                    (var current-time (systime))
                    (if (>= (- current-time light-blink-timer) 500)
                        {
                            (set 'light-blink-state (bitwise-xor light-blink-state 1))
                            (set 'light-blink-timer current-time)
                        }
                    )
                    (bufset-u8 tx-frame 9 light-blink-state)
                }
                (bufset-u8 tx-frame 9 light)
            )
            (bufset-u8 tx-frame 9 0)
        )

        ; beep field
        (if (= lock 1)
            (if (> current-speed min-speed)
                (bufset-u8 tx-frame 10 1) ; beep lock
                (bufset-u8 tx-frame 10 0))
            (if (> feedback 0)
                {
                    (bufset-u8 tx-frame 10 1)
                    (set 'feedback (- feedback 1))
                }
                (bufset-u8 tx-frame 10 0)
            )
        )

        ; speed field
        (if (= (+ show-batt-in-idle unlock) 2)
            (if (> current-speed 1)
                (bufset-u8 tx-frame 11 current-speed)
                (if (and (= field-tweaking-mode 1) (<= current-speed min-speed))
                    (bufset-u8 tx-frame 11 field-tweaking-value) ; Show tweaking value when in field tweaking mode and idle
                    (bufset-u8 tx-frame 11 battery) ; Show real battery in idle mode
                )
            )
            (bufset-u8 tx-frame 11 current-speed)
        )

        ; error field - disable temp display in field tweaking mode
        (if (= field-tweaking-mode 1)
            (bufset-u8 tx-frame 12 0) ; No error display in field tweaking mode
            (if (and (= show-temp-when-idle 1) (<= current-speed min-speed) (= (get-fault) 0) (= unlock 1))
                (bufset-u8 tx-frame 12 (round (get-temp-fet))) ; Show ESC temperature when stationary with no errors and in secret mode
                (bufset-u8 tx-frame 12 (get-fault))             ; Otherwise show actual error code
            )
        )

        ; calc crc

        (var crcout 0)
        (looprange i 2 13
        (set 'crcout (+ crcout (bufget-u8 tx-frame i))))
        (set 'crcout (bitwise-xor crcout 0xFFFF))
        (bufset-u8 tx-frame 13 crcout)
        (bufset-u8 tx-frame 14 (shr crcout 8))

        ; write
        (uart-write tx-frame)
    }
)

(defun read-frames()
    (loopwhile t
        {
            (uart-read-bytes uart-buf 3 0)
            (if (= (bufget-u16 uart-buf 0) 0x5aa5)
                {
                    (var len (bufget-u8 uart-buf 2))
                    (var crc len)
                    (if (and (> len 0) (< len 60)) ; max 64 bytes
                        {
                            (uart-read-bytes uart-buf (+ len 6) 0) ;read remaining 6 bytes + payload, overwrite buffer

                            (let ((code (bufget-u8 uart-buf 2)) (checksum (bufget-u16 uart-buf (+ len 4))))
                                {
                                    (looprange i 0 (+ len 4) (set 'crc (+ crc (bufget-u8 uart-buf i))))

                                    (if (= checksum (bitwise-and (+ (shr (bitwise-xor crc 0xFFFF) 8) (shl (bitwise-xor crc 0xFFFF) 8)) 65535)) ;If the calculated checksum matches with sent checksum, forward comman
                                        (handle-frame code)
                                    )
                                }
                            )
                        }
                    )
                }
            )
        }
    )
)

(defun handle-frame(code)
    {
        (if (and (= code 0x65) (= software-adc 1))
            (adc-input uart-buf)
        )

        (if(= code 0x64)
            (update-dash uart-buf)
        )
    }
)

(defun handle-button()
    (if (= presses 1) ; single press
        (if (= off 1) ; is it off? turn on scooter again
            {
                (set 'off 0) ; turn on
                (set 'feedback 1) ; beep feedback
                (set 'unlock 0) ; Disable unlock on turn off
                (apply-mode) ; Apply mode on start-up
                (stats-reset) ; reset stats when turning on
            }
            (if (and (= unlock 1) (>= (get-adc-decoded 0) 0.9)) ; In secret mode with full throttle (90% throttle or more)
                {
                    (set 'show-temp-when-idle (bitwise-xor show-temp-when-idle 1)) ; toggle temperature display
                    (set 'feedback (+ 1 show-temp-when-idle)) ; beep feedback: 1 beep for off, 2 beeps for on
                }
                (set 'light (bitwise-xor light 1)) ; toggle light
            )
        )
        (if (>= presses 2) ; double press
            {
                (if (> (get-adc-decoded 1) min-adc-brake) ; if brake is pressed
                    (if (and (= secret-enabled 1) (> (get-adc-decoded 0) min-adc-throttle))
                        {
                            (set 'unlock (bitwise-xor unlock 1))
                            (set 'feedback 2) ; beep 2x
                            (apply-mode)
                        }
                        {
                            (set 'unlock 0)
                            (apply-mode)
                            (set 'lock (bitwise-xor lock 1)) ; lock on or off
                            (set 'feedback 1) ; beep feedback
                        }
                    )
                    {
                        (if (= lock 0)
                            {
                                (cond
                                    ((= speedmode 1) (set 'speedmode 4))
                                    ((= speedmode 2) (set 'speedmode 1))
                                    ((= speedmode 4) (set 'speedmode 2))
                                )
                                (apply-mode)
                            }
                        )
                    }
                )
            }
        )
    )
)

(defun handle-holding-button()
    {
        (if (= (+ lock off) 0) ; it is locked and off?
            {
                (set 'unlock 0) ; Disable unlock on turn off
                (apply-mode)
                (set 'off 1) ; turn off
                (set 'light 0) ; turn off light
                (set 'feedback 1) ; beep feedback
            }
        )
    }
)

(defun reset-button()
    {
        (set 'presstime (systime)) ; reset press time again
        (set 'presses 0)
    }
)

; Speed mode implementation

(defun apply-mode()
    (if (= unlock 0)
        (if (= speedmode 1)
            (configure-speed drive-speed drive-watts drive-current drive-fw)
            (if (= speedmode 2)
                (configure-speed eco-speed eco-watts eco-current eco-fw)
                (if (= speedmode 4)
                    (configure-speed sport-speed sport-watts sport-current sport-fw)
                )
            )
        )
        (if (= speedmode 1)
            (configure-speed secret-drive-speed secret-drive-watts secret-drive-current secret-drive-fw)
            (if (= speedmode 2)
                (configure-speed secret-eco-speed secret-eco-watts secret-eco-current secret-eco-fw)
                (if (= speedmode 4)
                    (configure-speed secret-sport-speed secret-sport-watts secret-sport-current secret-sport-fw)
                )
            )
        )
    )
)

(defun configure-speed(speed watts current fw)
    {
        (set-param 'max-speed speed)
        (set-param 'l-watt-max watts)
        (set-param 'l-current-max-scale current)
        (set-param 'foc-fw-current-max fw)
    }
)

(defun handle-field-tweaking()
    {
        (var current-speed (* (get-speed) 3.6))
        (var brake-level (get-adc-decoded 1))
        (var throttle-level (get-adc-decoded 0))
        (var current-time (systime))
        
        ; Check if we're in secret mode and standing still
        (if (and (= unlock 1) (<= current-speed min-speed))
            {
                ; Detect brake press edge (transition from not pressed to fully pressed)
                (if (and (>= brake-level 0.9) (= last-brake-state 0) (= field-tweaking-mode 0))
                    {
                        (set 'brake-press-count (+ brake-press-count 1))
                        (set 'feedback 1) ; Single beep for each brake press
                        
                        ; Enter field tweaking mode after 2 full brake presses
                        (if (>= brake-press-count 2)
                            {
                                (set 'field-tweaking-mode 1)
                                (set 'feedback 3) ; 3 beeps to indicate entering tweaking mode
                                ; Initialize with current fw value based on mode
                                (if (= speedmode 1)
                                    (set 'field-tweaking-value secret-drive-fw)
                                    (if (= speedmode 2)
                                        (set 'field-tweaking-value secret-eco-fw)
                                        (set 'field-tweaking-value secret-sport-fw)
                                    )
                                )
                                (set 'brake-press-count 0) ; Reset counter
                            }
                        )
                    }
                )
                
                ; Update brake state for edge detection
                (if (>= brake-level 0.9)
                    (set 'last-brake-state 1)
                    (set 'last-brake-state 0)
                )
                
                ; Handle exit from tweaking mode with 5-second brake hold
                (if (= field-tweaking-mode 1)
                    {
                        ; Check if brake is fully pressed for exit
                        (if (>= brake-level 0.9)
                            {
                                ; Start tracking brake hold time if not already tracking
                                (if (= brake-hold-start-time 0)
                                    (set 'brake-hold-start-time current-time)
                                )
                                
                                ; Calculate how long brake has been held
                                (set 'brake-hold-duration (- current-time brake-hold-start-time))
                                
                                ; Exit field tweaking mode after 5 seconds of brake hold
                                (if (>= brake-hold-duration 5000)
                                    {
                                        (set 'field-tweaking-mode 0)
                                        (set 'feedback 2) ; 2 beeps to indicate saving and exiting
                                        ; Save the value to the appropriate fw variable
                                        (if (= speedmode 1)
                                            (set 'secret-drive-fw field-tweaking-value)
                                            (if (= speedmode 2)
                                                (set 'secret-eco-fw field-tweaking-value)
                                                (set 'secret-sport-fw field-tweaking-value)
                                            )
                                        )
                                        (apply-mode) ; Apply the new settings
                                        (set 'brake-hold-start-time 0)
                                        (set 'brake-hold-duration 0)
                                    }
                                )
                            }
                            {
                                ; Brake not fully pressed, reset exit tracking
                                (set 'brake-hold-start-time 0)
                                (set 'brake-hold-duration 0)
                            }
                        )
                        
                        ; Handle throttle presses for value adjustment in tweaking mode
                        ; Detect throttle press edge (transition from not pressed to pressed)
                        (if (and (>= throttle-level 0.1) (= last-throttle-state 0))
                            {
                                (set 'field-tweaking-value (+ field-tweaking-value 1))
                                ; Limit value to reasonable range (0-100)
                                (if (> field-tweaking-value 100)
                                    (set 'field-tweaking-value 100)
                                )
                                (set 'feedback 1) ; Single beep for increment
                            }
                        )
                        
                        ; Handle throttle hold for decreasing value
                        (if (>= throttle-level 0.1)
                            {
                                ; Start tracking throttle hold time if not already tracking
                                (if (= throttle-hold-start-time 0)
                                    (set 'throttle-hold-start-time current-time)
                                )
                                
                                ; Calculate how long throttle has been held
                                (set 'throttle-hold-duration (- current-time throttle-hold-start-time))
                                
                                ; Decrease value after 4 seconds of throttle hold
                                (if (>= throttle-hold-duration 4000)
                                    {
                                        (set 'field-tweaking-value (- field-tweaking-value 1))
                                        ; Limit value to reasonable range (0-100)
                                        (if (< field-tweaking-value 0)
                                            (set 'field-tweaking-value 0)
                                        )
                                        (set 'feedback 1) ; Single beep for decrement
                                        ; Reset hold time to allow continuous decreasing
                                        (set 'throttle-hold-start-time current-time)
                                    }
                                )
                            }
                            {
                                ; Throttle not pressed, reset hold tracking
                                (set 'throttle-hold-start-time 0)
                                (set 'throttle-hold-duration 0)
                            }
                        )
                        
                        ; Update throttle state for edge detection
                        (if (>= throttle-level 0.1)
                            (set 'last-throttle-state 1)
                            (set 'last-throttle-state 0)
                        )
                        
                        ; Apply field-tweaking value in real-time during tweaking mode
                        (set-param 'foc-fw-current-max field-tweaking-value)
                    }
                )
            }
            {
                ; Not in secret mode or not standing still, exit tweaking mode and reset counters
                (if (= field-tweaking-mode 1)
                    {
                        (set 'field-tweaking-mode 0)
                        (apply-mode) ; Restore normal fw values
                    }
                )
                (set 'brake-press-count 0)
                (set 'last-brake-state 0)
                (set 'last-throttle-state 0)
                (set 'brake-hold-start-time 0)
                (set 'brake-hold-duration 0)
                (set 'throttle-hold-start-time 0)
                (set 'throttle-hold-duration 0)
                (set 'light-blink-timer 0)
                (set 'light-blink-state 0)
            }
        )
    }
)

(defun set-param (param value)
    {
        (conf-set param value)
        (loopforeach id (can-list-devs)
            (looprange i 0 5 {
                (if (eq (rcode-run id 0.1 `(conf-set (quote ,param) ,value)) t) (break t))
                false
            })
        )
    }
)

(defun l-speed()
    {
        (var l-speed (get-speed))
        (loopforeach i (can-list-devs)
            {
                (var l-can-speed (canget-speed i))
                (if (< l-can-speed l-speed)
                    (set 'l-speed l-can-speed)
                )
            }
        )

        l-speed
    }
)

(defun button-logic()
    {
        ; Assume button is not pressed by default
        (var buttonold 0)
        (loopwhile t
            {
                (var button (gpio-read 'pin-rx))
                (sleep 0.05) ; wait 50 ms to debounce
                (var buttonconfirm (gpio-read 'pin-rx))
                (if (not (= button buttonconfirm))
                    (set 'button 0)
                )

                (if (> buttonold button)
                    {
                        (set 'presses (+ presses 1))
                        (set 'presstime (systime))
                    }
                    (button-apply button)
                )

                (set 'buttonold button)
                (handle-features)
            }
        )
    }
)

(defun button-apply(button)
    {
        (var time-passed (- (systime) presstime))
        (var is-active (or (= off 1) (<= (get-speed) button-safety-speed)))

        (if (> time-passed 2500) ; after 2500 ms
            (if (= button 0) ; check button is still pressed
                (if (> time-passed 6000) ; long press after 6000 ms
                    {
                        (if is-active
                            (handle-holding-button)
                        )
                        (reset-button) ; reset button
                    }
                )
                (if (> presses 0) ; if presses > 0
                    {
                        (if is-active
                            (handle-button) ; handle button presses
                        )
                        (reset-button) ; reset button
                    }
                )
            )
        )
    }
)

; Apply mode on start-up
(apply-mode)

; Spawn UART reading frames thread
(spawn 150 read-frames)
(button-logic) ; Start button logic in main thread - this will block the main thread