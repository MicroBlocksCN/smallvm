:; if [ uname = 'Linux' ]; then
:;      command=esptool.py
:; else
:;      command=esptool
:; fi
:; /tmp/$command erase_flash; /tmp/$command write_flash 0xe00 /tmp/boot_app0.bin; /tmp/$command write_flash 0x1000 /tmp/bootloader_dio_80m.bin; /tmp/$command write_flash 0x8000 /tmp/partitions.bin; /tmp/$command write_flash 0x10000 /tmp/vm
:; exit 0
%temp%\esptool.exe erase_flash
%temp%\esptool.exe write_flash 0xe00 %temp%\boot_app0.bin
%temp%\esptool.exe write_flash 0x1000 %temp%\bootloader_dio_80m.bin
%temp%\esptool.exe write_flash 0x8000 %temp%\partitions.bin
%temp%\esptool.exe write_flash 0x10000 %temp%\vm
