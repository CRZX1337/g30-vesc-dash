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

## Secret Modes

- Access unlimited modes by pressing button 2x while holding brake and throttle
- Removes software-imposed speed/power limits
- Allows using full hardware capability while staying compliant with regulations in normal mode
- Enabled through VESC Tool's hardware limits for safety
- Provides special displays:
  - ESC temperature shown in error code field when stationary
  - Motor current percentage shown as battery bar when riding

## Button Controls

- **Single Press**: Toggle lights (or turn on if off)
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