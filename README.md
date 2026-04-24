# Logitech MX - Input Switcher

# 1 - Introduction
The scripts provided in this repository let you switch your Logitech keyboard and mouse with one click of a button to another channel. This repository contains scripts as well as the hidapitester tool for both Windows and Linux.
If you prefer the most current version of the hidapitester you can download this here: https://github.com/todbot/hidapitester.

What you need are multiple Logitech devices with Easy-Switch (typically a keyboard and a mouse), that are connected to two different machines either directly via bluetooth or via Logitech Unifying or Bolt receivers. All devices should connect to the machine A when set to channel 1 and to machine B when set to channel 2.

Then, on machine A we will set up a script that causes all devices to switch to channel 2 and bind this script to a key. On machine B, we set up a script that causes all devices to switch to channel 1 and bind this to the same key. As a result, by pressing this key your devices will switch back and forth between machines.

This tutorial assumes machine A is Windows and machine B is Linux. Of course, other setups are also possible. Just make sure to modify the names and target channel of the scripts accordingly.

# 2 - Windows
The **windows** folder contains the following files:
- `switch_to_2.bat` ... This simple batch script switches your devices to channel 2.
- `switch_to_2.vbs` ... This is a Visual Basic script that is just a wrapper around switch_to_2.bat. If you would execute switch_to_2.bat you would get a command prompt window that pops up every time. The switch_to_2.vbs script prevents this. So if you bind this script to a key on your keyboard you can switch to another channel without the window popping up.  
- `hidapitester.exe` ... The [hidapitester](https://github.com/todbot/hidapitester) tool for Windows so you don't have to download it manually.

### Setup

- Create the following folder `C:\Program Files\InputSwitcher` and copy the 3 files into this folder.
- Execute `switch_to_2.bat` manually to see if it is already working out of the box. If not, refer to Section 6 of this README to see how to tweak the script for your setup.
- Now use Logitech Options to assign a custom application to the "Menu" key and have it execute the program: `C:\Program Files\InputSwitcher\switch_to_2.vbs`.

# 3 - Linux
The **linux** folder contains the following files:
- `switch_to_1.sh` ... This simple shell script switches your devices to channel 1.
- `hidapitester` ... The [hidapitester](https://github.com/todbot/hidapitester) tool for Linux so you don't have to download it manually.
- `42-logitech-unify.rules` ... If you have Solaar installed this file is not needed. If you don't have Solaar installed you will probably notice that hidapitester does not work without root permissions (e.g. via sudo). This is because non-root users do not have raw access to the hid devices by default. So the 42-logitech-unify.rules file is a udev rule that allows raw access to the Logitech Unify receiver for non-root users. You might have to unplug your receiver and plug it in again.

### Setup

- From within the **linux** folder, copy the files to `/usr/bin`:
  ```bash
  cd linux
  sudo cp hidapitester /usr/bin
  sudo cp switch_to_1.sh /usr/bin
  sudo cp 42-logitech-unify.rules /usr/lib/udev/rules.d
  chmod +x /usr/bin/hidapitester
  chmod +x /usr/bin/switch_to_1.sh
  ```

- Now also execute `switch_to_1.sh` manually to see if it is already working out of the box. If not, refer to Section 6 of this README to see how to tweak the script for your setup.

- Finally, in your desktop environment of choice, define a custom shortcut. In my case I have used the "Menu" key on my keyboard and assigned it to execute **/usr/bin/switch_to_1.sh**.

# 4 - Mac
To get the Input Switcher working on a Mac refer to [the Mac README](mac/README.md)

# 5 - Bind the scripts to a key
Personally I use this key to bind the scripts to in both Windows and Linux.
![Keyboard](/images/keyboard.png)

## 5.1 - Windows key binding
In Windows you can use Logitech Options to bind the key to the **switch_to_2.vbs** script.

## 5.2 - Linux key binding
In Linux it depends on the desktop environment you use. In Gnome you can do it via: **Settings > Keyboard > View and Customize Shortcuts > Custom Shortcuts**
![Gnome](/images/gnome.png)

### In case the key you want to map is not recognized (GNOME environment)

You can download the awesome [Input Remapper](https://github.com/sezanzeb/input-remapper) tool, which allows you to detect your Logitech devices and more. 
1. Run the tool and click on the device (e.g., Logitech MX Keys) to land in the Presets tab.
2. Create a new Preset, double click it and land into the editor.
3. In the bottom left side of the window, click on the add button below "Input", press "Record" and press the button that you want to remap.
4. In output, you can create a new Macro. Target keyboard and press your combination of choice. This combination will be the one that you'll use to trigger the key binding in GNOME. I created something that I will never press: Control_L + Alt_L + Super_L + period
5. Once it has been created, give this preset a name, press the down arrow next to the rename field, and press apply.
6. You now can go in GNOME's custom shortcut editor and specify the script you want to run.
7. Remember to make sure that the script you created is executable and that hidapitester can as root (you have multiple choices, which have a number of security implications -- suid .sh script, sudo nopasswd for hidapitester... make an informed decision)

# 6 - Modify the scripts
Now you know how to set it up, but it probably does not work yet. This is because the delivered script files are geared toward a specific setup.
You will have to figure out what the correct command is that you have to send to your devices for them to switch.

Take the command from the Windows script `switch_to_2.bat` for example:
```bash
.\hidapitester.exe --vidpid 046D:C52B --usagePage 0xFF00 --usage 0x0001 --open --length 7 --send-output 0x10,0x01,0x09,0x1e,0x01,0x00,0x00
```  
The generic form of this command is:
```bash
.\hidapitester.exe --vidpid <vidpid> --usagePage <usagePage> --usage <usage> --open --length <length> --send-output <payload>
```

The remainder of this section will guide you through determining the correct values for all these parameters.

## VID/PID

VID = Vendor ID, PID = Product ID. Together, they uniquely identify a human interface device (HID). Logitech's Vendor ID is 046D, so the value will always be of the form `046D:<PID>`.

To find out the VID/PID of connected HIDs, use `.\hidapitester.exe --list` on Windows and `.\hidapitester --list` on Linux. In the results, look for Logitech devices (VID 046D).

> *When using a Logitech Unifying or Bolt receiver, just use the appropriate value listed below. For bluetooth devices, use `.\hidapitester.exe --usagePage 0xFF43 --usage 0x0202 --list` to filter out most of the unwanted results. Then look for results with PID 046D.*

**common values**
- `046D:C52B` is for the Logitech Unifying receiver (Product ID C52B)
- `046D:C548` is for the Logitech Bolt receiver (Product ID C548)
- `046D:B034` is for connecting to the MX Master 3S via bluetooth (Product ID B034)
- `046D:B378` is for connecting to the MX Keys S via bluetooth (Product ID B378)

## UsagePage and Usage

In the HID specification, devices organize their capabilities into Usage Pages and Usages.

**common values**
- `--usagePage 0xFF00 --usage 0x0001` for Unifying and Bolt receivers
- `--usagePage 0xFF43 --usage 0x0202` for devices connected directly via bluetooth

## Length

The length of the command to write to the HID in bytes. If the provided payload is shorter, it will be padded with zeros.

**common values**
- `--length 7` for short HID++ messages
- `--length 20` for long HID++ messages

> *Long HID++ messages are necessary for devices connected via bluetooth, while Unifying and Bolt receivers can deal with both, short and long messages. For simplicity, you can simply always choose a length of 20.*

## Payload

The payload contains the actual command that is send to the HID. Only the first 5 bytes of the command are relevant (the rest will be padded with zeros automatically):
```bash
--send-output <Message Type>,<Device Index>,<Feature Index>,<Function Index>,<Target Channel>
```

There are several methods of finding the correct payload values for your setup. The remainder of this section will explain more about the specific payload components. Refer to Section 7 to see how to obtain the complete playload for your setup in one go.

### Message Type

Indicates whether command is a short or long HID++ message (similar to Length).

**common values**
- `0x10` for short HID++ messages
- `0x11` for long HID++ messages

> *Long HID++ messages are necessary for devices connected via bluetooth, while Unifying and Bolt receivers can deal with both, short and long messages. For simplicity, you can simply always choose `0x11`.*

### Device Index

Index of device paired to the Unifying or Bold receiver. The index of a device is displayed in the Solaar GUI but this value can also be obtained by sniffing the traffic with Solaar or Wireshark. 

For devices connected directly via bluetooth, this can be any value (e.g. just use `0x00`).

### Feature and Function Index

Identifies the HID++ feature and the specific function within the feature for the _change host_ command.

**common values**
- `0x09,0x1E` for the MX Keys
- `0x0A,0x1?` for the MX Anywhere 3, MX Master 3S, and the MX Keys S. Here `?` can be any value from `0` to `F`.

### Target Channel

This is the channel the device should switch to.

**common values**
- `0x00` for channel 1
- `0x03` for channel 2
- `0x02` for channel 3

# 7 Find payload values

To find the payload values for your setup, the easiest method is to sniff the commands issued when manually triggering the channel switch.

## Using Solaar

If you have a Linux PC with Solaar installed, use the following command to sniff the payload Solaar uses for switching the channel of your device:
```bash
solaar -ddd config "<device>" change-host 1
```
Here, `<device>` should be a substring of the device name (e.g. "MX Mas" for a "MX Master 3S").

Solaar will cycle through all connected devices and find out the correct command for the requested device. The last command Solaar prints before successful completion contains the payload we want to send with the script.

For example, let the last command printed by Solaar be: 
```bash
logitech_receiver.base: (18) <= w[11 01 091E 01000000000000000000000000000000]
```
Then we know that we need a Message Type of `0x11`, Device Index of `0x01`, Feature Index of `0x09`, Function Index of `0x1E`, and Target Channel of `0x01`.

## Using Wireshark USB capture
It is very easy to capture USB traffic via Wireshark and find commands send to the HID devices. Install [Wireshark](https://www.wireshark.org) including USBPcap and start tracing the USB Hub the dongle is connected. Filter protocol USBHID to find the SET_REPORT request changing the channel or other actions applied to the Logitech device. You can trigger commands using Logitech Options+. The data fragment is exactly the command you need for hidapitester.exe, as shown in this example:

**Switch Logitech Craft Keyboard to Channel 3**

*.\hidapitester.exe --vidpid 046D:C52B --usage 0x0001 --usagePage 0xFF00 --open --length 7 --send-output 0x10,0x05,0x08,0x1a,0x02,0x00,0x00*

![Wireshark](/images/wireshark.png)
