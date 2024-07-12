# README #

## 帮助改进中文翻译
欢迎帮忙改进编程界面的中文翻译, 翻译文件位于 [translations/简体中文.txt](https://github.com/MicroBlocksCN/smallvm/blob/devCN/translations/%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87.txt)

## 开发相关

当前仓库的 devCN 分支(部署在 https://microblocksfun.cn/run )会定期变基(git rebase)到官方的 pilot 版本(最新版本 https://microblocks.fun/run-pilot) 上.

开发者应该确保 pull requests 的代码总是基于最新的 devCN 分支.

推荐的工作流程:

1. fork 当前项目, 并将其克隆到你本地目录
2. 将 MicroBlocksCN 仓库添加为远程仓库: `git remote add MicroBlocksCN https://github.com/MicroBlocksCN/smallvm`
3. 每次创建开发分支之前, 拉取 MicroBlocksCN 仓库最新代码: `git fetch MicroBlocksCN` 
4. 从最新的远程分支 MicroBlocksCN/devCN 中创建你的开发分支(以 test-xxx 为例): `git checkout -b test-xxx MicroBlocksCN/devCN`: 
5. 提交你的开发分支, 并创建 pull request

**如果你想贡献积木库(ubl文件), 但觉得使用 git 太繁琐, 可以直接将库文件发给我(wuwenjie718@gmail.com), 我来代为提交**

## MicroBlocks Website ##

This repository contains the source code for MicroBlocks.
To learn more about MicroBlocks and how to use it please visit the MicroBlocks website,
<http://microblocks.fun>

## What is MicroBlocks? ##

[MicroBlocks](http://microblocks.fun) is a free, live, blocks programming system
for educators and makers that aims to be "the Scratch of physical computing."
It runs on the micro:bit, Raspberry Pi Pico (RP2040), Calliope mini,
Adafruit CircuitPlayground Express and Bluefruit,
ESP8266, ESP32, many other microcontrollers.

The MicroBlock firmware (or *virtual machine*) runs on 32-bit embedded processors
with as little as 16k of RAM. It is intended to be simple,
easily ported and extended, and offer decent performance.
It includes a low-latency task scheduler that works at timescales down to ~50 microseconds
and a garbage collected memory that allows working with dynamic lists and strings – within
the limits of the available RAM, of course!

MicroBlocks supports both *live* development and *autonomous operation*.
Live development allows the user to test program changes instantly,
without restarting or waiting for the program to compile and download.
Autonomous operation means that programs continue to run when the board
is untethered from the host computer. Because MicroBlocks programs run
directly on the microcontroller -- in contrast to tethered systems where
the program runs on a laptop and uses the microcontroller as an I/O device --
programs can work precisely at timescales down to 10's of microseconds.
For example, MicroBlocks can generate musical tones and servo waveforms
and it can analyze incoming signals such as those from an infrared remote
control.

Finally, since MicroBlocks stores the user's program in persistent Flash memory,
MicroBlocks allows a program stored on the board to be read back into the
development environment for inspection and further development.

MicroBlocks supports user-defined blocks (commands and functions).
That mechanism is used to create MicroBlocks libraries. Advanced
users can explore the implementation of these libraries to learn how
they work, to extend them, or to create their own libraries.

Built-in data types include integers, booleans, strings, lists, and byte arrays.
Floating point numbers are not supported since many microcontrollers lack
floating point hardware. However, the lack of floating point is seldom missed;
most physical computing projects don't require them.

## How do I build the MicroBlocks firmware? ##

First of all, you may not need to. The firmware for many boards can be installed
using the "update firmware on board" menu command
in the MicroBlocks interactive development environment (IDE).

However, if you have one of the
[community supported boards](https://bitbucket.org/john_maloney/smallvm/wiki/Devices),
or if you just want to build the firmware yourself, read on.

The MicroBlocks firmware, or **virtual machine**, is written in C and C++.
It is built on the Arduino platform and uses additional Arduino libraries for
features such as graphics and WiFi on boards that support those features.

The source code repository is [here](https://bitbucket.org/john_maloney/smallvm/src/master/).
To get the source code, you can either clone it:

    git clone https://john_maloney@bitbucket.org/john_maloney/smallvm.git

or download a snapshot of it by selecting "download repository" from the "..." menu to the right
of the "Clone" button on the repository home page.

### Building with PlatformIO ###

PlatformIO is the preferred build tool. PlatformIO is a cross platform build system
that is easy to install an use. Its only dependency is Python, which comes pre-installed
on MacOS and Linux and is easy to install on Windows.
You can get the PlatformIO command line interface (CLI) tools
[here](https://platformio.org/install/cli).

To compile the firmware for all platforms, just enter the "smallvm" folder and run:

    pio run

To compile and install the VM for a particular board (e.g. the micro:bit),
plug in the board and run:

    pio run -e microbit -t upload

Look at platformio.ini to see which boards are supported and what they are called.

### Building with the Arduino IDE ###

The MicroBlocks virtual machine can also be compiled and loaded onto a board using the
Arduino IDE (version 1.8 or later) with the appropriate board package and libraries
installed.

To build with the Arduino IDE, open the file *vm.ino*, select your board from the
boards manager, then click the upload button.

### Building for Raspberry Pi ###

To build the VM on the Raspberry Pi, run "./build" in the raspberryPi folder.
The Raspberry Pi version of MicroBlocks can control the digital I/O
pins of the Raspberry Pi.

On the Raspberry Pi, MicroBlocks can be run in two ways:

##### Desktop: #####

If you run ublocks-pi with the "-p" switch,
it will create a pseudo terminal, and you can connect to that pseudo terminal
from the MicroBlocks IDE running in a window on the same Raspberry Pi.

##### Headless: #####

This is more involved.
If you configure your RaspberryPi Zero(W) to behave like a slave USB-serial
device, then it can be plugged into a laptop as if it were an Arduino or micro:bit.
The MicroBlocks VM can be started on a headless Pi either by connecting
to the Pi via SSH and running ublocks-pi from the command line
or by configuring Linux to start the VM at boot time.

### Building for generic Linux ###

To build the VM to run on a generic Linux computer, run "./build" in the linux folder.
Running the resulting executable creates a pseudo terminal that you can connect
to from the MicroBlocks IDE running on the same computer.

The generic Linux version of the VM can't control pins or other microcontroller I/O devices
(there aren't any!), but it can be used to study the virtual machine.
It's also handy for debugging, since the Linux VM can print debugging information
to stdout without interfering with the VM-IDE communications (which goes over
the pseudo terminal connection).

## MicroBlocks IDE ##

The MicroBlocks IDE is written in [GP Blocks](https://gpblocks.org).
You'll find source code for the IDE in the ide
and the gp/runtime folders and build scripts in the the gp folder.

## Status ##

MicroBlocks is currently used by thousands of people, many of them complete beginners.

There are two release streams available on the download page.

The **stable release** is updated only a few times a year.
The stable release is meant for educators who require
stability and consistency.

**Pilot releases** are updated frequently.
Pilot release contain the latest features and improvements but may also introduce bugs or experimental features that are later removed or changed.

The **web application**, which runs in a Chrome or Edge web browser, tracks the pilot release,
sometimes with a short time lag for testing.

## Contributing ##

We welcome your feedback, comments, feature requests, and
[bug reports](https://bitbucket.org/john_maloney/smallvm/issues?status=new&status=open).

Since MicroBlocks is still under active development by the core team, we are not currently
soliciting code contributions or pull requests. However, if you are creating tutorials or other materials for MicroBlocks, please let us know so we can link to your website.

## Team ##

This project is a collaboration between John Maloney, Bernat Romagosa, and Jens Mönig,
with input and help from many others. It is under the fiscal sponsorship of the
[Software Freedom Conservancy](https://sfconservancy.org), a 501(c)(3) non-profit.

## License ##

MicroBlocks is licensed under the Mozilla Public License 2.0 (MPL 2.0).
