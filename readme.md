# sms watcher
A set of scripts and configurations to provide stable sms server.

## Hardware
* Linux box (raspberry pi, brix... etc.)
* USB 3G modem (Huawei E3533s-2)

## Software
* usb-modeswitch    # for change modem mode.
* gammu             # sms process daemon.

## Scripts
### sms_watcher
Watch folder which gammu will put recieved sms file in.
And dispatch recieved sms file to backend processor.

### Backend
* Email: Send sms content by email, need smtp server.
* Copy:  Copy sms to specified folder for further process.
* Http:  Send sms content by http, encrypted by same method as weixin_mp platform.
* Dummy: Not really a backend, just for log.

### weixin_mp
A weixin_mp app for send actually sms.

### weixin_commands
* send:  111111,aaaaaa: Send sms to number '111111' with content 'aaaaaa'.
* sms:   Check if there's new sms. (must use with sms_watcher http backend.)
* clear: Clear sms queue.

## Configuration
We have to set usb modem to sms mode use following command.

    usb_modeswitch -J -v 0x12d1 -p 0x15ca

if `/dev/ttyUSB2` is available, we are ready to send or receive sms.

Gammu should be counfigured as Files backend.

## Commands
some useful commandline.

    gammu-smsd-inject TEXT 123456 -unicode -text "Zkouška sirén"

### TODO
* better command line interface.
* pid support.
* start/stop support.
* monitor script.

### DONE
* this readme.
* process function plugin support.
* http plugin
* weixin_mp interface.

## Reference
* https://wammu.eu/docs/manual/smsd/inject.html#gammu-smsd-inject
* https://hui.lu/sms-on-raspberry-pi/
* https://wammu.eu/docs/manual/smsd/config.html#option-LogFile
