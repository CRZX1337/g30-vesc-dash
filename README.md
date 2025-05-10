# Ninebot G30 Dashboard VESC Integration

This LISP script enables integration between VESC controllers and the Ninebot G30 dashboard. It provides full dashboard functionality with speed modes, lights, and special features.

## Features

- **Speed Mode Selection**: 
  - Regular modes: Eco, Drive, and Sport
  - Secret modes: Unlimited versions of each mode with hardware-limited capabilities
- **Dashboard Integration**: 
  - Full display of speed, battery, and error codes
  - Temperature display in error field when stationary in secret mode
  - Motor current visualization via battery bar in secret mode
- **Light Control**: Toggle lights on/off via dashboard button
- **Lock Function**: Lock/unlock the scooter via dashboard button
- **Button Control**: Use the dashboard button for various functions

## Special Features

- **Enhanced Dashboard Displays**:
  - Real-time ESC temperature monitoring - Shows the actual temperature value in the error code field when standing still in secret mode, giving you a quick heat check before riding
  - Dynamic motor current visualization - Converts the battery bar display into a real-time power meter showing motor current as a percentage of maximum when riding in secret mode

## Button Controls

- **Single Press**: 
  - Normal: Toggle lights (or turn on if off)
  - In secret mode with full throttle: Toggle ESC temperature display
- **Double Press**: 
  - With brake pressed: Lock/unlock
  - Without brake: Change speed mode
  - With brake + throttle: Enable/disable secret modes
- **Long Press (6 seconds)**: Turn off

## Configuration

User parameters at the top of the script can be modified to:
- Adjust speed limits
- Change power settings
- Enable/disable features

## Credits

This project is based on the work from [vesc_m365_dash](https://github.com/m365fw/vesc_m365_dash) by [Izuna](https://github.com/1zun4), which provides VESC 6.0 Lisp implementation for M365/NineBot BLE compatibility. 