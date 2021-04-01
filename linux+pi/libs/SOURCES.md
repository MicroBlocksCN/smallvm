To make building the VM on Linux easier and ensure the same result in different
operating systems, this directory contains precompiled binaries for the
following libraries:

File: libfreetype.a
Library: FreeType
License: GPLv2 (https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)
Sources: https://www.freetype.org/developer.html

File: libSDL2.a
Library: Simple DirectMedia Layer 2 (SDL2)
License: zlib (https://www.zlib.net/zlib_license.html)
Sources: https://www.libsdl.org/hg.php

File: libSDL2_ttf.a
Library: SDL_ttf 2.0
License: zlib (https://www.zlib.net/zlib_license.html)
Sources: https://www.libsdl.org/projects/SDL_ttf/

The libraries were built on Ubuntu 16.04 LTS (32-bit).

SDL2 was configured:
  ./configure --disable-video-opengl --disable-video-vulkan --disable-dbus
